defmodule Mehungry.USDA.FdcClient do
  @moduledoc """
  HTTP client for the USDA FoodData Central (FDC) API.

  Searches for an ingredient by name (SR Legacy → Foundation data priority),
  fetches full nutrient detail, and returns a JSON string in the same format
  that FdcFoodParserLeg.get_ingredients_from_json_body/1 expects.

  Set FDC_API_KEY in the environment. Free API keys:
  https://api.nal.usda.gov/api-key-signup
  """

  require Logger

  @base_url "https://api.nal.usda.gov/fdc/v1"
  @timeout_ms 15_000

  @doc """
  Looks up an ingredient by name in the USDA FDC database.

  Returns `{:ok, json_string}` where json_string is a single-element JSON array
  in the FdcFoodParserLeg-compatible format, or `{:error, reason}` if the lookup
  fails (caller should fall back to AI estimation).
  """
  def lookup(name) do
    case api_key() do
      key when key in [nil, ""] ->
        {:error, "FDC_API_KEY not configured"}

      key ->
        with {:ok, fdc_id, description} <- search(name, key),
             {:ok, food} <- fetch(fdc_id, key) do
          Logger.info("[FdcClient] Matched '#{description}' (fdcId=#{fdc_id}) for '#{name}'")
          json = food |> to_parser_format() |> List.wrap() |> Jason.encode!()
          {:ok, json}
        end
    end
  end

  # ── private ──────────────────────────────────────────────────────────────────

  defp search(name, api_key) do
    params =
      URI.encode_query(%{
        query: name,
        dataType: "SR Legacy,Foundation",
        pageSize: 1,
        api_key: api_key
      })

    url = "#{@base_url}/foods/search?#{params}"

    case HTTPoison.get(url, [], recv_timeout: @timeout_ms) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"foods" => [%{"fdcId" => fdc_id, "description" => desc} | _]}} ->
            {:ok, fdc_id, desc}

          {:ok, %{"foods" => []}} ->
            {:error, "no FDC results for '#{name}'"}

          {:ok, _other} ->
            {:error, "unexpected FDC search response shape"}

          {:error, reason} ->
            {:error, "FDC search JSON parse error: #{inspect(reason)}"}
        end

      {:ok, %{status_code: code}} ->
        {:error, "FDC search HTTP #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "FDC search network error: #{inspect(reason)}"}
    end
  end

  defp fetch(fdc_id, api_key) do
    url = "#{@base_url}/food/#{fdc_id}?api_key=#{api_key}"

    case HTTPoison.get(url, [], recv_timeout: @timeout_ms) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, food} -> {:ok, food}
          {:error, reason} -> {:error, "FDC fetch JSON parse error: #{inspect(reason)}"}
        end

      {:ok, %{status_code: code}} ->
        {:error, "FDC fetch HTTP #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "FDC fetch network error: #{inspect(reason)}"}
    end
  end

  # Converts the FDC API /food/{fdcId} response to the nested-map format expected
  # by FdcFoodParserLeg.create_ingredient/1.
  defp to_parser_format(food) do
    %{
      "description" => food["description"],
      "foodClass" => food["foodClass"] || "FinalFood",
      "publicationDate" => food["publicationDate"] || "4/1/2019",
      "nutrientConversionFactors" => food["nutrientConversionFactors"] || [],
      "foodCategory" => normalize_category(food["foodCategory"]),
      "foodPortions" => normalize_portions(food["foodPortions"] || []),
      "foodNutrients" => normalize_nutrients(food["foodNutrients"] || [])
    }
  end

  defp normalize_category(nil), do: %{"description" => "General"}
  defp normalize_category(cat) when is_binary(cat), do: %{"description" => cat}
  defp normalize_category(%{"description" => desc}), do: %{"description" => desc || "General"}
  defp normalize_category(_), do: %{"description" => "General"}

  defp normalize_portions(portions) do
    portions
    |> Enum.with_index(1)
    |> Enum.map(fn {p, i} ->
      gram_weight = p["gramWeight"] || 100.0
      amount = p["amount"] || 1.0
      modifier = p["modifier"] || extract_unit(p["portionDescription"]) || "serving"

      %{
        "modifier" => modifier,
        "gramWeight" => gram_weight,
        "amount" => amount,
        "value" => gram_weight,
        "id" => p["id"] || i,
        "sequenceNumber" => p["sequenceNumber"] || i,
        "minYearAcquired" => p["minYearAcquired"]
      }
    end)
  end

  defp normalize_nutrients(nutrients) do
    nutrients
    |> Enum.filter(fn n -> is_map(n["nutrient"]) and not is_nil(n["nutrient"]["id"]) end)
    |> Enum.map(fn n ->
      nut = n["nutrient"]

      %{
        "amount" => n["amount"] || 0.0,
        "median" => n["median"],
        "dataPoints" => n["dataPoints"],
        "type" => "FoodNutrient",
        "nutrient" => %{
          "id" => nut["id"],
          "name" => nut["name"],
          "number" => to_string(nut["number"] || ""),
          "rank" => nut["rank"] || 0,
          "unitName" => normalize_unit(nut["unitName"])
        }
      }
    end)
  end

  defp normalize_unit(nil), do: "g"
  defp normalize_unit("G"), do: "g"
  defp normalize_unit("MG"), do: "mg"
  defp normalize_unit("UG"), do: "µg"
  defp normalize_unit("KCAL"), do: "kcal"
  defp normalize_unit("KJ"), do: "kJ"
  defp normalize_unit(u), do: String.downcase(u)

  # Best-effort unit extraction from a portion description like "1 cup, whole"
  defp extract_unit(nil), do: nil

  defp extract_unit(desc) do
    desc
    |> String.split(~r/[\s,]+/)
    |> Enum.find(fn word -> String.length(word) > 1 and Regex.match?(~r/^[a-zA-Z]+$/, word) end)
  end

  defp api_key do
    Application.get_env(:mehungry, :fdc_api_key, "")
  end
end
