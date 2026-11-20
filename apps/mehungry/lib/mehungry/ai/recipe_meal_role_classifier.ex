defmodule Mehungry.AI.RecipeMealRoleClassifier do
  @moduledoc """
  Single-shot AI classification of recipes into **meal roles**
  (`Mehungry.Food.MealRoles`) — multi-label, with a per-role confidence.

  Mirrors `Mehungry.AI.TaxonomyClassifier`: one JSON prompt via
  `AI.Client.request/1`, fence-strip + `Jason.decode`, and only ids that were in
  the batch / roles that are in the vocabulary survive. Recipes arrive with
  ingredients + per-serving kcal/protein so the model judges what the dish
  *is* (a dip vs a main), not just what its title sounds like.
  """

  @behaviour Mehungry.AI.RecipeMealRoleClassifierBehaviour

  require Logger

  alias Mehungry.Food.MealRoles

  @default_model "claude-haiku-4-5-20251001"

  @impl true
  def classify([]), do: {:ok, %{}}

  def classify(recipes) when is_list(recipes) do
    ids = MapSet.new(recipes, & &1.id)

    user =
      "Classify these recipes. JSON input:\n" <>
        Jason.encode!(Enum.map(recipes, &Map.take(&1, prompt_keys())))

    case call_api(system_prompt(), user) do
      {:ok, text} -> parse(text, ids)
      error -> error
    end
  end

  defp prompt_keys,
    do: [
      :id,
      :title,
      :description,
      :cuisine,
      :servings,
      :ingredients,
      :kcal_per_serving,
      :protein_g_per_serving,
      :total_time_min
    ]

  @doc false
  def system_prompt do
    roles =
      Enum.map_join(MealRoles.all(), "\n", fn role ->
        "- #{role}: #{MealRoles.description(role)}"
      end)

    """
    You are a culinary expert classifying recipes for a meal-planning app. For each
    recipe decide which MEAL ROLES it can play in a real person's day. A recipe can
    have SEVERAL roles.

    Roles:
    #{roles}

    How to decide:
    - Judge what the dish actually is from its ingredients, portion size
      (kcal/protein per serving) and description — not only its title. Titles may be
      in Greek, Turkish, Italian or other languages; use your knowledge of the dish.
    - "main" means a person would eat it as their whole lunch or dinner. A dip, a
      spread, a meze, or a light vegetable plate is NOT a main, even when it is
      tasty or big — give it "meze" and/or "side" instead.
    - Low protein and low kcal per serving (e.g. under ~250 kcal) usually means it
      is not a main.
    - Only give "breakfast" to dishes people commonly eat for breakfast.
    - "dinner" is for a complete meal that suits the evening but is too light to
      be a midday main (an omelette, a light fish plate, a hearty salad bowl). A
      dish that works at both lunch and dinner is just "main" — do not add
      "dinner" to every main. A meze, dip or side is not a "dinner".
    - "pre_workout" and "post_workout" are extra tags, given on top of the dish's
      normal roles (snack, breakfast, main, drink…). "pre_workout": easy to digest,
      carbohydrate-led, low fat and fibre. "post_workout": clearly protein-rich
      (roughly 20 g+ protein per serving) with some carbohydrate. Most recipes get
      neither.
    - "component" is for things never eaten on their own (sauces, dressings,
      doughs, stocks, spice mixes). Do not combine it with eating roles unless
      the item is genuinely both.
    - Every recipe gets at least one role.

    Examples:
    - Spanakopita (spinach-feta pie) → main 0.7, side 0.8, meze 0.85, snack 0.7
    - Patlıcan Salatası (smoky eggplant salad/dip) → meze 0.95, side 0.8
    - Horiatiki (Greek salad) → salad 0.95, side 0.85
    - Fasolada (bean soup) → soup 0.95, main 0.85
    - Moussaka → main 0.97
    - Greek yogurt with honey and walnuts → breakfast 0.85, snack 0.85, dessert 0.7
    - Tzatziki → meze 0.95, side 0.6, component 0.4
    - Béchamel sauce → component 0.97
    - Vegetable omelette with a green salad → dinner 0.85, breakfast 0.6
    - Banana oat energy bites → snack 0.9, pre_workout 0.85
    - Chicken and rice bowl → main 0.95, post_workout 0.85

    Confidence is 0.0–1.0: how sure you are the role applies.

    Return ONLY a valid JSON object mapping each recipe id (as a string) to a list
    of {"role", "confidence"} objects. No markdown, no explanation. Example:
    {"12": [{"role": "meze", "confidence": 0.93}, {"role": "side", "confidence": 0.8}],
     "15": [{"role": "main", "confidence": 0.96}]}
    """
  end

  @doc false
  def parse(text, ids) do
    cleaned =
      text
      |> String.trim()
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, map} when is_map(map) ->
        {:ok,
         map
         |> Enum.flat_map(&to_entry(&1, ids))
         |> Map.new()}

      _ ->
        Logger.warning("RecipeMealRoleClassifier: failed to parse response: #{inspect(text)}")
        {:error, "Could not parse meal-role classification response"}
    end
  end

  defp to_entry({id_string, roles}, ids) when is_list(roles) do
    with {id, ""} <- Integer.parse(to_string(id_string)),
         true <- MapSet.member?(ids, id) do
      assignments =
        roles
        |> Enum.flat_map(&to_assignment/1)
        |> Enum.uniq_by(& &1.role)

      [{id, assignments}]
    else
      _ -> []
    end
  end

  defp to_entry(_, _), do: []

  defp to_assignment(%{"role" => role} = a) when is_binary(role) do
    role = role |> String.trim() |> String.downcase() |> String.replace(~r/[\s-]+/, "_")
    if MealRoles.valid?(role), do: [%{role: role, confidence: confidence(a)}], else: []
  end

  defp to_assignment(_), do: []

  defp confidence(%{"confidence" => c}) when is_number(c),
    do: c |> max(0.0) |> min(1.0) |> Kernel.*(1.0)

  defp confidence(_), do: nil

  defp call_api(system, user) do
    case Mehungry.AI.Client.request(%{
           model: model(),
           system: system,
           messages: [%{role: "user", content: user}],
           max_tokens: 4096
         }) do
      {:ok, response} -> {:ok, Mehungry.AI.Client.text_from(response)}
      error -> error
    end
  end

  defp model, do: Application.get_env(:mehungry, :meal_role_classifier_model, @default_model)
end
