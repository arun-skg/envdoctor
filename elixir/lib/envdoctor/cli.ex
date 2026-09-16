defmodule Envdoctor.CLI do
  @moduledoc """
  Command-line entry point for the native Elixir envdoctor (escript).

  Subcommands: `scan`, `diff`, `sync`, `init`, `fix`, `snapshot`,
  `snapshot-diff`. Exit codes: 0 = clean, 1 = issues found, 2 = usage error.
  """

  alias Envdoctor.{Json, Scanner}
  alias Envdoctor.Runtime.{Capture, Compare, Token}
  alias Envdoctor.Scanner.ScanResult

  @red IO.ANSI.red()
  @yellow IO.ANSI.yellow()
  @dim IO.ANSI.faint()
  @reset IO.ANSI.reset()

  @exit_ok 0
  @exit_issues 1
  @exit_usage 2

  @doc "escript entry point."
  def main(argv) do
    argv
    |> run()
    |> then(&System.halt/1)
  end

  @doc "Run the CLI and return the exit code (testable, does not halt)."
  def run(argv) do
    case argv do
      ["scan" | rest] -> run_scan(rest)
      ["diff" | rest] -> run_diff(rest)
      ["sync" | rest] -> run_sync(rest)
      ["init" | rest] -> run_init(rest)
      ["fix" | rest] -> run_fix(rest)
      ["snapshot" | rest] -> run_snapshot(rest)
      ["snapshot-diff" | rest] -> run_snapshot_diff(rest)
      ["--version"] -> puts("envdoctor #{Envdoctor.version()}")
      ["-v"] -> puts("envdoctor #{Envdoctor.version()}")
      ["--help"] -> print_help()
      ["-h"] -> print_help()
      [] -> print_help()
      _ -> print_help()
    end
  end

  defp puts(text) do
    IO.puts(text)
    @exit_ok
  end

  defp print_help do
    IO.puts("""
    envdoctor — local-first consistency checker for environment variables.

    Usage:
      envdoctor scan [-d DIR] [--strict] [--no-color] [--json] [--ext ex,exs]
      envdoctor diff <envA> <envB> [-d DIR] [--json]
      envdoctor sync <from> <to> [-d DIR] [--dry-run] [--json]
      envdoctor init [-d DIR] [--force]
      envdoctor fix [-d DIR]
      envdoctor snapshot [--json] [--token] [--output FILE] [--globals]
      envdoctor snapshot-diff <a> <b> [--json]

    Exit codes: 0 = clean, 1 = issues found, 2 = usage error.
    """)

    @exit_ok
  end

  # ---------------------------------------------------------------------------
  # scan
  # ---------------------------------------------------------------------------

  defp run_scan(args) do
    opts = parse_opts(args, %{dir: ".", strict: false, no_color: false, json: false, ext: nil})

    root = Path.expand(opts.dir)
    extensions = extensions(opts.ext)
    result = Scanner.scan(root, extensions)

    if opts.json do
      result.findings
      |> Enum.map(&Scanner.finding_to_map(&1, root))
      |> Json.encode!()
      |> IO.puts()
    else
      IO.puts(format_report(result, root, not opts.no_color))
    end

    if ScanResult.errors(result) != [] or (opts.strict and ScanResult.warnings(result) != []) do
      @exit_issues
    else
      @exit_ok
    end
  end

  defp extensions(nil), do: Scanner.default_extensions()
  defp extensions(ext), do: ext |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

  @doc "Human-readable audit report. Values never appear."
  def format_report(%ScanResult{} = result, root, use_color \\ true) do
    lines = ["ENVIRONMENT AUDIT", String.duplicate("=", 40), ""]

    if result.findings == [] do
      Enum.join(lines ++ ["No issues found."], "\n")
    else
      errors = ScanResult.errors(result)
      warnings = ScanResult.warnings(result)

      lines =
        if errors != [] do
          entries =
            Enum.map(errors, fn f ->
              "  x #{f.name}#{location(f, root, use_color)}  #{f.message}"
            end)

          lines ++ [color("Errors", @red, use_color)] ++ entries ++ [""]
        else
          lines
        end

      lines =
        if warnings != [] do
          entries =
            Enum.map(warnings, fn f ->
              "  ! #{f.name}#{location(f, root, use_color)}  #{f.message}"
            end)

          lines ++ [color("Warnings", @yellow, use_color)] ++ entries ++ [""]
        else
          lines
        end

      lines = lines ++ ["Summary: #{length(errors)} error(s), #{length(warnings)} warning(s)"]
      Enum.join(lines, "\n")
    end
  end

  defp location(%{origin: nil}, _root, _color), do: ""

  defp location(%{origin: %{file: file, line: line}}, root, use_color) do
    rel = Path.relative_to(file, root)
    " " <> color("#{rel}:#{line}", @dim, use_color)
  end

  defp color(text, code, true), do: code <> text <> @reset
  defp color(text, _code, false), do: text

  # ---------------------------------------------------------------------------
  # diff / sync
  # ---------------------------------------------------------------------------

  defp run_diff(args) do
    {pos, opts} = parse_positional(args, %{dir: ".", json: false})

    case pos do
      [a, b | _] ->
        root = Path.expand(opts.dir)
        d = Scanner.diff_labels(root, a, b)

        if opts.json do
          IO.puts(Json.encode!(Map.merge(%{"a" => a, "b" => b}, d)))
        else
          lines = ["ENVIRONMENT DIFF: #{a} vs #{b}", String.duplicate("=", 40)]

          lines =
            if d["onlyInA"] != [] do
              lines ++ ["Only in #{a}:"] ++ Enum.map(d["onlyInA"], &"  + #{&1}")
            else
              lines
            end

          lines =
            if d["onlyInB"] != [] do
              lines ++ ["Only in #{b}:"] ++ Enum.map(d["onlyInB"], &"  + #{&1}")
            else
              lines
            end

          IO.puts(Enum.join(lines ++ ["Common: #{length(d["common"])} variable(s)"], "\n"))
        end

        @exit_ok

      _ ->
        IO.puts(:stderr, "usage: envdoctor diff <a> <b>")
        @exit_usage
    end
  end

  defp run_sync(args) do
    {pos, opts} = parse_positional(args, %{dir: ".", json: false, dry_run: false})

    case pos do
      [from, to | _] ->
        root = Path.expand(opts.dir)
        added = Scanner.sync_labels(root, from, to, opts.dry_run)

        if opts.json do
          IO.puts(Json.encode!(%{"from" => from, "to" => to, "added" => added, "dryRun" => opts.dry_run}))
        else
          cond do
            added == [] ->
              IO.puts("Already in sync.")

            true ->
              verb = if opts.dry_run, do: "Would sync", else: "Synced"
              IO.puts("#{verb} #{length(added)} variable(s) from #{from} to #{to}:")
              IO.puts(Enum.map_join(added, "\n", &"  + #{&1}"))
          end
        end

        @exit_ok

      _ ->
        IO.puts(:stderr, "usage: envdoctor sync <from> <to>")
        @exit_usage
    end
  end

  # ---------------------------------------------------------------------------
  # init / fix
  # ---------------------------------------------------------------------------

  defp run_init(args) do
    opts = parse_opts(args, %{dir: ".", force: false, ext: nil})
    root = Path.expand(opts.dir)
    docs = Scanner.generate_docs(root, extensions(opts.ext))

    Enum.each(Scanner.generated_files(), fn name ->
      target = Path.join(root, name)

      cond do
        opts.force ->
          File.write!(target, docs[name])
          IO.puts("wrote #{name}")

        File.exists?(target) ->
          IO.puts("skipped #{name} (exists)")

        true ->
          File.write!(target, docs[name])
          IO.puts("created #{name}")
      end
    end)

    @exit_ok
  end

  defp run_fix(args) do
    opts = parse_opts(args, %{dir: ".", ext: nil})
    root = Path.expand(opts.dir)
    docs = Scanner.generate_docs(root, extensions(opts.ext))

    Enum.each(Scanner.generated_files(), fn name ->
      File.write!(Path.join(root, name), docs[name])
      IO.puts("wrote #{name}")
    end)

    @exit_ok
  end

  # ---------------------------------------------------------------------------
  # snapshot / snapshot-diff
  # ---------------------------------------------------------------------------

  defp run_snapshot(args) do
    opts = parse_opts(args, %{json: false, token: false, output: nil, globals: false})
    snapshot = Capture.capture(globals: opts.globals)

    if opts.output do
      dest = Path.expand(opts.output)
      File.write!(dest, Json.pretty(snapshot))
      IO.puts(:stderr, "✓ Snapshot written to #{opts.output}")
    end

    cond do
      opts.json ->
        IO.write(Json.pretty(snapshot))

      opts.token ->
        IO.puts(Token.encode(snapshot))

      true ->
        render_snapshot(snapshot, opts.globals)
    end

    @exit_ok
  end

  defp render_snapshot(snapshot, globals_flag) do
    title = "RUNTIME SNAPSHOT"
    IO.puts(title)
    IO.puts(String.duplicate("=", title |> String.length() |> Kernel.*(2)))
    IO.puts("")
    IO.puts("  OS  #{snapshot.os.platform}/#{snapshot.os.arch} #{snapshot.os.release}")
    IO.puts("")
    IO.puts("  Tools")

    if snapshot.tools == [] do
      IO.puts("  none detected")
    else
      Enum.each(snapshot.tools, fn t ->
        IO.puts("  ✓ #{String.pad_trailing(t.tool, 8)} #{t.version}  #{t.resolvedFrom}")
      end)
    end

    IO.puts("")
    IO.puts("  PATH (#{length(snapshot.path)} entries)")

    snapshot.path
    |> Enum.take(12)
    |> Enum.with_index(1)
    |> Enum.each(fn {p, i} -> IO.puts("  #{i |> Integer.to_string() |> String.pad_leading(2)}  #{p}") end)

    if length(snapshot.path) > 12 do
      IO.puts("  … #{length(snapshot.path) - 12} more")
    end

    ecosystems = Map.keys(snapshot.globals)

    cond do
      ecosystems != [] ->
        IO.puts("")
        IO.puts("  Globals")
        Enum.each(ecosystems, fn eco -> IO.puts("  #{eco}: #{length(snapshot.globals[eco])} packages") end)

      not globals_flag ->
        IO.puts("")
        IO.puts("  Globals omitted — pass --globals to include the package inventory.")

      true ->
        :ok
    end

    IO.puts("")
    IO.puts("  Share with:  envdoctor snapshot --token   ·   compare with:  envdoctor snapshot-diff <a> <b>")
  end

  defp run_snapshot_diff(args) do
    {pos, opts} = parse_positional(args, %{dir: ".", json: false})

    case pos do
      [a_arg, b_arg | _] ->
        with {:ok, a} <- load_snapshot(opts.dir, a_arg),
             {:ok, b} <- load_snapshot(opts.dir, b_arg) do
          diff = Compare.compare(a, b)

          if opts.json do
            out = Map.merge(%{exitCode: if(diff.equivalent, do: 0, else: 1)}, diff)
            IO.write(Json.pretty(out))
          else
            render_runtime_diff(diff)
          end

          if diff.equivalent, do: @exit_ok, else: @exit_issues
        else
          {:error, msg} ->
            IO.puts(:stderr, "error #{msg}")
            @exit_usage
        end

      _ ->
        IO.puts(:stderr, "usage: envdoctor snapshot-diff <a> <b>")
        @exit_usage
    end
  end

  # Resolve a positional arg that may be a token string or a file path.
  defp load_snapshot(root, arg) do
    if String.trim(arg) |> String.starts_with?("envd1:") do
      Token.decode(arg)
    else
      file = Path.expand(arg, root)

      if File.exists?(file) do
        file |> File.read!() |> Token.parse_json()
      else
        {:error, "Not a snapshot token, and file not found: #{arg}"}
      end
    end
  end

  defp render_runtime_diff(diff) do
    title = "RUNTIME DIFF"
    IO.puts(title)
    IO.puts(String.duplicate("=", String.length(title) * 2))
    IO.puts("")
    IO.puts("  A → B")
    IO.puts("")

    if diff.os.status == "same" do
      IO.puts("  = OS  #{diff.os.a}")
    else
      IO.puts("  ≠ OS  #{diff.os.a} → #{diff.os.b}")
    end

    IO.puts("")
    IO.puts("  Tools")

    Enum.each(diff.tools, fn t ->
      name = String.pad_trailing(t.name, 8)

      case t.status do
        "same" -> IO.puts("  = #{name} #{t.a}")
        "different" -> IO.puts("  ≠ #{name} #{t.a} → #{t.b}")
        "onlyA" -> IO.puts("  - #{name} missing in B (A: #{t.a})")
        "onlyB" -> IO.puts("  - #{name} missing in A (B: #{t.b})")
      end
    end)

    if diff.pathReordered or diff.pathOnlyA != [] or diff.pathOnlyB != [] do
      IO.puts("")
      IO.puts("  PATH")
      if diff.pathReordered, do: IO.puts("  ≠ same entries, different order")
      Enum.each(diff.pathOnlyA, &IO.puts("  - only in A: #{&1}"))
      Enum.each(diff.pathOnlyB, &IO.puts("  - only in B: #{&1}"))
    end

    if diff.globals != [] do
      IO.puts("")
      IO.puts("  Globals")

      Enum.each(diff.globals, fn g ->
        label = "#{g.ecosystem}:#{g.name}"

        case g.status do
          "different" -> IO.puts("  ≠ #{label}  #{g.a} → #{g.b}")
          "onlyA" -> IO.puts("  - #{label}  missing in B")
          "onlyB" -> IO.puts("  - #{label}  missing in A")
        end
      end)
    end

    IO.puts("")

    if diff.equivalent do
      IO.puts("  ✓ runtimes are equivalent")
    else
      IO.puts("  ✗ runtime drift detected")
    end
  end

  # ---------------------------------------------------------------------------
  # Argument parsing
  # ---------------------------------------------------------------------------

  # Flag-style parsing for scan/init/fix/snapshot.
  defp parse_opts(args, defaults) do
    Enum.reduce(args, defaults, fn
      "-d", acc -> put_in(acc, [:_next], :dir)
      "--dir", acc -> put_in(acc, [:_next], :dir)
      "--strict", acc -> Map.put(acc, :strict, true)
      "--no-color", acc -> Map.put(acc, :no_color, true)
      "--json", acc -> Map.put(acc, :json, true)
      "--force", acc -> Map.put(acc, :force, true)
      "--token", acc -> Map.put(acc, :token, true)
      "--globals", acc -> Map.put(acc, :globals, true)
      "--ext", acc -> put_in(acc, [:_next], :ext)
      "--output", acc -> put_in(acc, [:_next], :output)
      "-o", acc -> put_in(acc, [:_next], :output)
      <<"--dir=", value::binary>>, acc -> Map.put(acc, :dir, value)
      <<"--ext=", value::binary>>, acc -> Map.put(acc, :ext, value)
      <<"--output=", value::binary>>, acc -> Map.put(acc, :output, value)
      value, %{_next: key} = acc -> acc |> Map.delete(:_next) |> Map.put(key, value)
      _unknown, acc -> acc
    end)
    |> Map.delete(:_next)
  end

  # Positional + shared flags for diff/sync/snapshot-diff.
  defp parse_positional(args, defaults) do
    {pos, opts} =
      Enum.reduce(args, {[], defaults}, fn
        "-d", {pos, acc} -> {pos, put_in(acc, [:_next], :dir)}
        "--dir", {pos, acc} -> {pos, put_in(acc, [:_next], :dir)}
        "--dry-run", {pos, acc} -> {pos, Map.put(acc, :dry_run, true)}
        "--json", {pos, acc} -> {pos, Map.put(acc, :json, true)}
        <<"--dir=", value::binary>>, {pos, acc} -> {pos, Map.put(acc, :dir, value)}
        value, {pos, %{_next: key} = acc} -> {pos, acc |> Map.delete(:_next) |> Map.put(key, value)}
        value, {pos, acc} -> {pos ++ [value], acc}
      end)

    {pos, Map.delete(opts, :_next)}
  end
end
