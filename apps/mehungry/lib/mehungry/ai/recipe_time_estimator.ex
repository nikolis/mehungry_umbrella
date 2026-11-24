defmodule Mehungry.AI.RecipeTimeEstimator do
  @moduledoc """
  Single-shot AI estimate of recipes' **preparation** and **cooking** minutes, for
  recipes saved without a time (`Mehungry.Food.RecipeTimeEstimation`). One JSON
  prompt via `AI.Client.request/1`, fence-strip + `Jason.decode`; only ids that were
  in the batch survive. Same shape as `Mehungry.AI.RecipeMealRoleClassifier`.

  Behind the `:recipe_time_estimator` config key so tests can stub it.
  """

  @callback estimate(recipes :: [map()]) ::
              {:ok, %{integer() => %{prep: integer() | nil, cook: integer() | nil}}}
              | {:error, term()}

  @behaviour __MODULE__

  require Logger

  @default_model "claude-haiku-4-5-20251001"

  @doc "The configured estimator module (the real one unless a test swaps it)."
  def impl, do: Application.get_env(:mehungry, :recipe_time_estimator, __MODULE__)

  @impl true
  def estimate([]), do: {:ok, %{}}

  def estimate(recipes) when is_list(recipes) do
    ids = MapSet.new(recipes, & &1.id)
    user = "Estimate the times for these recipes. JSON input:\n" <> Jason.encode!(recipes)

    case call_api(system_prompt(), user) do
      {:ok, text} -> parse(text, ids)
      error -> error
    end
  end

  @doc false
  def system_prompt do
    """
    You are an experienced home cook estimating how long recipes take, for a
    meal-planning app that uses the times to pick quick breakfasts (≤ 15 min) and
    weeknight dinners (≤ 40 min).

    For each recipe estimate, in whole minutes, for the stated servings:
    - "prep": hands-on preparation (washing, chopping, mixing, assembling).
    - "cook": time on the heat or in the oven, including baking, simmering and
      resting that the cook must wait for. 0 for no-cook dishes.

    Judge from the ingredients and steps, not only the title (titles may be Greek,
    Turkish, Italian or another language). Be realistic for a home cook, not a
    professional kitchen: an omelette is about 5 prep + 5 cook; a moussaka about
    45 prep + 60 cook; a salad about 10 prep + 0 cook. Exclude overnight soaking or
    marinating from both numbers. If a recipe gives too little to judge, omit it.

    Return ONLY a valid JSON object mapping each recipe id (as a string) to
    {"prep": minutes, "cook": minutes}. No markdown, no explanation. Example:
    {"12": {"prep": 5, "cook": 5}, "15": {"prep": 45, "cook": 60}}
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
        {:ok, map |> Enum.flat_map(&to_entry(&1, ids)) |> Map.new()}

      _ ->
        Logger.warning("RecipeTimeEstimator: failed to parse response: #{inspect(text)}")
        {:error, "Could not parse recipe time estimate response"}
    end
  end

  defp to_entry({id_string, %{} = times}, ids) do
    with {id, ""} <- Integer.parse(to_string(id_string)),
         true <- MapSet.member?(ids, id) do
      [{id, %{prep: minutes(times["prep"]), cook: minutes(times["cook"])}}]
    else
      _ -> []
    end
  end

  defp to_entry(_, _), do: []

  defp minutes(n) when is_number(n) and n >= 0, do: round(n)
  defp minutes(_), do: nil

  defp call_api(system, user) do
    case Mehungry.AI.Client.request(%{
           model: Application.get_env(:mehungry, :recipe_time_estimator_model, @default_model),
           system: system,
           messages: [%{role: "user", content: user}],
           max_tokens: 2048
         }) do
      {:ok, response} -> {:ok, Mehungry.AI.Client.text_from(response)}
      error -> error
    end
  end
end
