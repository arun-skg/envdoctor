defmodule Envdoctor.Runtime.Compare do
  @moduledoc """
  Pure comparison of two runtime snapshots. `capturedAt` is ignored.

  Status for each item is one of `"same"`, `"different"`, `"onlyA"`, `"onlyB"`.
  """

  @doc "Compare two snapshots, returning a drift report map."
  def compare(a, b) do
    tools = diff_tools(a.tools, b.tools)
    path_only_a = only_in(a.path, b.path)
    path_only_b = only_in(b.path, a.path)

    path_reordered =
      path_only_a == [] and path_only_b == [] and a.path != b.path

    globals = diff_globals(a.globals, b.globals)
    env_flag_only_a = only_in(a.envFlagNames, b.envFlagNames)
    env_flag_only_b = only_in(b.envFlagNames, a.envFlagNames)

    os_same =
      a.os.platform == b.os.platform and a.os.arch == b.os.arch and
        a.os.release == b.os.release

    equivalent =
      Enum.all?(tools, &(&1.status == "same")) and not path_reordered and
        path_only_a == [] and path_only_b == [] and globals == []

    %{
      os: %{
        status: if(os_same, do: "same", else: "different"),
        a: fmt_os(a),
        b: fmt_os(b)
      },
      tools: tools,
      pathReordered: path_reordered,
      pathOnlyA: path_only_a,
      pathOnlyB: path_only_b,
      globals: globals,
      envFlagOnlyA: env_flag_only_a,
      envFlagOnlyB: env_flag_only_b,
      equivalent: equivalent
    }
  end

  defp fmt_os(s), do: "#{s.os.platform}/#{s.os.arch} #{s.os.release}"

  defp status_for(nil, nil), do: "same"
  defp status_for(nil, _b), do: "onlyB"
  defp status_for(_a, nil), do: "onlyA"
  defp status_for(a, b), do: if(a == b, do: "same", else: "different")

  defp diff_tools(tools_a, tools_b) do
    av = Map.new(tools_a, &{&1.tool, &1.version})
    bv = Map.new(tools_b, &{&1.tool, &1.version})

    (Map.keys(av) ++ Map.keys(bv))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn name ->
      %{name: name, status: status_for(av[name], bv[name]), a: av[name], b: bv[name]}
    end)
  end

  defp diff_globals(globals_a, globals_b) do
    (Map.keys(globals_a) ++ Map.keys(globals_b))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn eco ->
      av = globals_a |> Map.get(eco, []) |> Map.new(&{&1.name, &1.version})
      bv = globals_b |> Map.get(eco, []) |> Map.new(&{&1.name, &1.version})

      (Map.keys(av) ++ Map.keys(bv))
      |> Enum.uniq()
      |> Enum.map(fn name ->
        status = status_for(av[name], bv[name])

        if status == "same" do
          nil
        else
          %{ecosystem: eco, name: name, status: status, a: av[name], b: bv[name]}
        end
      end)
      |> Enum.reject(&is_nil/1)
    end)
    |> Enum.sort_by(& &1.name)
  end

  # Set difference preserving A's order.
  defp only_in(a, b) do
    set = MapSet.new(b)
    Enum.reject(a, &MapSet.member?(set, &1))
  end
end
