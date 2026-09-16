defmodule Envdoctor do
  @moduledoc """
  envdoctor — a local-first consistency checker for environment variables
  (native Elixir port).

  Reconciles the environment variables **used** in your Elixir source
  (`System.get_env("X")`, `System.fetch_env("X")`, `System.fetch_env!("X")`)
  and in infra files (Docker Compose, GitHub Actions, Kubernetes) against
  those **defined** in your `.env` files. Nothing is uploaded and variable
  values are never printed.
  """

  alias Envdoctor.Scanner
  alias Envdoctor.Scanner.{Finding, Origin, ScanResult}

  @version "0.1.2"

  @doc "envdoctor version."
  def version, do: @version

  @doc "Audit environment variables under `root`. See `Envdoctor.Scanner.scan/2`."
  @spec scan(Path.t(), [String.t()]) :: ScanResult.t()
  def scan(root, extensions \\ Scanner.default_extensions()),
    do: Scanner.scan(root, extensions)

  @doc "Compare the variable names defined in two environment labels."
  defdelegate diff_labels(root, a, b), to: Scanner

  @doc "Copy missing keys between environments (values are never copied)."
  def sync_labels(root, src, dst, dry_run \\ false),
    do: Scanner.sync_labels(root, src, dst, dry_run)

  @doc "Return `%{filename => content}` for `.env.example` and `ENVIRONMENT.md`."
  def generate_docs(root, extensions \\ Scanner.default_extensions()),
    do: Scanner.generate_docs(root, extensions)

  @doc "Capture this machine's live runtime into a snapshot."
  def capture_snapshot(opts \\ []), do: Envdoctor.Runtime.Capture.capture(opts)

  @doc "Compare two runtime snapshots."
  defdelegate compare_snapshots(a, b), to: Envdoctor.Runtime.Compare, as: :compare

  @doc "Encode a runtime snapshot into a paste-safe `envd1:` token."
  defdelegate encode_token(snapshot), to: Envdoctor.Runtime.Token, as: :encode

  @doc "Decode an `envd1:` token back into a runtime snapshot."
  defdelegate decode_token(token), to: Envdoctor.Runtime.Token, as: :decode

  # Keep aliases referenced for docs/types.
  @type finding :: Finding.t()
  @type origin :: Origin.t()
end
