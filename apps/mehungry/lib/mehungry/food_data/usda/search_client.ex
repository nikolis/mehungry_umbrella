defmodule Mehungry.FoodData.Usda.SearchClient do
  @moduledoc """
  USDA FoodData Central API client for shopping basket item search
  """

  @api_url "https://api.nal.usda.gov/fdc/v1"

  def search_foods(query, page_size \\ 10) do
    with {:ok, api_key} <- api_key() do
      url =
        "#{@api_url}/foods/search?api_key=#{api_key}&query=#{URI.encode(query)}&pageSize=#{page_size}&dataType=Foundation,SR%20Legacy"

      case Req.get(url) do
        {:ok, %Req.Response{status: 200, body: %{"foods" => foods}}} ->
          {:ok, format_search_results(foods)}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  def get_food_details(fdc_id) do
    with {:ok, api_key} <- api_key() do
      url = "#{@api_url}/food/#{fdc_id}?api_key=#{api_key}"

      case Req.get(url) do
        {:ok, %Req.Response{status: 200, body: food}} ->
          {:ok, food}

        {:error, error} ->
          {:error, error}
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
