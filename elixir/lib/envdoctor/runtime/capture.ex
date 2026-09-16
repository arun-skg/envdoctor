defmodule Envdoctor.Runtime.Capture do
  @moduledoc """
  Capture this machine's live runtime into a snapshot. Never records any
  environment variable **value** — only non-secret names in `envFlagNames`,
  and secret-looking names are dropped entirely.
  """

  alias Envdoctor.Scanner

  @snapshot_schema 1

  # First dotted version-looking token in a tool's output.
  @version_re ~r/(\d+\.\d+(?:\.\d+)?)/

  # Tools probed by default. Order here is irrelevant; results are sorted.
  @tool_probes [
    {"node", ["-v"]},
    {"python3", ["--version"]},
    {"python", ["--version"]},
    {"go", ["version"]},
    {"rustc", ["-V"]},
    {"java", ["-version"]},
    {"ruby", ["-v"]},
    {"php", ["-v"]},
    {"perl", ["-v"]},
    {"cc", ["--version"]},
    {"git", ["--version"]}
  ]

  @doc "Snapshot schema version; `snapshot-diff` refuses tokens from newer versions."
  def snapshot_schema, do: @snapshot_schema

  @doc "Capture the live runtime. Pass `globals: true` for the npm package inventory."
  def capture(opts \\ []) do
    tools = collect_tools()
    globals = if Keyword.get(opts, :globals, false), do: collect_globals(), else: %{}
    {platform, arch, release} = os_info()

    %{
      schema: @snapshot_schema,
      capturedAt: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      os: %{platform: platform, arch: arch, release: release},
      tools: tools,
      path: collect_path(),
      globals: globals,
      envFlagNames: collect_env_flag_names()
    }
  end

  defp os_info do
    platform =
      case :os.type() do
        {:unix, :darwin} -> "darwin"
        {:unix, :linux} -> "linux"
        {:unix, :freebsd} -> "freebsd"
        {:win32, _} -> "win32"
        {:unix, other} -> Atom.to_string(other)
        {family, _} -> Atom.to_string(family)
      end

    arch =
      case :erlang.system_info(:system_architecture) |> to_string() |> String.split("-") do
        ["aarch64" | _] -> "arm64"
        ["x86_64" | _] -> "x64"
        [other | _] -> other
      end

    release =
      case :os.type() do
        {:unix, _} ->
          case System.cmd("uname", ["-r"], stderr_to_stdout: false) do
            {out, 0} -> String.trim(out)
            _ -> ""
          end

        _ ->
          ""
      end

    {platform, arch, release}
  rescue
    _ -> {platform_fallback(), "", ""}
  end

  defp platform_fallback do
    case :os.type() do
      {:unix, name} -> Atom.to_string(name)
      {family, _} -> Atom.to_string(family)
    end
  end

  @doc "Collapse a leading $HOME to \"~\" so snapshots don't leak usernames."
  def collapse_home(p) do
    case System.user_home() do
      nil ->
        p

      home ->
        if p == home or String.starts_with?(p, home <> "/") do
          "~" <> String.slice(p, byte_size(home)..-1//1)
        else
          p
        end
    end
  end

  @doc "Ordered, de-duplicated `$PATH` entries with $HOME collapsed. Order is significant."
  def collect_path(path_env \\ System.get_env("PATH") || "") do
    path_env
    |> String.split(":")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&collapse_home/1)
    |> Enum.uniq()
  end

  @doc "Non-secret env var NAMES only. Secret-looking names are dropped, not masked."
  def collect_env_flag_names(env \\ System.get_env()) do
    env
    |> Map.keys()
    |> Enum.reject(&Scanner.secret_name?/1)
    |> Enum.sort()
  end

  @doc "Probe one CLI's version; nil when the tool isn't installed or misbehaves."
  def probe_version(tool, args) do
    with path when is_binary(path) <- System.find_executable(tool),
         {out, _} <- run_quietly(path, args),
         [_, version] <- Regex.run(@version_re, out) do
      version
    else
      _ -> nil
    end
  end

  defp run_quietly(executable, args) do
    task =
      Task.async(fn ->
        try do
          System.cmd(executable, args, stderr_to_stdout: true)
        rescue
          _ -> {"", 1}
        catch
          :exit, _ -> {"", 1}
        end
      end)

    case Task.yield(task, 4_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, {out, _}} -> {out, 0}
      _ -> nil
    end
  end

  @doc "Locate which PATH directory a command resolves from, $HOME collapsed."
  def resolve_from(tool) do
    case System.find_executable(tool) do
      nil -> ""
      path -> path |> Path.dirname() |> collapse_home()
    end
  end

  @doc "Probe every known tool; only installed ones appear in the result."
  def collect_tools do
    @tool_probes
    |> Enum.flat_map(fn {tool, args} ->
      case probe_version(tool, args) do
        nil -> []
        version -> [%{tool: tool, version: version, resolvedFrom: resolve_from(tool)}]
      end
    end)
    |> Enum.sort_by(& &1.tool)
  end

  @doc "Global npm package inventory, opt-in (`--globals`) because it is slow."
  def collect_globals do
    case System.find_executable("npm") do
      nil ->
        %{}

      npm ->
        task =
          Task.async(fn ->
            try do
              System.cmd(npm, ["ls", "-g", "--depth=0", "--json"], stderr_to_stdout: false)
            rescue
              _ -> {"", 1}
            catch
              :exit, _ -> {"", 1}
            end
          end)

        case Task.yield(task, 15_000) || Task.shutdown(task, :brutal_kill) do
          {:ok, {out, 0}} ->
            case Envdoctor.Json.decode(out) do
              {:ok, %{"dependencies" => deps}} when is_map(deps) ->
                pkgs =
                  deps
                  |> Enum.map(fn {name, meta} ->
                    %{name: name, version: if(is_map(meta), do: Map.get(meta, "version", ""), else: "")}
                  end)
                  |> Enum.sort_by(& &1.name)

                if pkgs == [], do: %{}, else: %{npm: pkgs}

              _ ->
                %{}
            end

          _ ->
            %{}
        end
    end
  end
end
