# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/envdoctor/scanner"
require_relative "../lib/envdoctor/cli"

class ScannerTest < Minitest::Test
  def test_detects_usage_and_ignores_comments
    src = <<~RUBY
      # ENV["COMMENTED"]
      db = ENV["DB_URL"]
      port = ENV.fetch("PORT")
      =begin
      ENV["BLOCK_IGNORED"]
      =end
      user = ENV['DB_USER']
    RUBY
    used = Envdoctor::Scanner.scan_source("app.rb", src)
    assert_equal %w[DB_URL DB_USER PORT], used.keys.sort
    refute used.key?("COMMENTED")
    refute used.key?("BLOCK_IGNORED")
  end

  def test_reconciles_missing_and_unused
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".env"), "DB_URL=x\nUNUSED_KEY=1\n")
      File.write(File.join(dir, "app.rb"), "ENV[\"DB_URL\"]\nENV[\"NEW_FLAG\"]\n")
      findings = Envdoctor::Scanner.scan(dir)
      errors = findings.select { |f| f.severity == "error" }.map(&:name)
      warnings = findings.select { |f| f.severity == "warning" }.map(&:name)
      assert_includes errors, "NEW_FLAG"
      assert_includes warnings, "UNUSED_KEY"
      refute_includes errors, "DB_URL"
      refute_includes warnings, "DB_URL"
    end
  end

  def test_detects_duplicate_keys
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".env"), "DUP=a\nSOLO=1\nDUP=b\n")
      File.write(File.join(dir, "app.rb"), "ENV[\"DUP\"]\nENV[\"SOLO\"]\n")
      findings = Envdoctor::Scanner.scan(dir)
      dup = findings.find { |f| f.rule == "duplicates" }
      refute_nil dup
      assert_equal "DUP", dup.name
      assert_equal "error", dup.severity
      assert_equal "defined 2 times in the same file (lines 1, 3)", dup.message
      # single-definition key not reported as duplicate
      refute(findings.any? { |f| f.rule == "duplicates" && f.name == "SOLO" })
      # duplicated-but-used var must NOT also be flagged unused/undefined
      refute(findings.any? { |f| f.name == "DUP" && %w[unused undefined-in-source].include?(f.rule) })
    end
  end

  def test_detects_public_prefix_secrets
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".env"),
                 "NEXT_PUBLIC_API_KEY=x\nVITE_SECRET=y\nPUBLIC_URL=z\nAPI_KEY=w\nPUBLIC_KEY=k\n")
      findings = Envdoctor::Scanner.scan(dir)
      flagged = findings.select { |f| f.rule == "public-prefix" }.map(&:name)
      assert_includes flagged, "NEXT_PUBLIC_API_KEY"
      assert_includes flagged, "VITE_SECRET"
      refute_includes flagged, "PUBLIC_URL"
      refute_includes flagged, "API_KEY"
      refute_includes flagged, "PUBLIC_KEY"
      flagged.each do |name|
        f = findings.find { |x| x.rule == "public-prefix" && x.name == name }
        assert_equal "error", f.severity
      end
    end
  end

  def test_detects_weak_secret
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".env"),
                 "API_KEY=changeme\nDB_PASSWORD=s3cureLongValue!\nAUTH_TOKEN=\nSECRET_KEY=xxxxxx\nDATABASE_URL=postgres://localhost/db\n")
      File.write(File.join(dir, "app.rb"),
                 "ENV[\"API_KEY\"]\nENV[\"DB_PASSWORD\"]\nENV[\"AUTH_TOKEN\"]\nENV[\"SECRET_KEY\"]\nENV[\"DATABASE_URL\"]\n")
      findings = Envdoctor::Scanner.scan(dir)
      weak = findings.select { |f| f.rule == "weak-secret" }
      names = weak.map(&:name)
      assert_includes names, "API_KEY"      # placeholder value
      assert_includes names, "AUTH_TOKEN"   # empty value
      assert_includes names, "SECRET_KEY"   # xxxxxx placeholder
      refute_includes names, "DB_PASSWORD"  # strong value
      refute_includes names, "DATABASE_URL" # not a secret-looking name
      weak.each do |f|
        assert_equal "warning", f.severity
        assert_equal "secret-looking variable has a weak or placeholder value", f.message
      end
    end
  end

  def test_detects_typo
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".env"), "DATABASE_URL=x\n")
      File.write(File.join(dir, "app.rb"), "ENV[\"DATBASE_URL\"]\n")
      findings = Envdoctor::Scanner.scan(dir)
      typo = findings.find { |f| f.rule == "typo" }
      refute_nil typo
      assert_equal "DATBASE_URL", typo.name
      assert_equal "warning", typo.severity
      assert_equal "\"DATBASE_URL\" is not defined; did you mean \"DATABASE_URL\"?", typo.message
      # undefined-in-source still also fires for the same name.
      assert(findings.any? { |f| f.rule == "undefined-in-source" && f.name == "DATBASE_URL" })
    end
  end

  def test_detects_environment_diff
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".env"), "SHARED=1\nONLY_DEFAULT=1\n")
      File.write(File.join(dir, ".env.production"), "SHARED=1\nONLY_PROD=1\n")
      findings = Envdoctor::Scanner.scan(dir)
      diffs = findings.select { |f| f.rule == "environment-diff" }
      od = diffs.find { |f| f.name == "ONLY_DEFAULT" }
      refute_nil od
      assert_equal "warning", od.severity
      assert_equal "defined in default but missing in production", od.message
      assert(diffs.any? { |f| f.name == "ONLY_PROD" && f.message == "defined in production but missing in default" })
      # present in both → no diff.
      refute(diffs.any? { |f| f.name == "SHARED" })
    end
  end

  def test_detects_type_mismatch
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".env"), "PORT=8080\nWORKERS=4\n")
      File.write(File.join(dir, ".env.production"), "PORT=production\nWORKERS=8\n")
      findings = Envdoctor::Scanner.scan(dir)
      tm = findings.select { |f| f.rule == "type-mismatch" }
      names = tm.map(&:name)
      assert_includes names, "PORT" # integer vs string → error
      refute_includes names, "WORKERS" # two integers → no error
      port = tm.find { |f| f.name == "PORT" }
      assert_equal "error", port.severity
      assert_equal "inferred type differs across environments", port.message
    end
  end

  def test_json_shape_and_no_value_leak
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".env"), "API_KEY=changeme\nUNUSED_KEY=supersecretvalue\n")
      File.write(File.join(dir, "app.rb"), "ENV[\"API_KEY\"]\n")
      findings = Envdoctor::Scanner.scan(dir)
      json = Envdoctor::Scanner.to_json_array(findings)
      arr = JSON.parse(json)
      assert_kind_of Array, arr
      arr.each do |obj|
        assert_equal %w[file line message name rule severity], obj.keys.sort
      end
      # values must never leak into JSON output
      refute_includes json, "supersecretvalue"
      refute_includes json, "changeme"
    end
  end
  def test_scans_compose_actions_and_kubernetes
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".env"), "DB_URL=postgres://localhost/db\n")
      File.write(File.join(dir, "docker-compose.yml"), <<~YAML)
        services:
          web:
            environment:
              SECRET: ${COMPOSE_SECRET}
              DATABASE: ${DB_URL}
      YAML
      wf = File.join(dir, ".github", "workflows")
      FileUtils.mkdir_p(wf)
      File.write(File.join(wf, "ci.yml"), <<~YAML)
        jobs:
          deploy:
            steps:
              - run: deploy
                env:
                  KEY: ${{ secrets.DEPLOY_KEY }}
                  REGION: ${{ vars.REGION }}
      YAML
      File.write(File.join(dir, "deployment.yaml"), <<~YAML)
        apiVersion: apps/v1
        kind: Deployment
        spec:
          value: ${K8S_VAR}
      YAML

      findings = Envdoctor::Scanner.scan(dir)
      undef_found = findings.select { |f| f.rule == "undefined-in-source" }
      undef_names = undef_found.map(&:name)
      assert_includes undef_names, "COMPOSE_SECRET"
      assert_includes undef_names, "DEPLOY_KEY"
      assert_includes undef_names, "REGION"
      assert_includes undef_names, "K8S_VAR"
      undef_found.each do |f|
        assert_equal "referenced but not defined in any environment file", f.message
      end
      # DB_URL referenced by compose interpolation → not unused.
      refute(findings.any? { |f| f.rule == "unused" && f.name == "DB_URL" })
      # values never leak.
      json = Envdoctor::Scanner.to_json_array(findings)
      refute_includes json, "postgres://localhost/db"
    end
  end

  EXAMPLE = "# Generated by envdoctor. Fill in values; do not commit secrets.\nDB_URL=\nPORT=\n"

  def with_generate_project
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".env"), "DB_URL=secretvalue\n")
      File.write(File.join(dir, "app.rb"), "ENV[\"PORT\"]\n")
      yield dir
    end
  end

  def test_env_example_content_exact_and_no_values
    with_generate_project do |dir|
      content = Envdoctor::Scanner.env_example_content(dir)
      assert_equal EXAMPLE, content
      refute_includes content, "secretvalue"
    end
  end

  def test_environment_doc_content
    with_generate_project do |dir|
      content = Envdoctor::Scanner.environment_doc_content(dir)
      assert_includes content, "| DB_URL | yes | no |"
      assert_includes content, "| PORT | no | yes |"
      assert content.end_with?("\n")
      refute_includes content, "secretvalue"
    end
  end

  def test_init_creates_then_skips_then_force
    with_generate_project do |dir|
      out, = capture_io { Envdoctor::CLI.run(["init", "-d", dir]) }
      assert_includes out, "created .env.example"
      assert_includes out, "created ENVIRONMENT.md"
      assert_equal EXAMPLE, File.read(File.join(dir, ".env.example"))

      # second run without --force skips
      File.write(File.join(dir, ".env.example"), "TOUCHED\n")
      out2, = capture_io { Envdoctor::CLI.run(["init", "-d", dir]) }
      assert_includes out2, "skipped .env.example (exists)"
      assert_equal "TOUCHED\n", File.read(File.join(dir, ".env.example"))

      # --force rewrites
      out3, = capture_io { Envdoctor::CLI.run(["init", "-d", dir, "--force"]) }
      assert_includes out3, "wrote .env.example"
      assert_equal EXAMPLE, File.read(File.join(dir, ".env.example"))
    end
  end

  def test_fix_always_rewrites
    with_generate_project do |dir|
      File.write(File.join(dir, ".env.example"), "STALE\n")
      out, = capture_io { Envdoctor::CLI.run(["fix", "-d", dir]) }
      assert_includes out, "wrote .env.example"
      assert_includes out, "wrote ENVIRONMENT.md"
      assert_equal EXAMPLE, File.read(File.join(dir, ".env.example"))
      doc = File.read(File.join(dir, "ENVIRONMENT.md"))
      assert_includes doc, "| DB_URL | yes | no |"
      assert_includes doc, "| PORT | no | yes |"
    end
  end

  def test_diff_and_sync
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".env"), "A=1\nB=2\n")
      File.write(File.join(dir, ".env.production"), "A=9\n")
      d = Envdoctor::Scanner.diff_labels(dir, "default", "production")
      assert_equal({ "onlyInA" => ["B"], "onlyInB" => [], "common" => ["A"] }, d)
      assert_equal ["B"], Envdoctor::Scanner.sync_labels(dir, "default", "production", dry_run: true)
      refute_includes File.read(File.join(dir, ".env.production")), "B="
      assert_equal ["B"], Envdoctor::Scanner.sync_labels(dir, "default", "production")
      prod = File.read(File.join(dir, ".env.production"))
      assert_includes prod, "B=\n"
      assert_includes prod, "A=9"
      refute_includes prod, "B=2"
    end
  end

  def test_schema_validation
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".env"), "PORT=99999\nLEVEL=verbose\nAPI=ftp://x\nGOOD=info\n")
      File.write(File.join(dir, "envdoctor.schema.json"),
                 %q({"PORT":{"type":"integer","max":65535},"LEVEL":{"enum":["debug","info"]},"API":{"type":"url"},"MISSING":{"type":"string"},"GOOD":{"enum":["info","warn"]}}))
      findings = Envdoctor::Scanner.scan(dir)
      schema = findings.select { |f| f.rule == "schema-validation" }.map { |f| [f.name, f.message] }.to_h
      assert_equal({ "PORT" => "value exceeds the maximum",
                     "LEVEL" => "value is not one of the allowed values",
                     "API" => "value does not match schema type url",
                     "MISSING" => "required by schema but not defined" }, schema)
      refute schema.key?("GOOD")
    end
  end

end
