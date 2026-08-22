# frozen_string_literal: true

require_relative "lib/envdoctor"

Gem::Specification.new do |spec|
  spec.name = "envdoctor"
  spec.version = Envdoctor::VERSION
  spec.authors = ["Arun Natesan"]
  spec.summary = "Local-first consistency checker for environment variables (native Ruby port)"
  spec.description = "Reconciles ENV usage in Ruby source against .env files: reports " \
                     "undefined-in-source (error) and unused (warning). Local-first, no network."
  spec.homepage = "https://github.com/arun-skg/envdoctor"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6"

  spec.files = Dir["lib/**/*.rb", "exe/*", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["envdoctor"]
  spec.require_paths = ["lib"]

  spec.metadata = {
    "source_code_uri" => "https://github.com/arun-skg/envdoctor",
    "rubygems_mfa_required" => "true"
  }
end
