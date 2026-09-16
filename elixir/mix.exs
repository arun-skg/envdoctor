defmodule Envdoctor.MixProject do
  use Mix.Project

  @version "0.1.2"

  def project do
    [
      app: :envdoctor,
      version: @version,
      elixir: "~> 1.14",
      escript: [main_module: Envdoctor.CLI, name: "envdoctor"],
      deps: deps(),
      package: package(),
      description:
        "Local-first consistency checker for environment variables (native Elixir port)",
      name: "envdoctor",
      source_url: "https://github.com/arun-skg/envdoctor"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:yaml_elixir, "~> 2.9"}
    ]
  end

  defp package do
    [
      name: "envdoctor",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/arun-skg/envdoctor"},
      files: ~w(lib mix.exs README.md)
    ]
  end
end
