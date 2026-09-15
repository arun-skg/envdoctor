defmodule Envdoctor.Runtime.Token do
  @moduledoc """
  Portable snapshot token: `envd1:` + base64url(gzip(json)). Compact enough to
  paste into an issue or chat, self-contained, and schema-versioned so a
  decoder can refuse a token from a newer envdoctor instead of mis-diffing it.
  """

  alias Envdoctor.Json
  alias Envdoctor.Runtime.Capture

  @prefix "envd1:"

  @doc "Encode a snapshot into a single-line, paste-safe token."
  def encode(snapshot) do
    @prefix <> (snapshot |> Json.encode!() |> :zlib.gzip() |> Base.url_encode64(padding: false))
  end

  @doc "Decode a token back into a snapshot. Errors are clear and non-raising."
  def decode(token) do
    trimmed = String.trim(token)

    if String.starts_with?(trimmed, @prefix) do
      payload = String.slice(trimmed, byte_size(@prefix)..-1//1)

      with {:ok, gz} <- Base.url_decode64(payload, padding: false),
           {:ok, json} <- gunzip(gz),
           {:ok, raw} <- Json.decode(json) do
        raw |> normalize() |> assert_readable()
      else
        _ -> {:error, "Corrupt snapshot token: could not decode."}
      end
    else
      {:error, "Not an envdoctor snapshot token (missing envd1: prefix)."}
    end
  end

  @doc "Parse raw JSON (from a `--output` file) into a validated snapshot."
  def parse_json(text) do
    case Json.decode(text) do
      {:ok, raw} -> raw |> normalize() |> assert_readable()
      :error -> {:error, "Invalid snapshot JSON."}
    end
  end

  defp gunzip(gz) do
    {:ok, :zlib.gunzip(gz)}
  rescue
    _ -> :error
  end

  # Normalize decoded JSON (string keys) into the atom-keyed snapshot shape.
  defp normalize(%{} = raw) do
    os = Map.get(raw, "os", %{})

    tools =
      raw
      |> Map.get("tools", [])
      |> List.wrap()
      |> Enum.map(fn t when is_map(t) ->
        %{
          tool: Map.get(t, "tool", ""),
          version: Map.get(t, "version", ""),
          resolvedFrom: Map.get(t, "resolvedFrom", "")
        }
      end)

    globals =
      raw
      |> Map.get("globals", %{})
      |> then(fn
        g when is_map(g) ->
          Map.new(g, fn {eco, pkgs} ->
            {eco,
             pkgs
             |> List.wrap()
             |> Enum.map(fn p when is_map(p) ->
               %{name: Map.get(p, "name", ""), version: Map.get(p, "version", "")}
             end)}
          end)

        _ ->
          %{}
      end)

    %{
      schema: Map.get(raw, "schema"),
      capturedAt: Map.get(raw, "capturedAt", ""),
      os: %{
        platform: Map.get(os, "platform", ""),
        arch: Map.get(os, "arch", ""),
        release: Map.get(os, "release", "")
      },
      tools: tools,
      path: raw |> Map.get("path", []) |> List.wrap(),
      globals: globals,
      envFlagNames: raw |> Map.get("envFlagNames", []) |> List.wrap()
    }
  end

  defp assert_readable(%{schema: schema, tools: tools} = snapshot) do
    cond do
      not is_integer(schema) or not is_list(tools) ->
        {:error, "Not a runtime snapshot."}

      schema > Capture.snapshot_schema() ->
        {:error,
         "Snapshot schema v#{schema} is newer than this envdoctor (v#{Capture.snapshot_schema()}). Upgrade to compare it."}

      true ->
        {:ok, snapshot}
    end
  end
end
