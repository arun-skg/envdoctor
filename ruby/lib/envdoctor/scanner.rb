# frozen_string_literal: true

require "json"

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

    PUBLIC_PREFIXES = %w[
      NEXT_PUBLIC_ VITE_ REACT_APP_ EXPO_PUBLIC_ GATSBY_ NUXT_PUBLIC_ VUE_APP_ PUBLIC_
    ].freeze

    SECRET_RE = /SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE|CREDENTIAL|API_?KEY|ACCESS_?KEY|AUTH/i.freeze

    WEAK_VALUE_RE =
      /\A(changeme|change_me|placeholder|x{3,}|todo|secret|password|passwd|test|example|sample|dummy|your[_-].*|<.*>|\$\{.*\})\z/i.freeze

    Origin = Struct.new(:file, :line)
    # A single .env definition occurrence: its line and parsed value.
    Definition = Struct.new(:line, :value)
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

    # Parse the VALUE to the right of the first `=`: trim, then strip one pair
    # of matching surrounding quotes. Values are used ONLY for detection and are
    # never surfaced in any output.
    def parse_value(raw)
      idx = raw.index("=")
      return "" if idx.nil?

      value = raw[(idx + 1)..].to_s.strip
      if value.length >= 2 && %w[" '].include?(value[0]) && value[-1] == value[0]
        value = value[1..-2]
      end
      value
    end

    # Returns { name => [Definition, ...] } with ALL occurrences per key in order.
    def parse_env(path, content)
      defined = {}
      content.split("\n").each_with_index do |raw, i|
        stripped = raw.strip
        next if stripped.empty? || stripped.start_with?("#")

        if (m = raw.match(ENV_LINE))
          (defined[m[1]] ||= []) << Definition.new(i + 1, parse_value(raw))
        end
      end
      defined
    end

    # Derive the environment label from a .env filename.
    def env_label(filename)
      base = File.basename(filename)
      return "default" if base == ".env"

      label = base.sub(/\A\.env\./, "")
      label = label.sub(/\.local\z/, "") if label.end_with?(".local")
      label
    end

    def public_prefix?(name)
      PUBLIC_PREFIXES.any? { |p| name.start_with?(p) } && SECRET_RE.match?(name)
    end

    # Infer the coarse type of a value string.
    def infer_type(value)
      return "empty" if value.empty?
      return "integer" if value.match?(/\A-?\d+\z/)
      return "float" if value.match?(/\A-?\d+\.\d+\z/)
      return "boolean" if value.match?(/\A(true|false)\z/i)
      return "url" if value.match?(%r{\Ahttps?://})

      if value.start_with?("{", "[")
        begin
          JSON.parse(value)
          return "json"
        rescue JSON::ParserError
          # fall through to string
        end
      end
      "string"
    end

    # Compatibility group for an inferred type (integer/float collapse to numeric).
    def type_group(type)
      %w[integer float].include?(type) ? "numeric" : type
    end

    def weak_secret?(value)
      value.empty? || value.length < 8 || WEAK_VALUE_RE.match?(value)
    end

    def levenshtein(a, b)
      return b.length if a.empty?
      return a.length if b.empty?

      prev = (0..b.length).to_a
      a.each_char.with_index do |ca, i|
        curr = [i + 1]
        b.each_char.with_index do |cb, j|
          cost = ca == cb ? 0 : 1
          curr << [curr[j] + 1, prev[j + 1] + 1, prev[j] + cost].min
        end
        prev = curr
      end
      prev[b.length]
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

    COMPOSE_RE = /\A(docker-)?compose([.-].*)?\.ya?ml\z/i.freeze

    def skip_infra_path?(path)
      path.split(File::SEPARATOR).any? { |part| %w[.git vendor node_modules target].include?(part) }
    end

    # Walk the project and classify infra YAML files. Returns [[path, kind], ...]
    # where kind is one of :compose, :actions, :k8s.
    def discover_infra_files(root)
      out = []
      Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).each do |path|
        next unless File.file?(path)
        next if skip_infra_path?(path)

        base = File.basename(path)
        segments = path.split(File::SEPARATOR)
        if base.match?(COMPOSE_RE)
          out << [path, :compose]
        elsif base =~ /\.ya?ml\z/i &&
              segments.each_cons(2).any? { |a, b| a == ".github" && b == "workflows" }
          out << [path, :actions]
        elsif base =~ /\.ya?ml\z/i
          content = File.read(path)
          out << [path, :k8s] if content.match?(/^apiVersion:/m) && content.match?(/^kind:/m)
        end
      end
      out.sort_by(&:first)
    end

    INTERP_PATTERNS = [
      /\$\{([A-Za-z_][A-Za-z0-9_]*)/,
      /\$([A-Za-z_][A-Za-z0-9_]*)/
    ].freeze

    ACTIONS_CONTEXT_RE = /\b(?:secrets|vars|env)\.([A-Za-z_][A-Za-z0-9_]*)/.freeze

    # Extract used variable NAMES (with origin) from an infra YAML file. First
    # removes escaped `$$` (two spaces, offsets preserved), then scans for
    # interpolation and, for GitHub Actions, the secrets/vars/env contexts.
    def scan_infra(path, content, kind)
      text = content.gsub("$$", "  ")
      used = {}
      patterns = INTERP_PATTERNS.dup
      patterns << ACTIONS_CONTEXT_RE if kind == :actions
      patterns.each do |re|
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

    # Map each environment label to the set of variable names defined in it.
    def defined_by_label(root)
      labels = {}
      discover_env_files(root).each do |f|
        set = (labels[env_label(f)] ||= [])
        parse_env(f, File.read(f)).each_key { |name| set << name unless set.include?(name) }
      end
      labels
    end

    def diff_labels(root, a, b)
      labels = defined_by_label(root)
      da = labels[a] || []
      db = labels[b] || []
      {
        "onlyInA" => (da - db).sort,
        "onlyInB" => (db - da).sort,
        "common" => (da & db).sort
      }
    end

    # Append keys present in `from` but missing from `to` as `KEY=` placeholders.
    # Values are never copied.
    def sync_labels(root, from, to, dry_run: false)
      labels = defined_by_label(root)
      missing = ((labels[from] || []) - (labels[to] || [])).sort
      if !missing.empty? && !dry_run
        target = File.join(root, to == "default" ? ".env" : ".env.#{to}")
        existing = File.exist?(target) ? File.read(target) : ""
        prefix = (existing.empty? || existing.end_with?("\n")) ? "" : "\n"
        File.open(target, "a") { |fh| fh.write(prefix + missing.map { |k| "#{k}=\n" }.join) }
      end
      missing
    end

    # Collect the DEFINED (from .env*) and USED (source + infra) name sets for a
    # project. Returns [defined_hash, used_hash] with name => true entries.
    def collect_names(root)
      defined = {}
      discover_env_files(root).each do |f|
        parse_env(relative(root, f), File.read(f)).each_key { |name| defined[name] = true }
      end
      used = {}
      discover_source_files(root).each do |f|
        scan_source(relative(root, f), File.read(f)).each_key { |k| used[k] = true }
      end
      discover_infra_files(root).each do |f, kind|
        scan_infra(relative(root, f), File.read(f), kind).each_key { |k| used[k] = true }
      end
      [defined, used]
    end

    # Exact `.env.example` content: header, then `NAME=` per (defined ∪ used),
    # sorted ascending. Values are never written.
    def env_example_content(root)
      defined, used = collect_names(root)
      names = (defined.keys + used.keys).uniq.sort
      "# Generated by envdoctor. Fill in values; do not commit secrets.\n" +
        names.map { |n| "#{n}=\n" }.join
    end

    # Exact `ENVIRONMENT.md` content: a table of Defined/Used per variable.
    def environment_doc_content(root)
      defined, used = collect_names(root)
      names = (defined.keys + used.keys).uniq.sort
      lines = ["# Environment variables", "", "| Variable | Defined | Used |", "| --- | --- | --- |"]
      names.each do |n|
        lines << "| #{n} | #{defined.key?(n) ? 'yes' : 'no'} | #{used.key?(n) ? 'yes' : 'no'} |"
      end
      lines.join("\n") + "\n"
    end

    def scan(root)
      defined = {}          # name => Origin (first definition wins)
      defined_value = {}    # name => value at first definition
      labels_of = {}        # name => { label => value } (first value per label)
      project_labels = []
      dup_findings = []

      discover_env_files(root).each do |f|
        rel = relative(root, f)
        label = env_label(f)
        project_labels << label unless project_labels.include?(label)
        parse_env(rel, File.read(f)).each do |name, defs|
          if defs.length >= 2
            lines = defs.map(&:line)
            dup_findings << Finding.new("duplicates", "error", name,
                                        "defined #{defs.length} times in the same file " \
                                        "(lines #{lines.join(', ')})",
                                        Origin.new(rel, defs.first.line))
          end
          # First occurrence (first file wins) counts as the definition.
          unless defined.key?(name)
            defined[name] = Origin.new(rel, defs.first.line)
            defined_value[name] = defs.first.value
          end
          bucket = (labels_of[name] ||= {})
          bucket[label] = defs.first.value unless bucket.key?(label)
        end
      end

      used = {}
      discover_source_files(root).each do |f|
        scan_source(relative(root, f), File.read(f)).each { |k, v| used[k] ||= v }
      end
      # Infra sources (Docker Compose / GitHub Actions / Kubernetes) contribute
      # additional used names; first origin wins.
      discover_infra_files(root).each do |f, kind|
        scan_infra(relative(root, f), File.read(f), kind).each { |k, v| used[k] ||= v }
      end

      errors = []
      warnings = []

      # --- errors: undefined-in-source ---
      used.keys.sort.each do |name|
        next if defined.key?(name)

        errors << Finding.new("undefined-in-source", "error", name,
                              "referenced but not defined in any environment file",
                              used[name])
      end

      # --- errors: duplicates ---
      dup_findings.sort_by(&:name).each { |finding| errors << finding }

      # --- errors: public-prefix ---
      defined.keys.sort.each do |name|
        next unless public_prefix?(name)

        errors << Finding.new("public-prefix", "error", name,
                              "secret-looking variable is exposed to client bundles " \
                              "via a public prefix", defined[name])
      end

      # --- errors: type-mismatch ---
      defined.keys.sort.each do |name|
        labels = labels_of[name] || {}
        next if labels.size < 2

        groups = labels.values.map { |v| infer_type(v) }.reject { |t| t == "empty" }
                       .map { |t| type_group(t) }.uniq
        next if groups.size < 2

        errors << Finding.new("type-mismatch", "error", name,
                              "inferred type differs across environments", defined[name])
      end

      # --- errors: schema-validation ---
      load_schema(root).sort.each do |name, rule|
        next unless rule.is_a?(Hash)

        if defined.key?(name)
          msg = schema_failure(rule, defined_value[name])
          errors << Finding.new("schema-validation", "error", name, msg, defined[name]) if msg
        elsif !rule["optional"]
          errors << Finding.new("schema-validation", "error", name,
                                "required by schema but not defined", nil)
        end
      end

      # --- warnings: unused ---
      defined.keys.sort.each do |name|
        next if used.key?(name)

        warnings << Finding.new("unused", "warning", name,
                                "defined but never referenced in source", defined[name])
      end

      # --- warnings: environment-diff ---
      if project_labels.length >= 2
        defined.keys.sort.each do |name|
          present = (labels_of[name] || {}).keys.sort
          absent = (project_labels - present).sort
          next if present.empty? || absent.empty?

          warnings << Finding.new("environment-diff", "warning", name,
                                  "defined in #{present.join(', ')} but missing in " \
                                  "#{absent.join(', ')}", defined[name])
        end
      end

      # --- warnings: weak-secret ---
      defined.keys.sort.each do |name|
        next unless SECRET_RE.match?(name)
        next unless weak_secret?(defined_value[name].to_s)

        warnings << Finding.new("weak-secret", "warning", name,
                                "secret-looking variable has a weak or placeholder value",
                                defined[name])
      end

      # --- warnings: typo ---
      defined_names = defined.keys
      used.keys.sort.each do |u|
        next if defined.key?(u)

        best = nil
        best_dist = nil
        defined_names.each do |d|
          next if d == u

          limit = [u.length, d.length].min <= 4 ? 1 : 2
          dist = levenshtein(u, d)
          next if dist > limit

          if best.nil? || dist < best_dist || (dist == best_dist && d < best)
            best = d
            best_dist = dist
          end
        end
        next if best.nil?

        warnings << Finding.new("typo", "warning", u,
                                "\"#{u}\" is not defined; did you mean \"#{best}\"?",
                                used[u])
      end

      errors + warnings
    end

    # Serialize findings to the shared JSON shape. Values never appear.
    NUMERIC_RE = /\A-?\d+(\.\d+)?\z/.freeze

    def load_schema(root)
      require "json"
      data = JSON.parse(File.read(File.join(root, "envdoctor.schema.json")))
      data.is_a?(Hash) ? data : {}
    rescue StandardError
      {}
    end

    def schema_type_ok(value, declared)
      case declared
      when "string" then true
      when "integer" then value.match?(/\A-?\d+\z/)
      when "float" then value.match?(/\A-?\d+(\.\d+)?\z/)
      when "boolean" then %w[true false].include?(value.downcase)
      when "url" then value.match?(%r{\Ahttps?://})
      when "json" then (JSON.parse(value); true rescue false)
      else true
      end
    end

    def schema_failure(rule, value)
      t = rule["type"]
      return "value does not match schema type #{t}" if t.is_a?(String) && !schema_type_ok(value, t)

      enum = rule["enum"]
      return "value is not one of the allowed values" if enum.is_a?(Array) && !enum.include?(value)

      pattern = rule["regex"]
      if pattern.is_a?(String)
        begin
          return "value does not match the required pattern" if value !~ Regexp.new(pattern)
        rescue RegexpError
          # ignore invalid pattern
        end
      end

      if value.match?(NUMERIC_RE)
        num = value.to_f
        lo = rule["min"]
        return "value is below the minimum" if lo.is_a?(Numeric) && num < lo

        hi = rule["max"]
        return "value exceeds the maximum" if hi.is_a?(Numeric) && num > hi
      end
      nil
    end

    def to_json_array(findings)
      JSON.generate(findings.map do |f|
        {
          "rule" => f.rule,
          "severity" => f.severity,
          "name" => f.name,
          "message" => f.message,
          "file" => f.origin&.file,
          "line" => f.origin&.line
        }
      end)
    end

    def relative(root, path)
      path.sub(/\A#{Regexp.escape(root)}#{Regexp.escape(File::SEPARATOR)}?/, "")
    end
  end
end
