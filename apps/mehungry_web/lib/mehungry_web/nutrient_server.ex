defmodule MehungryWeb.NutrientServer do
  use GenServer
  require Logger

  @moduledoc """
  Fetches and caches USDA nutrient definitions at runtime.
  Provides human-readable names for both USDA and custom nutrients.
  """

  @api_base "https://api.nal.usda.gov/fdc/v1"

  # Client API

  def start_link(opts \\ []) do
    api_key = "ICjMhFVerhu917ppnyybL7ozeXGbftEk3q7li2GM"
    GenServer.start_link(__MODULE__, api_key, name: __MODULE__)
  end

  def get_nutrient_name(nutrient_id, nutrient_name \\ nil) do
    GenServer.call(__MODULE__, {:get_name, nutrient_id, nutrient_name})
  end

  def get_all_mappings, do: GenServer.call(__MODULE__, :all_mappings)

  # Server Callbacks

  @impl true
  def init(api_key) do
    Logger.info("Fetching nutrient definitions from USDA...")

    case fetch_nutrients_from_search(api_key) do
      {:ok, mappings} ->
        count = map_size(mappings)
        Logger.info("Loaded #{count} nutrient mappings")
        {:ok, %{mappings: mappings, api_key: api_key}}

      {:error, reason} ->
        Logger.error("Failed to load nutrients: #{reason}")
        # Fallback to built-in common nutrients
        {:ok, %{mappings: get_fallback_mappings(), api_key: api_key}}
    end
  end

  @impl true
  def handle_call({:get_name, nutrient_id, nil}, _from, state) do
    result = Map.get(state.mappings, to_string(nutrient_id), "Nutrient #{nutrient_id}")
    {:reply, result, state}
  end

  def handle_call({:get_name, nutrient_id, nutrient_name}, _from, state) do
    # Try ID first, then fallback to name-based humanization
    result =
      case Map.get(state.mappings, to_string(nutrient_id)) do
        nil -> humanize_nutrient_name(nutrient_name)
        name -> name
      end

    {:reply, result, state}
  end

  def handle_call(:all_mappings, _from, state) do
    {:reply, state.mappings, state}
  end

  # Fetch nutrients by searching for a comprehensive food
  defp fetch_nutrients_from_search(api_key) do
    # Search for a food that has complete nutrient profile
    # Foundation Foods typically have 50-100+ nutrients
    url = "#{@api_base}/foods/search?api_key=#{api_key}&query=raw apple&pageSize=1"

    case Req.get(url, retry: :transient) do
      {:ok, %Req.Response{status: 200, body: %{"foods" => [food | _]}}} ->
        extract_nutrient_mappings(food)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "HTTP #{status}"}

      {:error, error} ->
        {:error, "Request failed: #{inspect(error)}"}
    end
  end

  defp extract_nutrient_mappings(food) do
    nutrients = food["foodNutrients"] || []

    mappings =
      Enum.reduce(nutrients, %{}, fn nutrient, acc ->
        nutrient_id = to_string(nutrient["nutrientId"])
        nutrient_name = get_nutrient_name_from_api(nutrient)

        if nutrient_id && nutrient_name do
          human_name = humanize_nutrient_name(nutrient_name)
          Map.put(acc, nutrient_id, human_name)
        else
          acc
        end
      end)

    {:ok, mappings}
  end

  defp get_nutrient_name_from_api(nutrient) do
    # Handle different API response structures
    nutrient["nutrientName"] ||
      nutrient["name"] ||
      (nutrient["nutrient"] && nutrient["nutrient"]["name"])
  end

  # Convert USDA technical names to human-readable
  defp humanize_nutrient_name(name) when is_binary(name) do
    name
    |> String.replace("_", " ")
    |> String.trim()
    |> apply_fatty_acid_mappings()
    |> apply_vitamin_mappings()
    |> apply_mineral_mappings()
    |> capitalize_properly()
  end

  defp humanize_nutrient_name(_), do: "Unknown Nutrient"

  # Special mappings for fatty acids
  defp apply_fatty_acid_mappings(name) do
    name_lower = String.downcase(name)

    cond do
      # Omega-3 family
      String.contains?(name_lower, "dha") or String.contains?(name_lower, "22:6") ->
        "Docosahexaenoic Acid (DHA, Omega-3)"

      String.contains?(name_lower, "epa") or String.contains?(name_lower, "20:5") ->
        "Eicosapentaenoic Acid (EPA, Omega-3)"

      (String.contains?(name_lower, "18:3") and String.contains?(name_lower, "n-3")) or
          String.contains?(name_lower, "ala") ->
        "Alpha-Linolenic Acid (ALA, Omega-3)"

      String.contains?(name_lower, "18:3") ->
        "Alpha-Linolenic Acid (Omega-3)"

      # Omega-6 family
      (String.contains?(name_lower, "18:2") and String.contains?(name_lower, "n-6")) or
          String.contains?(name_lower, "linoleic") ->
        "Linoleic Acid (Omega-6)"

      String.contains?(name_lower, "20:4") or String.contains?(name_lower, "arachidonic") ->
        "Arachidonic Acid (AA, Omega-6)"

      # Omega-9 family
      String.contains?(name_lower, "18:1") or String.contains?(name_lower, "oleic") ->
        "Oleic Acid (Omega-9)"

      # General categories
      String.contains?(name_lower, "pufa") or
          (String.contains?(name_lower, "polyunsaturated") and
             not String.contains?(name_lower, "18:")) ->
        "Polyunsaturated Fat"

      String.contains?(name_lower, "mufa") or String.contains?(name_lower, "monounsaturated") ->
        "Monounsaturated Fat"

      String.contains?(name_lower, "sfa") or String.contains?(name_lower, "saturated") ->
        "Saturated Fat"

      String.contains?(name_lower, "trans") ->
        "Trans Fat"

      # Fallback for any 18:2 not caught above
      String.contains?(name_lower, "18:2") ->
        "Linoleic Acid"

      true ->
        name
    end
  end

  defp apply_vitamin_mappings(name) do
    cond do
      String.contains?(name, "Vitamin A") and String.contains?(name, "RAE") ->
        "Vitamin A (Retinol Activity Equivalents)"

      String.contains?(name, "Vitamin D") ->
        "Vitamin D"

      String.contains?(name, "Vitamin B-12") ->
        "Vitamin B12"

      String.contains?(name, "Vitamin B-6") ->
        "Vitamin B6"

      true ->
        name
    end
  end

  defp apply_mineral_mappings(name) do
    cond do
      name == "Ca" -> "Calcium"
      name == "Fe" -> "Iron"
      name == "K" -> "Potassium"
      name == "Na" -> "Sodium"
      name == "Mg" -> "Magnesium"
      name == "Zn" -> "Zinc"
      true -> name
    end
  end

  defp capitalize_properly(name) do
    name
    |> String.split(" ")
    |> Enum.map(fn word ->
      case String.downcase(word) do
        "and" -> "and"
        "of" -> "of"
        "in" -> "in"
        "to" -> "to"
        "for" -> "for"
        "with" -> "with"
        "by" -> "by"
        other -> String.capitalize(other)
      end
    end)
    |> Enum.join(" ")
  end

  # Fallback mapping for common nutrients (used if API fails)
  defp get_fallback_mappings do
    %{
      "1008" => "Energy (kcal)",
      "1004" => "Total Fat",
      "1003" => "Protein",
      "1005" => "Carbohydrates",
      "1087" => "Calcium",
      "1089" => "Iron",
      "1092" => "Potassium",
      "1093" => "Sodium",
      "1162" => "Vitamin C",
      "1104" => "Vitamin B12",
      "1114" => "Vitamin D",
      "1108" => "Vitamin A",
      "1110" => "Vitamin E",
      "1258" => "Saturated Fat",
      "1259" => "Monounsaturated Fat",
      "1260" => "Polyunsaturated Fat",
      "1253" => "Cholesterol",
      "1079" => "Fiber",
      "2000" => "Sugars"
    }
  end
end
