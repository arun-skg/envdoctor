defmodule EnvdoctorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Envdoctor.{CLI, Scanner}
  alias Envdoctor.Runtime.{Compare, Token}
  alias Envdoctor.Scanner.ScanResult

  setup do
    dir = Path.join(System.tmp_dir!(), "envdoctor_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp write(dir, name, content) do
    path = Path.join(dir, name)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    path
  end

  defp errors(%ScanResult{} = r), do: ScanResult.errors(r)
  defp warnings(%ScanResult{} = r), do: ScanResult.warnings(r)

  test "version matches the reference" do
    assert Envdoctor.version() == "0.1.2"
  end

  test "detects all usage forms and ignores comments/heredocs", %{dir: dir} do
    src =
      write(dir, "app.ex", """
      defmodule App do
        # System.get_env("COMMENTED")
        @moduledoc \"\"\"
        Example: System.get_env("DOC_IGNORED")
        \"\"\"
        def a, do: System.get_env("DB_URL")
        def b, do: System.get_env("PORT", "3000")
        def c, do: System.fetch_env("API_KEY")
        def d, do: System.fetch_env!("HOST")
      end
      """)

    used = Scanner.scan_source_file(src)
    assert Map.keys(used) |> Enum.sort() == ["API_KEY", "DB_URL", "HOST", "PORT"]
    refute Map.has_key?(used, "COMMENTED")
    refute Map.has_key?(used, "DOC_IGNORED")
  end

  test "detects JS usage forms when js extensions are scanned", %{dir: dir} do
    src =
      write(dir, "app.js", """
      // process.env.COMMENTED
      /* process.env.BLOCKED */
      const a = process.env.DATABASE_URL;
      const b = process.env["API_KEY"];
      const c = import.meta.env.VITE_FLAG;
      """)

    used = Scanner.scan_source_file(src)
    assert Map.keys(used) |> Enum.sort() == ["API_KEY", "DATABASE_URL", "VITE_FLAG"]
    refute Map.has_key?(used, "COMMENTED")
    refute Map.has_key?(used, "BLOCKED")
  end

  test "missing and unused", %{dir: dir} do
    write(dir, ".env", "DB_URL=postgres://x\nUNUSED_KEY=1\n")
    write(dir, "app.ex", "System.get_env(\"DB_URL\")\nSystem.get_env(\"NEW_FLAG\")\n")

    result = Scanner.scan(dir)
    err_names = result |> errors() |> Enum.map(& &1.name)
    warn_names = result |> warnings() |> Enum.map(& &1.name)

    assert "NEW_FLAG" in err_names
    assert "UNUSED_KEY" in warn_names
    refute "DB_URL" in err_names
    refute "DB_URL" in warn_names
  end

  test "duplicates", %{dir: dir} do
    write(dir, ".env", "DB_URL=a\nDB_URL=b\nSOLO=1\n")
    write(dir, "app.ex", "System.get_env(\"DB_URL\")\nSystem.get_env(\"SOLO\")\n")

    result = Scanner.scan(dir)
    dups = Enum.filter(result.findings, &(&1.rule == "duplicates"))
    assert length(dups) == 1
    assert hd(dups).name == "DB_URL"
    assert hd(dups).severity == "error"
    assert hd(dups).message =~ "lines 1, 2"
    refute Enum.any?(result.findings, &(&1.rule == "unused" and &1.name == "DB_URL"))
  end

  test "public-prefix", %{dir: dir} do
    write(dir, ".env", "NEXT_PUBLIC_API_KEY=x\nPUBLIC_URL=x\nAPI_KEY=x\n")
    result = Scanner.scan(dir)
    pp = Enum.filter(result.findings, &(&1.rule == "public-prefix"))
    assert Enum.map(pp, & &1.name) == ["NEXT_PUBLIC_API_KEY"]
    assert hd(pp).severity == "error"
  end

  test "clean project has no findings", %{dir: dir} do
    write(dir, ".env", "DB_URL=x\n")
    write(dir, "app.ex", "System.get_env(\"DB_URL\")\n")
    assert Scanner.scan(dir).findings == []
  end

  test "infer_type" do
    assert Scanner.infer_type("") == "empty"
    assert Scanner.infer_type("3000") == "integer"
    assert Scanner.infer_type("-7") == "integer"
    assert Scanner.infer_type("1.5") == "float"
    assert Scanner.infer_type("TRUE") == "boolean"
    assert Scanner.infer_type("https://x.io") == "url"
    assert Scanner.infer_type(~s({"a":1})) == "json"
    assert Scanner.infer_type("hello") == "string"
  end

  test "levenshtein" do
    assert Scanner.levenshtein("abc", "abc") == 0
    assert Scanner.levenshtein("DATBASE_URL", "DATABASE_URL") == 1
    assert Scanner.levenshtein("", "abc") == 3
  end

  test "weak-secret never leaks values", %{dir: dir} do
    write(dir, ".env", "API_KEY=changeme\nSTRONG_TOKEN=s0m3-l0ng-r4nd0m-value\nSHORT_SECRET=abc\n")
    write(dir, "app.ex", "# nothing used\n")

    result = Scanner.scan(dir)
    weak = result.findings |> Enum.filter(&(&1.rule == "weak-secret")) |> Enum.map(& &1.name)
    assert "API_KEY" in weak
    assert "SHORT_SECRET" in weak
    refute "STRONG_TOKEN" in weak

    for f <- result.findings do
      assert f.severity in ["error", "warning"]
      refute f.message =~ "changeme"
      refute f.message =~ "s0m3"
    end
  end

  test "typo suggestion", %{dir: dir} do
    write(dir, ".env", "DATABASE_URL=postgres://x\n")
    write(dir, "app.ex", "System.get_env(\"DATBASE_URL\")\n")

    result = Scanner.scan(dir)
    typos = Enum.filter(result.findings, &(&1.rule == "typo"))
    assert length(typos) == 1
    assert hd(typos).name == "DATBASE_URL"
    assert hd(typos).severity == "warning"
    assert hd(typos).message =~ ~s(did you mean "DATABASE_URL")
    assert "DATBASE_URL" in Enum.map(errors(result), & &1.name)
  end

  test "environment-diff", %{dir: dir} do
    write(dir, ".env", "SHARED=1\n")
    write(dir, ".env.production", "SHARED=1\nONLY_PROD=1\n")
    write(dir, "app.ex", "# none\n")

    result = Scanner.scan(dir)
    diffs = Map.new(Enum.filter(result.findings, &(&1.rule == "environment-diff")), &{&1.name, &1})
    assert Map.has_key?(diffs, "ONLY_PROD")
    assert diffs["ONLY_PROD"].severity == "warning"
    assert diffs["ONLY_PROD"].message =~ "default"
    assert diffs["ONLY_PROD"].message =~ "production"
    refute Map.has_key?(diffs, "SHARED")
  end

  test "type-mismatch", %{dir: dir} do
    write(dir, ".env", "PORT=3000\nHOST=8080\n")
    write(dir, ".env.production", "PORT=abc\nHOST=9090\n")
    write(dir, "app.ex", "# none\n")

    result = Scanner.scan(dir)
    mismatches = result.findings |> Enum.filter(&(&1.rule == "type-mismatch")) |> Enum.map(& &1.name)
    assert "PORT" in mismatches
    refute "HOST" in mismatches

    tm = Enum.find(result.findings, &(&1.rule == "type-mismatch"))
    assert tm.severity == "error"
    refute tm.message =~ "3000"
    refute tm.message =~ "abc"
  end

  test "scan --json output shape and no value leak", %{dir: dir} do
    write(dir, ".env", "API_KEY=changeme\n")
    write(dir, "app.ex", "System.get_env(\"DATBASE_URL\")\n")
    write(dir, ".env.production", "API_KEY=changeme\nDATABASE_URL=x\n")

    out = capture_io(fn -> assert CLI.run(["scan", "--dir", dir, "--json"]) == 1 end)
    {:ok, data} = Envdoctor.Json.decode(out)
    assert is_list(data)

    for obj <- data do
      assert obj |> Map.keys() |> Enum.sort() == ["file", "line", "message", "name", "rule", "severity"]
    end

    refute out =~ "changeme"
  end

  test "finding_to_map shape", %{dir: dir} do
    write(dir, ".env", "UNUSED=1\n")
    write(dir, "app.ex", "# none\n")
    [finding | _] = Scanner.scan(dir).findings
    d = Scanner.finding_to_map(finding, dir)
    assert d["file"] == ".env"
    assert is_integer(d["line"])
  end

  test "infra sources scanned (compose/actions/k8s)", %{dir: dir} do
    write(dir, ".env", "DB_URL=postgres://x\n")

    write(dir, "docker-compose.yml", """
    services:
      web:
        image: x
        environment:
          - TOKEN=${COMPOSE_SECRET}
          - DB=${DB_URL}
    """)

    write(dir, ".github/workflows/ci.yml", """
    jobs:
      build:
        steps:
          - run: deploy
            env:
              KEY: ${{ secrets.DEPLOY_KEY }}
              REGION: ${{ vars.REGION }}
    """)

    write(dir, "k8s/deploy.yaml", """
    apiVersion: apps/v1
    kind: Deployment
    spec:
      value: ${K8S_VAR}
    """)

    result = Scanner.scan(dir)

    undefined =
      result |> errors() |> Enum.filter(&(&1.rule == "undefined-in-source")) |> Enum.map(& &1.name)

    for name <- ["COMPOSE_SECRET", "DEPLOY_KEY", "REGION", "K8S_VAR"] do
      assert name in undefined
    end

    for f <- result.findings, f.rule == "undefined-in-source" do
      assert f.message == "referenced but not defined in any environment file"
    end

    unused = result |> warnings() |> Enum.filter(&(&1.rule == "unused")) |> Enum.map(& &1.name)
    refute "DB_URL" in unused

    for f <- result.findings do
      refute f.message =~ "postgres"
    end
  end

  test "generate_docs exact content", %{dir: dir} do
    write(dir, ".env", "DB_URL=postgres://x\n")
    write(dir, "app.ex", "System.get_env(\"PORT\")\n")

    docs = Scanner.generate_docs(dir)

    assert docs[".env.example"] ==
             "# Generated by envdoctor. Fill in values; do not commit secrets.\nDB_URL=\nPORT=\n"

    md = docs["ENVIRONMENT.md"]
    assert String.starts_with?(md, "# Environment variables\n\n| Variable | Defined | Used |\n")
    assert md =~ "| DB_URL | yes | no |"
    assert md =~ "| PORT | no | yes |"
    assert String.ends_with?(md, "\n")
    refute docs[".env.example"] =~ "postgres"
    refute md =~ "postgres"
  end

  test "init creates, skips, and forces", %{dir: dir} do
    write(dir, ".env", "DB_URL=postgres://x\n")
    write(dir, "app.ex", "System.get_env(\"PORT\")\n")

    example = Path.join(dir, ".env.example")
    envdoc = Path.join(dir, "ENVIRONMENT.md")

    out = capture_io(fn -> assert CLI.run(["init", "--dir", dir]) == 0 end)
    assert out =~ "created .env.example"
    assert out =~ "created ENVIRONMENT.md"

    first_example = File.read!(example)
    first_md = File.read!(envdoc)

    assert first_example ==
             "# Generated by envdoctor. Fill in values; do not commit secrets.\nDB_URL=\nPORT=\n"

    refute first_example =~ "postgres"
    refute first_md =~ "postgres"

    File.write!(example, "SENTINEL")
    out = capture_io(fn -> assert CLI.run(["init", "--dir", dir]) == 0 end)
    assert out =~ "skipped .env.example (exists)"
    assert out =~ "skipped ENVIRONMENT.md (exists)"
    assert File.read!(example) == "SENTINEL"

    out = capture_io(fn -> assert CLI.run(["init", "--dir", dir, "--force"]) == 0 end)
    assert out =~ "wrote .env.example"
    assert out =~ "wrote ENVIRONMENT.md"
    assert File.read!(example) == first_example
  end

  test "fix always rewrites", %{dir: dir} do
    write(dir, ".env", "DB_URL=postgres://x\n")
    write(dir, "app.ex", "System.get_env(\"PORT\")\n")
    write(dir, ".env.example", "STALE")

    out = capture_io(fn -> assert CLI.run(["fix", "--dir", dir]) == 0 end)
    assert out =~ "wrote .env.example"
    assert out =~ "wrote ENVIRONMENT.md"

    assert File.read!(Path.join(dir, ".env.example")) ==
             "# Generated by envdoctor. Fill in values; do not commit secrets.\nDB_URL=\nPORT=\n"

    md = File.read!(Path.join(dir, "ENVIRONMENT.md"))
    assert md =~ "| DB_URL | yes | no |"
    assert md =~ "| PORT | no | yes |"
    refute md =~ "postgres"
  end

  test "diff and sync", %{dir: dir} do
    write(dir, ".env", "A=1\nB=2\n")
    write(dir, ".env.production", "A=9\n")

    assert Scanner.diff_labels(dir, "default", "production") ==
             %{"onlyInA" => ["B"], "onlyInB" => [], "common" => ["A"]}

    # dry-run does not write
    assert Scanner.sync_labels(dir, "default", "production", true) == ["B"]
    refute File.read!(Path.join(dir, ".env.production")) =~ "B="

    # real sync appends B= (no value copied) and leaves A's value intact
    assert Scanner.sync_labels(dir, "default", "production") == ["B"]
    prod = File.read!(Path.join(dir, ".env.production"))
    assert prod =~ "B=\n"
    assert prod =~ "A=9"
    refute prod =~ "B=2"
    assert Scanner.diff_labels(dir, "default", "production")["common"] == ["A", "B"]
  end

  test "schema validation", %{dir: dir} do
    write(dir, ".env", "PORT=99999\nLEVEL=verbose\nAPI=ftp://x\nGOOD=info\n")

    write(dir, "envdoctor.schema.json", ~s|{"PORT":{"type":"integer","max":65535},"LEVEL":{"enum":["debug","info"]},"API":{"type":"url"},"MISSING":{"type":"string"},"GOOD":{"enum":["info","warn"]}}|)

    result = Scanner.scan(dir)

    schema =
      Map.new(
        Enum.filter(result.findings, &(&1.rule == "schema-validation")),
        &{&1.name, &1.message}
      )

    assert schema == %{
             "PORT" => "value exceeds the maximum",
             "LEVEL" => "value is not one of the allowed values",
             "API" => "value does not match schema type url",
             "MISSING" => "required by schema but not defined"
           }

    for f <- result.findings do
      refute f.message =~ "99999"
      refute f.message =~ "verbose"
    end
  end

  test "schema optional and absent", %{dir: dir} do
    write(dir, ".env", "A=1\n")
    assert Scanner.load_schema(dir) == %{}
    refute Enum.any?(Scanner.scan(dir).findings, &(&1.rule == "schema-validation"))

    write(dir, "envdoctor.schema.json", ~s|{"MAYBE":{"type":"string","optional":true}}|)
    refute Enum.any?(Scanner.scan(dir).findings, &(&1.rule == "schema-validation"))
  end

  test "scan exits 1 on errors, 0 when clean, 1 with --strict warnings", %{dir: dir} do
    write(dir, ".env", "UNUSED=1\n")
    write(dir, "app.ex", "# none\n")
    capture_io(fn -> assert CLI.run(["scan", "--dir", dir]) == 0 end)
    capture_io(fn -> assert CLI.run(["scan", "--dir", dir, "--strict"]) == 1 end)

    write(dir, "app.ex", "System.get_env(\"MISSING_VAR\")\n")
    capture_io(fn -> assert CLI.run(["scan", "--dir", dir]) == 1 end)
  end

  test "token round-trip and snapshot-diff equivalence" do
    snapshot = %{
      schema: 1,
      capturedAt: "2025-01-01T00:00:00Z",
      os: %{platform: "darwin", arch: "arm64", release: "24.0.0"},
      tools: [%{tool: "node", version: "20.11.1", resolvedFrom: "/usr/local/bin"}],
      path: ["/usr/local/bin", "/usr/bin"],
      globals: %{},
      envFlagNames: ["HOME", "PATH"]
    }

    token = Token.encode(snapshot)
    assert String.starts_with?(token, "envd1:")
    assert {:ok, decoded} = Token.decode(token)
    assert decoded.tools == [%{tool: "node", version: "20.11.1", resolvedFrom: "/usr/local/bin"}]

    diff = Compare.compare(decoded, decoded)
    assert diff.equivalent

    other = put_in(decoded.tools, [%{tool: "node", version: "22.0.0", resolvedFrom: "/opt/bin"}])
    diff = Compare.compare(decoded, other)
    refute diff.equivalent
    assert Enum.any?(diff.tools, &(&1.name == "node" and &1.status == "different"))

    assert {:error, _} = Token.decode("not-a-token")
    assert {:error, _} = Token.decode("envd1:!!!garbage!!!")
  end

  test "snapshot capture records names only, never secret names" do
    snapshot = Envdoctor.capture_snapshot()
    assert snapshot.schema == 1
    assert is_binary(snapshot.capturedAt)
    assert is_binary(snapshot.os.platform)
    assert is_list(snapshot.path)
    assert is_list(snapshot.envFlagNames)
    # PATH itself is an env name; values never appear in the snapshot.
    refute Map.has_key?(snapshot, :env)
  end
end
