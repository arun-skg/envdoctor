defmodule Envdoctor.Json do
  @moduledoc """
  Thin wrapper over OTP's `:json` with a small pretty printer, so snapshot
  output matches the reference's `JSON.stringify(..., null, 2)` shape.
  """

  @doc "Compact JSON encoding to a binary."
  def encode!(term), do: term |> :json.encode() |> IO.iodata_to_binary()

  @doc "Decode a binary, returning `{:ok, term}` or `:error`."
  def decode(binary) do
    {:ok, :json.decode(binary)}
  rescue
    _ -> :error
  end

  @doc "Pretty-print with 2-space indentation, matching JSON.stringify(., null, 2)."
  def pretty(term), do: do_pretty(term, 0) <> "\n"

  defp do_pretty(map, indent) when is_map(map) do
    if map_size(map) == 0 do
      "{}"
    else
      inner =
        map
        |> Enum.map(fn {k, v} ->
          key = if is_atom(k), do: Atom.to_string(k), else: to_string(k)
          key_json = key |> :json.encode() |> IO.iodata_to_binary()
          pad(indent + 1) <> key_json <> ": " <> do_pretty(v, indent + 1)
        end)
        |> Enum.join(",\n")

      "{\n" <> inner <> "\n" <> pad(indent) <> "}"
    end
  end

  defp do_pretty(list, indent) when is_list(list) do
    if list == [] do
      "[]"
    else
      inner =
        list
        |> Enum.map(&(pad(indent + 1) <> do_pretty(&1, indent + 1)))
        |> Enum.join(",\n")

      "[\n" <> inner <> "\n" <> pad(indent) <> "]"
    end
  end

  defp do_pretty(other, _indent), do: other |> :json.encode() |> IO.iodata_to_binary()

  defp pad(indent), do: String.duplicate("  ", indent)
end
