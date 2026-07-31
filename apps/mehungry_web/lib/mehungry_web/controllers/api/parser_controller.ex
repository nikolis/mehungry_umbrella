defmodule MehungryWeb.Api.ParserController do
  @moduledoc """
  JSON endpoint over the deterministic USDA description parser.

      POST /api/parser/parse {"description": "Oil, corn", "trace": true}

  Pure and read-only — nothing is persisted; batch persistence goes through
  the science pipeline instead.
  """
  use MehungryWeb, :controller

  alias Mehungry.FoodData.Usda.Parser.{Pipeline, Result, Skipped}

  def parse(conn, %{"description" => description} = params) when is_binary(description) do
    case Pipeline.parse(description, trace: params["trace"] == true) do
      {:ok, %Result{} = result} ->
        json(conn, %{
          skipped: false,
          canonical_food: result.canonical_food,
          harvest_stage: result.harvest_stage,
          processing: result.processing,
          processing_modifiers: result.processing_modifiers,
          packaging: result.packaging,
          part: result.part,
          dismemberment: result.dismemberment,
          bone_state: result.bone_state,
          portion: result.portion,
          grade: result.grade,
          fat: result.fat,
          confidence: result.confidence,
          parser_version: Pipeline.version(),
          trace: trace_payload(result.trace)
        })

      {:skipped, %Skipped{} = skipped} ->
        json(conn, %{
          skipped: true,
          reason: skipped.reason,
          text: skipped.text,
          confidence: skipped.confidence,
          parser_version: Pipeline.version(),
          trace: trace_payload(skipped.trace)
        })
    end
  end

  def parse(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "missing required string parameter: description"})
  end

  defp trace_payload(nil), do: nil

  defp trace_payload(trace) do
    Enum.map(trace, fn entry ->
      Map.new(entry, fn {key, value} -> {key, json_safe(value)} end)
    end)
  end

  defp json_safe(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp json_safe(nil), do: nil

  defp json_safe(value) when is_atom(value),
    do: value |> Atom.to_string() |> String.trim_leading("Elixir.")

  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  defp json_safe(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {json_safe(k), json_safe(v)} end)

  defp json_safe(value), do: inspect(value)
end
