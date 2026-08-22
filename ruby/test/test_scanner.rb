# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/envdoctor/scanner"

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
end
