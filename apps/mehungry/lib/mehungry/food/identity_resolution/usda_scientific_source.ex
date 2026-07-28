defmodule Mehungry.Food.IdentityResolution.UsdaScientificSource do
  @moduledoc """
  Harvests the USDA FoodData Central `scientificName` for an ingredient.

  The FDC detail endpoint `/food/{fdcId}` returns a top-level `scientificName` for
  Foundation and SR-Legacy foods (e.g. spinach → "Spinacia oleracea"). The
  ingestion adapter (`FdcClient.to_parser_format/1`) deliberately discards it, so
  this module re-fetches the detail record — reusing the shared, retry/rate-limit
  aware HTTP layer `Mehungry.FoodData.Usda.FdcHttp.get/1` — and reads it directly.

  Read-only and additive: it does not touch `FdcClient`, `FoodParser`, or any
  ingestion/reconciliation code.

  Swappable in tests via the `:usda_scientific_source` app-env key.
  """

  alias Mehungry.FoodData.Usda.FdcHttp

  @base_url "https://api.nal.usda.gov/fdc/v1"

  @doc """
  Fetches the USDA scientific name for a known `fdc_id`.

  Returns `{:ok, %{scientific_name: name | nil, description: str, data_type: str}, meta}`
  (meta carries `x-ratelimit-remaining`), `{:error, {:rate_limited, seconds}}`, or
  `{:error, reason}`.
  """
  def fetch_scientific_name(fdc_id) when is_integer(fdc_id) do
    case api_key() do
      key when key in [nil, ""] ->
        {:error, "FDC_API_KEY not configured"}

      key ->
        case FdcHttp.get("#{@base_url}/food/#{fdc_id}?api_key=#{key}") do
          {:ok, food, meta} ->
            {:ok,
             %{
               scientific_name: normalize(food["scientificName"]),
               description: food["description"],
               data_type: food["dataType"]
             }, meta}

          {:error, {:rate_limited, _} = reason} ->
            {:error, reason}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # A scientific name is only meaningful when it is a proper binomial-ish string;
  # blank/whitespace becomes nil so callers record "no_scientific_name".
  defp normalize(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize(_), do: nil

  defp api_key, do: Application.get_env(:mehungry, :fdc_api_key, "")
end
