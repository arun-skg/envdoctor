# frozen_string_literal: true

module Envdoctor
  # Core scanner: reconcile ENV usage in Ruby source against .env definitions.
  # Local-first — no network, values never printed.
  module Scanner
    module_function

    USAGE_PATTERNS = [
      /\bENV\[\s*["']([A-Za-z_]\w*)["']\s*\]/,
      /\bENV\.fetch\(\s*["']([A-Za-z_]\w*)["']/
    ].freeze

    ENV_LINE = /\A\s*(?:export\s+)?([A-Za-z_]\w*)\s*=/.freeze

    Origin = Struct.new(:file, :line)
    Finding = Struct.new(:rule, :severity, :name, :message, :origin)

    # Blank comments and =begin/=end blocks, preserving line structure.
    def strip_noise(code)
      code = code.gsub(/^=begin\b.*?^=end\b[^\n]*/m) { |m| m.gsub(/[^\n]/, " ") }
      code.gsub(/#[^\n]*/) { |m| " " * m.length }
    end

    def scan_source(path, content)
      text = strip_noise(content)
      used = {}
      USAGE_PATTERNS.each do |re|
        text.to_enum(:scan, re).each do
          match = Regexp.last_match
          name = match[1]
          next if used.key?(name)

          line = text[0...match.begin(0)].count("\n") + 1
          used[name] = Origin.new(path, line)
        end
      end
      used
    end

    def parse_env(path, content)
      defined = {}
      content.split("\n").each_with_index do |raw, i|
        stripped = raw.strip
        next if stripped.empty? || stripped.start_with?("#")

        if (m = raw.match(ENV_LINE))
          defined[m[1]] ||= Origin.new(path, i + 1)
        end
      end
      defined
    end

    def discover_env_files(root)
      files = Dir.glob(File.join(root, ".env"))
      files += Dir.glob(File.join(root, ".env.*")).reject { |f| f.end_with?(".example") }
      files.sort
    end

    def discover_source_files(root)
      Dir.glob(File.join(root, "**", "*.rb")).reject do |p|
        p.split(File::SEPARATOR).any? { |part| %w[.git vendor node_modules].include?(part) }
      end.sort
    end

    def scan(root)
      defined = {}
      discover_env_files(root).each do |f|
        parse_env(relative(root, f), File.read(f)).each { |k, v| defined[k] ||= v }
      end

      used = {}
      discover_source_files(root).each do |f|
        scan_source(relative(root, f), File.read(f)).each { |k, v| used[k] ||= v }
      end

      findings = []
      used.keys.sort.each do |name|
        next if defined.key?(name)

        findings << Finding.new("undefined-in-source", "error", name,
                                "used in source code but not defined in any environment file",
                                used[name])
      end
      defined.keys.sort.each do |name|
        next if used.key?(name)

        findings << Finding.new("unused", "warning", name,
                                "defined but never referenced in source", defined[name])
      end
      findings
    end

    def relative(root, path)
      path.sub(/\A#{Regexp.escape(root)}#{Regexp.escape(File::SEPARATOR)}?/, "")
    end
  end
end
