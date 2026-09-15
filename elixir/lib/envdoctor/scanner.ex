defmodule Envdoctor.Scanner do
  @moduledoc """
  Core environment-variable consistency scanner (native Elixir port).

  Local-first: reads `.env` files and scans Elixir source for environment
  access, then reconciles the two. No network, no telemetry, and variable
  **values are never printed** — they are used only for detection.
  """

  # Source usage patterns. Each captures the variable name in group 1.
  @usage_patterns [
    ~r/\bSystem\.get_env\(\s*"([A-Za-z_]\w*)"/,
    ~r/\bSystem\.fetch_env!?\(\s*"([A-Za-z_]\w*)"/
  ]

  # JavaScript/TypeScript usage patterns (used when scanning js/ts extensions).
  @js_usage_patterns [
    ~r/\bprocess\.env\.([A-Za-z_$][\w$]*)/,
    ~r/\bprocess\.env\[['"]([A-Za-z_$][\w$]*)['"]\]/,
    ~r/\bimport\.meta\.env\.([A-Za-z_$][\w$]*)/
  ]

  # Heredocs are stripped so example code inside them is ignored.
  @heredoc ~r/""".*?"""|'''.*?'''/s
  @line_comment ~r/#[^\n]*/

  @js_line_comment ~r{//[^\n]*}
  @js_block_comment ~r{/\*.*?\*/}s

  # --- Infra source scanning (Docker Compose / GitHub Actions / Kubernetes) ---
  @compose_basename ~r/^(docker-)?compose([.-].*)?\.ya?ml$/i
  @interp_brace ~r/\$\{([A-Za-z_][A-Za-z0-9_]*)/
  @interp_bare ~r/\$([A-Za-z_][A-Za-z0-9_]*)/
  @actions_ref ~r/\b(?:secrets|vars|env)\.([A-Za-z_][A-Za-z0-9_]*)/
  @k8s_api_version ~r/^apiVersion:/m
  @k8s_kind ~r/^kind:/m
  @infra_skip_dirs [".git", "vendor", "node_modules", "target", "deps", "_build"]
  @source_skip_dirs [".git", "__pycache__", ".venv", "node_modules", "deps", "_build"]

  @env_line ~r/^\s*(?:export\s+)?([A-Za-z_]\w*)\s*=(.*)$/

  # Public/client-exposed environment prefixes (case-sensitive, exact).
  @public_prefixes [
    "NEXT_PUBLIC_",
    "VITE_",
    "REACT_APP_",
    "EXPO_PUBLIC_",
    "GATSBY_",
    "NUXT_PUBLIC_",
    "VUE_APP_",
    "PUBLIC_"
  ]

  # Secret-looking name pattern (case-insensitive).
  @secret_name ~r/SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE|CREDENTIAL|API_?KEY|ACCESS_?KEY|AUTH/i

  # Weak/placeholder secret value pattern (case-insensitive, whole-value).
  @weak_secret_value ~r/^(changeme|change_me|placeholder|x{3,}|todo|secret|password|passwd|test|example|sample|dummy|your[_-].*|<.*>|\$\{.*\})$/i

  @int_re ~r/^-?\d+$/
  @float_re ~r/^-?\d+\.\d+$/
  @url_re ~r/^https?:\/\//i
  @numeric ~r/^-?\d+(\.\d+)?$/

  # Generated docs, in output order.
  @generated_files [".env.example", "ENVIRONMENT.md"]

  @default_extensions ["ex", "exs"]

  defmodule Origin do
    @moduledoc "Where a variable was defined or referenced."
    defstruct file: nil, line: nil

    @type t :: %__MODULE__{file: Path.t() | nil, line: non_neg_integer() | nil}
  end

  defmodule Finding do
    @moduledoc "A single audit finding. Never carries a variable value."
    defstruct rule: nil, severity: nil, name: nil, message: nil, origin: nil

    @type t :: %__MODULE__{
            rule: String.t(),
            severity: String.t(),
            name: String.t(),
            message: String.t(),
            origin: Origin.t() | nil
          }
  end

  defmodule ScanResult do
    @moduledoc "All findings from a scan, split by severity."
    defstruct findings: []

    @type t :: %__MODULE__{findings: [Finding.t()]}

    def errors(%__MODULE__{findings: fs}), do: Enum.filter(fs, &(&1.severity == "error"))
    def warnings(%__MODULE__{findings: fs}), do: Enum.filter(fs, &(&1.severity == "warning"))
  end

  def generated_files, do: @generated_files
  def default_extensions, do: @default_extensions

  # ---------------------------------------------------------------------------
  # Small pure helpers
  # ---------------------------------------------------------------------------

  @doc "Blank heredocs and comments while preserving line structure."
  def strip_noise(code) do
    code
    |> blank_matches(@heredoc)
    |> blank_matches(@line_comment)
  end

  @doc "Blank JS line/block comments while preserving line structure."
  def strip_js_noise(code) do
    code
    |> blank_matches(@js_block_comment)
    |> blank_matches(@js_line_comment)
  end

  defp blank_matches(text, regex) do
    Regex.replace(regex, text, fn match -> blank(match) end)
  end

  defp blank(match), do: String.replace(match, ~r/[^\n]/, " ")

  # Split like Python's str.splitlines(): trailing newline does not yield an
  # extra empty line.
  defp split_lines(text) do
    lines = String.split(text, ~r/\r?\n/)
    if List.last(lines) == "", do: Enum.drop(lines, -1), else: lines
  end

  @doc "Trim the right-hand side and strip one matching pair of surrounding quotes."
  def parse_value(raw_rhs) do
    v = String.trim(raw_rhs)

    if String.length(v) >= 2 and String.first(v) == String.last(v) and
         String.first(v) in ["'", "\""] do
      v |> String.slice(1..-2//1)
    else
      v
    end
  end

  @doc "Derive an environment label from a dotenv filename."
  def env_label(".env"), do: "default"

  def env_label(filename) do
    rest = String.replace_prefix(filename, ".env.", "")

    cond do
      rest == "local" -> "local"
      String.ends_with?(rest, ".local") -> String.slice(rest, 0, byte_size(rest) - 6)
      true -> rest
    end
  end

  @doc "Infer a coarse type from a value string."
  def infer_type(""), do: "empty"
  def infer_type(value) do
    cond do
      Regex.match?(@int_re, value) -> "integer"
      Regex.match?(@float_re, value) -> "float"
      String.downcase(value) in ["true", "false"] -> "boolean"
      Regex.match?(@url_re, value) -> "url"
      json_like?(value) -> "json"
      true -> "string"
    end
  end

  defp json_like?(<<first::utf8, _::binary>> = value) when first in [?{, ?[] do
    match?({:ok, _}, safe_json_decode(value))
  end

  defp json_like?(_), do: false

  defp safe_json_decode(value) do
    {:ok, :json.decode(value)}
  rescue
    _ -> :error
  end

  @doc "Map an inferred type to its compatibility group."
  def compat_group(inferred) when inferred in ["integer", "float"], do: "numeric"
  def compat_group(inferred), do: inferred

  @doc "Classic dynamic-programming Levenshtein edit distance."
  def levenshtein(a, b) when a == b, do: 0

  def levenshtein(a, b) do
    cs_a = String.graphemes(a)
    cs_b = String.graphemes(b)

    cond do
      cs_a == [] ->
        length(cs_b)

      cs_b == [] ->
        length(cs_a)

      true ->
        n = length(cs_b)
        prev = :array.from_list(Enum.to_list(0..n))

        last =
          cs_a
          |> Enum.with_index(1)
          |> Enum.reduce(prev, fn {ca, i}, prev_row ->
            row0 = :array.set(0, i, :array.new(n + 1, default: 0))

            cs_b
            |> Enum.with_index(1)
            |> Enum.reduce(row0, fn {cb, j}, row ->
              cost = if ca == cb, do: 0, else: 1

              val =
                min(
                  min(:array.get(j, prev_row) + 1, :array.get(j - 1, row) + 1),
                  :array.get(j - 1, prev_row) + cost
                )

              :array.set(j, val, row)
            end)
          end)

        :array.get(n, last)
    end
  end

  @doc "True when a name looks like it holds a secret."
  def secret_name?(name), do: Regex.match?(@secret_name, name)

  # ---------------------------------------------------------------------------
  # File discovery & parsing
  # ---------------------------------------------------------------------------

  @doc "Return `%{NAME => [{Origin, value}, ...]}` for every definition in a file."
  def parse_env_file(path) do
    path
    |> File.read!()
    |> split_lines()
    |> Enum.with_index(1)
    |> Enum.reduce(%{}, fn {raw, lineno}, acc ->
      stripped = String.trim(raw)

      if stripped == "" or String.starts_with?(stripped, "#") do
        acc
      else
        case Regex.run(@env_line, raw) do
          [_, name, rhs] ->
            entry = {%Origin{file: path, line: lineno}, parse_value(rhs)}
            Map.update(acc, name, [entry], &(&1 ++ [entry]))

          _ ->
            acc
        end
      end
    end)
  end

  @doc "Return `%{NAME => first Origin}` for env usages in a source file."
  def scan_source_file(path) do
    text = File.read!(path)

    if js_extension?(path) do
      find_refs(strip_js_noise(text), path, @js_usage_patterns)
    else
      find_refs(strip_noise(text), path, @usage_patterns)
    end
  end

  defp js_extension?(path) do
    path
    |> Path.extname()
    |> String.trim_leading(".")
    |> String.downcase()
    |> Kernel.in(["js", "jsx", "ts", "tsx", "mjs", "cjs"])
  end

  defp find_refs(text, path, patterns) do
    Enum.reduce(patterns, %{}, fn pattern, acc ->
      Regex.scan(pattern, text, return: :index, capture: :all_but_first)
      |> Enum.reduce(acc, fn [{idx, len}], inner ->
        name = binary_part(text, idx, len)

        Map.put_new(inner, name, %Origin{
          file: path,
          line: line_number_at(text, idx)
        })
      end)
    end)
  end

  defp line_number_at(text, offset) do
    text
    |> binary_part(0, offset)
    |> then(&length(:binary.matches(&1, "\n")) + 1)
  end

  defp has_workflows_segment?(path) do
    parts = Path.split(path)

    parts
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [a, b] -> a == ".github" and b == "workflows" end)
  end

  @doc """
  Return `[{path, kind}, ...]` for Compose/Actions/Kubernetes YAML files.

  `kind` is one of `"compose"`, `"actions"`, `"k8s"`. Classification is by
  filename/path/content; yamerl confirms Kubernetes manifests when the regex
  heuristic matches.
  """
  def discover_infra_files(root) do
    root
    |> walk_files(@infra_skip_dirs)
    |> Enum.reduce([], fn path, acc ->
      base = Path.basename(path)
      low = String.downcase(base)
      is_yaml = String.ends_with?(low, ".yml") or String.ends_with?(low, ".yaml")

      cond do
        Regex.match?(@compose_basename, base) -> [{path, "compose"} | acc]
        is_yaml and has_workflows_segment?(path) -> [{path, "actions"} | acc]
        is_yaml and k8s_manifest?(path) -> [{path, "k8s"} | acc]
        true -> acc
      end
    end)
    |> Enum.reverse()
  end

  defp k8s_manifest?(path) do
    case File.read(path) do
      {:ok, text} ->
        (Regex.match?(@k8s_api_version, text) and Regex.match?(@k8s_kind, text)) or
          yaml_has_k8s_keys?(text)

      _ ->
        false
    end
  end

  # Confirmation pass with yamerl: parse the document(s) and look for
  # apiVersion/kind keys at the top level of any document.
  defp yaml_has_k8s_keys?(text) do
    docs = YamlElixir.read_from_string(text)

    has_keys? = fn
      %{} = map ->
        Map.has_key?(map, "apiVersion") and Map.has_key?(map, "kind")

      _ ->
        false
    end

    case docs do
      {:ok, parsed} when is_map(parsed) -> has_keys?.(parsed)
      {:ok, parsed} when is_list(parsed) -> Enum.any?(parsed, has_keys?)
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc """
  Return `%{NAME => first Origin}` for interpolation refs in an infra file.

  Escaped `$$` is neutralized first (offset-preserving). Interpolation refs
  apply to all kinds; GitHub Actions additionally matches
  `secrets.X`/`vars.X`/`env.X` references.
  """
  def scan_infra_file(path, kind) do
    text = String.replace(File.read!(path), "$$", "  ")

    patterns =
      if kind == "actions" do
        [@interp_brace, @interp_bare, @actions_ref]
      else
        [@interp_brace, @interp_bare]
      end

    find_refs(text, path, patterns)
  end

  @doc "Dotenv files at the project root: `.env` then sorted `.env.*` (excluding `*.example`)."
  def discover_env_files(root) do
    {:ok, entries} = File.ls(root)

    base =
      if ".env" in entries and File.regular?(Path.join(root, ".env")),
        do: [Path.join(root, ".env")],
        else: []

    suffixed =
      entries
      |> Enum.filter(fn name ->
        String.starts_with?(name, ".env.") and not String.ends_with?(name, ".example") and
          File.regular?(Path.join(root, name))
      end)
      |> Enum.sort()
      |> Enum.map(&Path.join(root, &1))

    base ++ suffixed
  end

  defp walk_files(root, skip_dirs) do
    do_walk(root, skip_dirs, []) |> Enum.sort()
  end

  defp do_walk(path, skip_dirs, acc) do
    if File.dir?(path) do
      case File.ls(path) do
        {:ok, entries} ->
          entries
          |> Enum.sort()
          |> Enum.reduce(acc, fn entry, inner ->
            full = Path.join(path, entry)

            cond do
              File.dir?(full) and entry in skip_dirs -> inner
              File.dir?(full) -> do_walk(full, skip_dirs, inner)
              File.regular?(full) -> [full | inner]
              true -> inner
            end
          end)

        _ ->
          acc
      end
    else
      if File.regular?(path), do: [path | acc], else: acc
    end
  end

  @doc "Source files under `root` whose extension is in `extensions`."
  def discover_source_files(root, extensions \\ @default_extensions) do
    exts = MapSet.new(extensions, &String.trim_leading(String.downcase(&1), "."))

    root
    |> walk_files(@source_skip_dirs)
    |> Enum.filter(fn path ->
      path |> Path.extname() |> String.trim_leading(".") |> String.downcase() |> then(&(&1 in exts))
    end)
  end

  @doc "Map each environment label to the set of variable names defined in it."
  def defined_by_label(root) do
    root
    |> discover_env_files()
    |> Enum.reduce(%{}, fn env_file, acc ->
      label = env_label(Path.basename(env_file))
      names = parse_env_file(env_file) |> Map.keys() |> MapSet.new()
      Map.update(acc, label, names, &MapSet.union(&1, names))
    end)
  end

  @doc "Compare the variable names defined in two environment labels."
  def diff_labels(root, a, b) do
    labels = defined_by_label(root)
    da = Map.get(labels, a, MapSet.new())
    db = Map.get(labels, b, MapSet.new())

    %{
      "onlyInA" => da |> MapSet.difference(db) |> Enum.sort(),
      "onlyInB" => db |> MapSet.difference(da) |> Enum.sort(),
      "common" => da |> MapSet.intersection(db) |> Enum.sort()
    }
  end

  @doc """
  Append keys present in `src` but missing from `dst` to dst's file.

  Values are never copied — only `KEY=` placeholders are written.
  """
  def sync_labels(root, src, dst, dry_run \\ false) do
    labels = defined_by_label(root)

    missing =
      labels
      |> Map.get(src, MapSet.new())
      |> MapSet.difference(Map.get(labels, dst, MapSet.new()))
      |> Enum.sort()

    if missing != [] and not dry_run do
      target = Path.join(root, if(dst == "default", do: ".env", else: ".env.#{dst}"))
      existing = if File.exists?(target), do: File.read!(target), else: ""
      prefix = if existing == "" or String.ends_with?(existing, "\n"), do: "", else: "\n"
      File.write!(target, existing <> prefix <> Enum.map_join(missing, "", &"#{&1}=\n"))
    end

    missing
  end

  @doc """
  Return `{defined, used}` name sets, computed exactly as `scan/2` does.
  """
  def collect_names(root, extensions \\ @default_extensions) do
    defined =
      root
      |> discover_env_files()
      |> Enum.flat_map(fn env_file -> parse_env_file(env_file) |> Map.keys() end)
      |> MapSet.new()

    used =
      root
      |> discover_source_files(extensions)
      |> Enum.flat_map(fn src -> scan_source_file(src) |> Map.keys() end)
      |> MapSet.new()

    used =
      root
      |> discover_infra_files()
      |> Enum.reduce(used, fn {infra_path, kind}, acc ->
        infra_path |> scan_infra_file(kind) |> Map.keys() |> Enum.into(acc)
      end)

    {defined, used}
  end

  @doc "Render `.env.example` content from the union of names. Values omitted."
  def render_env_example(defined, used) do
    names = defined |> MapSet.union(used) |> Enum.sort()

    (["# Generated by envdoctor. Fill in values; do not commit secrets."] ++
       Enum.map(names, &"#{&1}="))
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  @doc "Render `ENVIRONMENT.md` content from the union of names. Values omitted."
  def render_environment_md(defined, used) do
    names = defined |> MapSet.union(used) |> Enum.sort()

    rows =
      Enum.map(names, fn name ->
        d = if name in defined, do: "yes", else: "no"
        u = if name in used, do: "yes", else: "no"
        "| #{name} | #{d} | #{u} |"
      end)

    (["# Environment variables", "", "| Variable | Defined | Used |", "| --- | --- | --- |"] ++
       rows)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  @doc "Return `%{filename => content}` for the two generated files."
  def generate_docs(root, extensions \\ @default_extensions) do
    {defined, used} = collect_names(root, extensions)

    %{
      ".env.example" => render_env_example(defined, used),
      "ENVIRONMENT.md" => render_environment_md(defined, used)
    }
  end

  # ---------------------------------------------------------------------------
  # Schema validation (envdoctor.schema.json)
  # ---------------------------------------------------------------------------

  @doc "Load `envdoctor.schema.json` from the project root, or `%{}` if absent/invalid."
  def load_schema(root) do
    path = Path.join(root, "envdoctor.schema.json")

    with {:ok, text} <- File.read(path),
         {:ok, data} <- safe_json_decode(text),
         true <- is_map(data) do
      data
    else
      _ -> %{}
    end
  end

  defp type_ok?(_value, "string"), do: true
  defp type_ok?(value, "integer"), do: Regex.match?(~r/^-?\d+$/, value)
  defp type_ok?(value, "float"), do: Regex.match?(~r/^-?\d+(\.\d+)?$/, value)
  defp type_ok?(value, "boolean"), do: String.downcase(value) in ["true", "false"]
  defp type_ok?(value, "url"), do: Regex.match?(~r/^https?:\/\//, value)

  defp type_ok?(value, "json") do
    match?({:ok, _}, safe_json_decode(value))
  end

  defp type_ok?(_value, _declared), do: true

  @doc "Return the first schema-check failure message for `value`, or nil."
  def schema_failure(rule, value) when is_map(rule) do
    declared = Map.get(rule, "type")

    cond do
      is_binary(declared) and not type_ok?(value, declared) ->
        "value does not match schema type #{declared}"

      is_list(Map.get(rule, "enum")) and value not in Map.get(rule, "enum") ->
        "value is not one of the allowed values"

      is_binary(Map.get(rule, "regex")) and
          not Regex.match?(Regex.compile!(Map.get(rule, "regex")), value) ->
        "value does not match the required pattern"

      true ->
        numeric_bounds_failure(rule, value)
    end
  end

  def schema_failure(_rule, _value), do: nil

  defp numeric_bounds_failure(rule, value) do
    if Regex.match?(@numeric, value) do
      {num, _} = Float.parse(value)
      lo = Map.get(rule, "min")
      hi = Map.get(rule, "max")

      cond do
        is_number(lo) and num < lo -> "value is below the minimum"
        is_number(hi) and num > hi -> "value exceeds the maximum"
        true -> nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # The scan itself
  # ---------------------------------------------------------------------------

  @doc "Reconcile dotenv definitions against source usage under `root`."
  def scan(root, extensions \\ @default_extensions) do
    {defined, project_labels, duplicates} = collect_definitions(root)

    used =
      root
      |> discover_source_files(extensions)
      |> Enum.reduce(%{}, fn src, acc ->
        src
        |> scan_source_file()
        |> Enum.reduce(acc, fn {name, origin}, inner -> Map.put_new(inner, name, origin) end)
      end)

    # Docker Compose / GitHub Actions / Kubernetes files also reference vars.
    used =
      root
      |> discover_infra_files()
      |> Enum.reduce(used, fn {infra_path, kind}, acc ->
        infra_path
        |> scan_infra_file(kind)
        |> Enum.reduce(acc, fn {name, origin}, inner -> Map.put_new(inner, name, origin) end)
      end)

    findings =
      []
      # --- Errors, in rule order ---
      |> Kernel.++(undefined_in_source(defined, used))
      |> Kernel.++(Enum.sort_by(duplicates, & &1.name))
      |> Kernel.++(public_prefix(defined))
      |> Kernel.++(type_mismatch(defined))
      |> Kernel.++(schema_validation(root, defined))
      # --- Warnings, in rule order ---
      |> Kernel.++(unused(defined, used))
      |> Kernel.++(environment_diff(defined, project_labels))
      |> Kernel.++(weak_secret(defined))
      |> Kernel.++(typo(defined, used))

    %ScanResult{findings: findings}
  end

  # defined: %{name => %{origin: Origin, values: %{label => value}, label_order: [label]}}
  defp collect_definitions(root) do
    Enum.reduce(discover_env_files(root), {%{}, MapSet.new(), []}, fn env_file,
                                                                       {defined, labels, dups} ->
      label = env_label(Path.basename(env_file))
      labels = MapSet.put(labels, label)

      {defined, dups} =
        env_file
        |> parse_env_file()
        |> Enum.reduce({defined, dups}, fn {name, occurrences}, {defs, dup_acc} ->
          [{first_origin, first_value} | _] = occurrences

          defs =
            Map.update(defs, name, new_def(first_origin, label, first_value), fn d ->
              # First value seen for this label wins.
              if Map.has_key?(d.values, label) do
                d
              else
                %{
                  d
                  | values: Map.put(d.values, label, first_value),
                    label_order: d.label_order ++ [label]
                }
              end
            end)

          dup_acc =
            if length(occurrences) >= 2 do
              lines = occurrences |> Enum.map(fn {o, _} -> Integer.to_string(o.line) end) |> Enum.join(", ")

              [
                %Finding{
                  rule: "duplicates",
                  severity: "error",
                  name: name,
                  message:
                    "defined #{length(occurrences)} times in the same file (lines #{lines})",
                  origin: first_origin
                }
                | dup_acc
              ]
            else
              dup_acc
            end

          {defs, dup_acc}
        end)

      {defined, labels, dups}
    end)
    |> then(fn {defined, labels, dups} -> {defined, labels, Enum.reverse(dups)} end)
  end

  defp new_def(origin, label, value) do
    %{origin: origin, values: %{label => value}, label_order: [label]}
  end

  # undefined-in-source: used but never defined.
  defp undefined_in_source(defined, used) do
    used
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reject(&Map.has_key?(defined, &1))
    |> Enum.map(fn name ->
      %Finding{
        rule: "undefined-in-source",
        severity: "error",
        name: name,
        message: "referenced but not defined in any environment file",
        origin: used[name]
      }
    end)
  end

  # public-prefix: secret-looking var exposed to client bundles.
  defp public_prefix(defined) do
    defined
    |> Map.keys()
    |> Enum.sort()
    |> Enum.filter(fn name ->
      String.starts_with?(name, @public_prefixes) and secret_name?(name)
    end)
    |> Enum.map(fn name ->
      %Finding{
        rule: "public-prefix",
        severity: "error",
        name: name,
        message: "secret-looking variable is exposed to client bundles via a public prefix",
        origin: defined[name].origin
      }
    end)
  end

  # type-mismatch: incompatible inferred types across environments.
  defp type_mismatch(defined) do
    defined
    |> Map.keys()
    |> Enum.sort()
    |> Enum.filter(fn name ->
      d = defined[name]

      map_size(d.values) >= 2 and
        d.values
        |> Map.values()
        |> Enum.map(&infer_type/1)
        |> Enum.reject(&(&1 == "empty"))
        |> Enum.map(&compat_group/1)
        |> Enum.uniq()
        |> length() >= 2
    end)
    |> Enum.map(fn name ->
      %Finding{
        rule: "type-mismatch",
        severity: "error",
        name: name,
        message: "inferred type differs across environments",
        origin: defined[name].origin
      }
    end)
  end

  # schema-validation: values must satisfy envdoctor.schema.json rules.
  defp schema_validation(root, defined) do
    schema = load_schema(root)

    schema
    |> Map.keys()
    |> Enum.sort()
    |> Enum.flat_map(fn name ->
      rule = schema[name]

      if not is_map(rule) do
        []
      else
        case Map.get(defined, name) do
          nil ->
            if Map.get(rule, "optional") do
              []
            else
              [
                %Finding{
                  rule: "schema-validation",
                  severity: "error",
                  name: name,
                  message: "required by schema but not defined",
                  origin: nil
                }
              ]
            end

          d ->
            value = first_value(d)

            case schema_failure(rule, value) do
              nil ->
                []

              msg ->
                [
                  %Finding{
                    rule: "schema-validation",
                    severity: "error",
                    name: name,
                    message: msg,
                    origin: d.origin
                  }
                ]
            end
        end
      end
    end)
  end

  defp first_value(%{values: values, label_order: [first | _]}), do: values[first]
  defp first_value(%{values: values}), do: values |> Map.values() |> List.first() |> Kernel.||("")

  # unused: defined but never referenced.
  defp unused(defined, used) do
    defined
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reject(&Map.has_key?(used, &1))
    |> Enum.map(fn name ->
      %Finding{
        rule: "unused",
        severity: "warning",
        name: name,
        message: "defined but never referenced in source",
        origin: defined[name].origin
      }
    end)
  end

  # environment-diff: defined in some but not all project env labels.
  defp environment_diff(defined, project_labels) do
    if MapSet.size(project_labels) >= 2 do
      defined
      |> Map.keys()
      |> Enum.sort()
      |> Enum.flat_map(fn name ->
        present = defined[name].values |> Map.keys() |> Enum.sort()
        absent = project_labels |> MapSet.difference(MapSet.new(present)) |> Enum.sort()

        if present != [] and absent != [] do
          [
            %Finding{
              rule: "environment-diff",
              severity: "warning",
              name: name,
              message:
                "defined in #{Enum.join(present, ", ")} but missing in #{Enum.join(absent, ", ")}",
              origin: defined[name].origin
            }
          ]
        else
          []
        end
      end)
    else
      []
    end
  end

  # weak-secret: secret-looking name with a weak or placeholder value.
  defp weak_secret(defined) do
    defined
    |> Map.keys()
    |> Enum.sort()
    |> Enum.filter(&secret_name?/1)
    |> Enum.filter(fn name ->
      d = defined[name]
      origin_label = env_label(Path.basename(d.origin.file))
      value = Map.get(d.values, origin_label) || first_value(d) || ""

      value == "" or String.length(value) < 8 or Regex.match?(@weak_secret_value, value)
    end)
    |> Enum.map(fn name ->
      %Finding{
        rule: "weak-secret",
        severity: "warning",
        name: name,
        message: "secret-looking variable has a weak or placeholder value",
        origin: defined[name].origin
      }
    end)
  end

  # typo: used-but-undefined name close to a defined name.
  defp typo(defined, used) do
    defined_names = defined |> Map.keys() |> Enum.sort()

    used
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reject(&Map.has_key?(defined, &1))
    |> Enum.flat_map(fn u ->
      best =
        Enum.reduce(defined_names, nil, fn d, best ->
          if d == u do
            best
          else
            threshold = if min(String.length(u), String.length(d)) <= 4, do: 1, else: 2
            dist = levenshtein(u, d)

            if dist <= threshold and (is_nil(best) or dist < elem(best, 1)) do
              {d, dist}
            else
              best
            end
          end
        end)

      case best do
        nil ->
          []

        {best_d, _} ->
          [
            %Finding{
              rule: "typo",
              severity: "warning",
              name: u,
              message: "\"#{u}\" is not defined; did you mean \"#{best_d}\"?",
              origin: used[u]
            }
          ]
      end
    end)
  end

  @doc "Serialize a finding for JSON output. Values are never included."
  def finding_to_map(%Finding{} = finding, root) do
    {file, line} =
      case finding.origin do
        nil -> {nil, nil}
        %Origin{file: f, line: l} -> {relative(f, root), l}
      end

    %{
      "rule" => finding.rule,
      "severity" => finding.severity,
      "name" => finding.name,
      "message" => finding.message,
      "file" => file,
      "line" => line
    }
  end

  defp relative(file, root) do
    case Path.relative_to(file, root) do
      ^file -> file
      rel -> rel
    end
  end
end
