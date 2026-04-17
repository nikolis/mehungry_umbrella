defmodule MehungryWeb.IngredientSearch do
  use GenServer
  require Logger

  @api_base "https://api.nal.usda.gov/fdc/v1"

  # Client API

  def start_link(opts \\ []) do
    api_key = "ICjMhFVerhu917ppnyybL7ozeXGbftEk3q7li2GM"
    GenServer.start_link(__MODULE__, api_key, name: __MODULE__)
  end

  def search_ingredients(query, data_types \\ ["Foundation", "SR Legacy"]) do
    GenServer.call(__MODULE__, {:search, query, data_types})
  end

  def get_food_details(fdc_id) do
    GenServer.call(__MODULE__, {:food_details, fdc_id})
  end

  # Server Callbacks

  @impl true
  def init(api_key) do
    {:ok, %{api_key: api_key, cache: %{}}}
  end

  @impl true
  def handle_call({:search, query, data_types}, _from, state) do
    result = perform_search(state.api_key, query, data_types)
    {:reply, result, state}
  end

  def handle_call({:food_details, fdc_id}, _from, state) do
    # Check cache first
    result =
      case Map.get(state.cache, fdc_id) do
        nil -> fetch_food_details(state.api_key, fdc_id)
        cached -> {:ok, cached}
      end

    # Cache if successful
    new_cache =
      case result do
        {:ok, food} -> Map.put(state.cache, fdc_id, food)
        _ -> state.cache
      end

    {:reply, result, %{state | cache: new_cache}}
  end

  defp perform_search(api_key, query, data_types) do
    url = "#{@api_base}/foods/search?api_key=#{api_key}&query=#{URI.encode(query)}&pageSize=20"

    case Req.post(url, json: %{dataType: data_types}) do
      {:ok, %Req.Response{status: 200, body: %{"foods" => foods}}} ->
        {:ok, format_search_results(foods)}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "Search failed: HTTP #{status}"}

      {:error, error} ->
        {:error, "Request failed: #{inspect(error)}"}
    end
  end

  defp format_search_results(foods) do
    Enum.map(foods, fn food ->
      %{
        fdc_id: food["fdcId"],
        name: food["description"],
        data_type: food["dataType"],
        brand: food["brandOwner"],
        portions: extract_portions(food),
        nutrients_summary: extract_nutrient_summary(food)
      }
    end)
  end

  defp extract_portions(food) do
    # Extract portion information from the food data
    # Portions can be in different places depending on data type
    portions = []

    # Check for foodPortions array (Foundation/SR Legacy)
    if food["foodPortions"] do
      portions =
        portions ++
          Enum.map(food["foodPortions"], fn portion ->
            %{
              description: portion["portionDescription"],
              gram_weight: portion["gramWeight"],
              amount: portion["amount"],
              measure_unit: portion["measureUnit"]
            }
          end)
    end

    # Check for serving size (Branded foods)
    if food["servingSize"] do
      portions =
        portions ++
          [
            %{
              description: "Serving",
              gram_weight: food["servingSize"],
              amount: food["servingSize"],
              measure_unit: food["servingSizeUnit"]
            }
          ]
    end

    portions
  end

  defp extract_nutrient_summary(food) do
    # Extract key nutrients for quick display
    nutrients = food["foodNutrients"] || []

    # Energy, Fat, Protein, Carbs
    key_nutrient_ids = ["1008", "1004", "1003", "1005"]

    Enum.filter(nutrients, fn n ->
      to_string(n["nutrientId"]) in key_nutrient_ids
    end)
    |> Enum.map(fn n ->
      %{
        name: Nutrition.NutrientMapper.get_nutrient_name(n["nutrientId"]),
        amount: n["amount"],
        unit: n["unitName"]
      }
    end)
  end

  defp fetch_food_details(api_key, fdc_id) do
    url = "#{@api_base}/food/#{fdc_id}?api_key=#{api_key}"

    case Req.get(url, retry: :transient) do
      {:ok, %Req.Response{status: 200, body: food}} ->
        %{
          fdc_id: food["fdcId"],
          name: food["description"],
          data_type: food["dataType"],
          brand: food["brandOwner"],
          ingredients: food["ingredients"],
          portions: extract_portions(food),
          nutrients: extract_all_nutrients(food)
        }

      {:ok, %Req.Response{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, error} ->
        {:error, "Request failed: #{inspect(error)}"}
    end
  end

  defp extract_all_nutrients(food) do
    nutrients = food["foodNutrients"] || []

    Enum.map(nutrients, fn nutrient ->
      %{
        id: nutrient["nutrientId"],
        name:
          Nutrition.NutrientMapper.get_nutrient_name(
            nutrient["nutrientId"],
            nutrient["nutrientName"]
          ),
        amount: nutrient["amount"],
        unit: nutrient["unitName"]
      }
    end)
    |> Enum.reject(fn n -> is_nil(n.amount) end)
  end
end
