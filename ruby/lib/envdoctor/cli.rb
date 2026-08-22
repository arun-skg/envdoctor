# frozen_string_literal: true

require "optparse"
require_relative "scanner"

module Envdoctor
  # Command-line entry point.
  module CLI
    module_function

    def run(argv)
      dir = "."
      strict = false
      parser = OptionParser.new do |o|
        o.banner = "Usage: envdoctor scan [options]"
        o.on("-d", "--dir DIR", "Project root (default: cwd)") { |v| dir = v }
        o.on("--strict", "Treat warnings as errors") { strict = true }
      end
      args = argv.dup
      args.shift if args.first == "scan"
      parser.parse!(args)

      root = File.expand_path(dir)
      findings = Scanner.scan(root)
      errors = findings.select { |f| f.severity == "error" }
      warnings = findings.select { |f| f.severity == "warning" }

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
  end
end
