# frozen_string_literal: true

require "optparse"
require_relative "scanner"

module Envdoctor
  # Command-line entry point.
  module CLI
    module_function

    def run(argv)
      return run_diff(argv[1..]) if argv.first == "diff"
      return run_sync(argv[1..]) if argv.first == "sync"

      dir = "."
      strict = false
      json = false
      parser = OptionParser.new do |o|
        o.banner = "Usage: envdoctor scan [options]"
        o.on("-d", "--dir DIR", "Project root (default: cwd)") { |v| dir = v }
        o.on("--strict", "Treat warnings as errors") { strict = true }
        o.on("--json", "Emit findings as a JSON array") { json = true }
      end
      args = argv.dup
      args.shift if args.first == "scan"
      parser.parse!(args)

      root = File.expand_path(dir)
      findings = Scanner.scan(root)
      errors = findings.select { |f| f.severity == "error" }
      warnings = findings.select { |f| f.severity == "warning" }

      if json
        puts Scanner.to_json_array(findings)
        return (!errors.empty? || (strict && !warnings.empty?)) ? 1 : 0
      end

      puts "ENVIRONMENT AUDIT"
      puts "=" * 40
      if findings.empty?
        puts "\nNo issues found."
        return 0
      end

      unless errors.empty?
        puts "\nErrors"
        errors.each { |f| puts "  x #{f.name} #{f.origin.file}:#{f.origin.line}  #{f.message}" }
      end
      unless warnings.empty?
        puts "\nWarnings"
        warnings.each { |f| puts "  ! #{f.name} #{f.origin.file}:#{f.origin.line}  #{f.message}" }
      end
      puts "\nSummary: #{errors.length} error(s), #{warnings.length} warning(s)"

      (!errors.empty? || (strict && !warnings.empty?)) ? 1 : 0
    end

    def run_diff(argv)
      dir = "."
      json = false
      pos = []
      OptionParser.new do |o|
        o.on("-d", "--dir DIR") { |v| dir = v }
        o.on("--json") { json = true }
      end.order!(argv.dup) { |a| pos << a }
      a, b = pos[0], pos[1]
      d = Scanner.diff_labels(File.expand_path(dir), a, b)
      if json
        require "json"
        puts JSON.generate({ "a" => a, "b" => b }.merge(d))
        return 0
      end
      puts "ENVIRONMENT DIFF: #{a} vs #{b}"
      puts "=" * 40
      unless d["onlyInA"].empty?
        puts "Only in #{a}:"
        d["onlyInA"].each { |k| puts "  + #{k}" }
      end
      unless d["onlyInB"].empty?
        puts "Only in #{b}:"
        d["onlyInB"].each { |k| puts "  + #{k}" }
      end
      puts "Common: #{d['common'].length} variable(s)"
      0
    end

    def run_sync(argv)
      dir = "."
      json = false
      dry = false
      pos = []
      OptionParser.new do |o|
        o.on("-d", "--dir DIR") { |v| dir = v }
        o.on("--dry-run") { dry = true }
        o.on("--json") { json = true }
      end.order!(argv.dup) { |a| pos << a }
      from, to = pos[0], pos[1]
      added = Scanner.sync_labels(File.expand_path(dir), from, to, dry_run: dry)
      if json
        require "json"
        puts JSON.generate({ "from" => from, "to" => to, "added" => added, "dryRun" => dry })
        return 0
      end
      if added.empty?
        puts "Already in sync."
        return 0
      end
      verb = dry ? "Would sync" : "Synced"
      puts "#{verb} #{added.length} variable(s) from #{from} to #{to}:"
      added.each { |k| puts "  + #{k}" }
      0
    end
  end
end
