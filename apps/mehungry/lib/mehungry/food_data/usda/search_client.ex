defmodule Mehungry.FoodData.Usda.SearchClient do
  @moduledoc """
  USDA FoodData Central API client for shopping basket item search.

  Goes through `Mehungry.FoodData.Usda.FdcHttp` so it shares the same
  retry/backoff and rate-limit handling as the rest of the FDC callers. A
  rate-limited request surfaces as `{:error, {:rate_limited, retry_after}}`;
  callers currently treat any `{:error, _}` as "no results".
  """

  alias Mehungry.FoodData.Usda.FdcHttp

  @api_url "https://api.nal.usda.gov/fdc/v1"

  def search_foods(query, page_size \\ 10) do
    with {:ok, api_key} <- api_key() do
      url =
        "#{@api_url}/foods/search?api_key=#{api_key}&query=#{URI.encode(query)}&pageSize=#{page_size}&dataType=Foundation,SR%20Legacy"

      case FdcHttp.get(url) do
        {:ok, %{"foods" => foods}, _meta} -> {:ok, format_search_results(foods)}
        {:ok, _other, _meta} -> {:ok, []}
        {:error, _} = err -> err
      end
    end
  end

  def get_food_details(fdc_id) do
    with {:ok, api_key} <- api_key() do
      case FdcHttp.get("#{@api_url}/food/#{fdc_id}?api_key=#{api_key}") do
        {:ok, food, _meta} -> {:ok, food}
        {:error, _} = err -> err
      end
    end
  end

  defp api_key do
    case Application.get_env(:mehungry, :fdc_api_key, "") do
      key when key in [nil, ""] -> {:error, :fdc_api_key_not_configured}
      key -> {:ok, key}
    end
  end

  defp format_search_results(foods) do
    Enum.map(foods, fn food ->
      %{
        fdc_id: food["fdcId"],
        description: food["description"],
        data_type: food["dataType"],
        brand: food["brandOwner"]
      }
    end)
  end
end
