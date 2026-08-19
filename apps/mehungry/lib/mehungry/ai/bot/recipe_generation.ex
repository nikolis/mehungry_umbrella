defmodule Mehungry.AI.Bot.RecipeGeneration do
  @moduledoc """
  Shared recipe-generation helpers for the two bot workers
  (`DailyRecipeGenerationWorker` and `RecipeOrderWorker`).

  Centralizes the pieces both workers need so they can't drift:

    * **Meal prompts** — the dish-class hint injected so the agent always has a
      concrete thing to anchor on (`meal_prompt/1`).
    * **Condition guidance** — encouraged/discouraged ingredients resolved live
      from a setup's (or config's) linked health condition
      (`condition_guidance/1`), and the prompt injection that carries them
      (`append_guidance/3`). The condition's benefit is carried concretely by
      ingredient names — the disease is never named to the model.
    * **Avoid seeds** — the setup's `"avoid"` seed ingredient ids/names
      (`setup_avoid_ids/1`, `setup_avoid_names/1`).
    * **The avoid-guard** — run `RecipeAgent`, hard-rejecting and retrying any
      recipe that includes an avoided/discouraged ingredient id (`generate/4`,
      `generate_avoiding/4`).
  """

  require Logger

  alias Mehungry.Health
  alias Mehungry.AI.Agents.RecipeAgent

  # Cap the discouraged names injected into a prompt so it stays bounded; the full
  # avoided set is still enforced by the post-generation id guard regardless.
  @ingredient_name_limit 50

  # Encouraged ingredients have NO post-hoc enforcement — the prompt is the only
  # steering. "Build the recipe around these" is only coherent for a handful, and
  # the source list is alphabetical, so injecting the first N would always surface
  # the same head. Instead sample a small random subset each run: focused per
  # recipe, and varied across a batch.
  @encouraged_prompt_limit 12

  # Default number of agent runs before giving up on a clean recipe.
  @default_attempts 3

  # Meal-type hints so the agent always has a concrete dish class to anchor on —
  # a too-vague prompt makes it flail without ever submitting a recipe.
  @meal_prompts %{
    "breakfast" =>
      "light and nourishing breakfast recipe — suitable for the morning, could be egg-based, yogurt-based, or grain-based",
    "morning_snack" => "healthy mid-morning snack recipe — light, easy to prepare, energizing",
    "lunch" =>
      "satisfying main lunch recipe — a full meal with vegetables, protein, and grains or legumes",
    "afternoon_snack" =>
      "light afternoon snack recipe — sweet or savory, easy to prepare quickly",
    "dinner" => "hearty dinner recipe — a warming complete evening meal with rich flavors"
  }

  @doc "Dish-class hint for a meal type; a generic \"recipe\" fallback for unknown types."
  def meal_prompt(meal_type), do: Map.get(@meal_prompts, meal_type, "recipe")

  @doc """
  Live encouraged/discouraged ingredients for the linked condition of anything
  carrying a `condition_id` (a `RecipeSetup` or `AiBotConfig`), or empty lists
  when there is no condition. Returns `%{encouraged: [ingredient], discouraged: [ingredient]}`.
  """
  def condition_guidance(%{condition_id: id}) when not is_nil(id),
    do: Health.ingredient_guidance_for_condition(id)

  def condition_guidance(_), do: %{encouraged: [], discouraged: []}

  @doc """
  Bounded, comma-joined ingredient names for prompt injection ("" when none).
  Used for the **discouraged** list (a soft hint over the hard id-guard), so a
  simple head-of-list cap is fine.
  """
  def ingredient_names(ingredients) do
    ingredients
    |> Enum.map(& &1.name)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.take(@ingredient_name_limit)
    |> Enum.join(", ")
  end

  @doc """
  A small, **randomly sampled** set of encouraged ingredient names for prompt
  injection ("" when none). Sampling (rather than the alphabetical head) keeps
  the "build around these" steering focused per recipe and varied across a batch.
  """
  def encouraged_names(ingredients) do
    ingredients
    |> Enum.map(& &1.name)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.shuffle()
    |> Enum.take(@encouraged_prompt_limit)
    |> Enum.join(", ")
  end

  @doc """
  Append encouraged/discouraged ingredient guidance to a base description. Both
  args are pre-joined name strings (use `ingredient_names/1`); "" appends nothing.
  """
  def append_guidance(base, encouraged_names, discouraged_names) do
    base
    |> maybe_append(
      encouraged_names,
      " Build the recipe around these encouraged ingredients wherever they fit naturally: "
    )
    |> maybe_append(
      discouraged_names,
      " The recipe MUST NOT contain any of these ingredients under any circumstance: "
    )
  end

  defp maybe_append(base, "", _prefix), do: base
  defp maybe_append(base, names, prefix), do: base <> prefix <> names <> "."

  @doc "Ingredient ids the setup marks as `\"avoid\"` seed ingredients, as a MapSet."
  def setup_avoid_ids(nil), do: MapSet.new()

  def setup_avoid_ids(setup) do
    (setup.seed_ingredients || [])
    |> Enum.filter(&(&1.role == "avoid"))
    |> Enum.map(& &1.ingredient_id)
    |> MapSet.new()
  end

  @doc """
  `id => name` map for the setup's `"avoid"` seed ingredients (names from the
  preloaded association), used only to make the guard's log lines readable.
  """
  def setup_avoid_names(nil), do: %{}

  def setup_avoid_names(setup) do
    (setup.seed_ingredients || [])
    |> Enum.filter(&(&1.role == "avoid"))
    |> Map.new(fn si -> {si.ingredient_id, si.ingredient && si.ingredient.name} end)
  end

  @doc """
  Generate a recipe, applying the avoid-guard only when there is something to
  avoid. Returns `{:ok, attrs}` or `{:error, reason}`.

  Opts:
    * `:attempts`    — max agent runs before giving up (default #{@default_attempts})
    * `:avoid_names` — `id => name` map for readable log lines
    * `:label`       — short context label used in log/error messages (default `"recipe"`)
  """
  def generate(description, avoid_ids, brief_opts, opts \\ []) do
    if MapSet.size(avoid_ids) > 0 do
      generate_avoiding(description, avoid_ids, brief_opts, opts)
    else
      case RecipeAgent.run(description, brief_opts) do
        {:ok, attrs, _} -> {:ok, attrs}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Run `RecipeAgent`, hard-rejecting and retrying any recipe that contains an
  avoided ingredient id. `avoid_ids` is a MapSet. Same opts as `generate/4`.
  """
  def generate_avoiding(description, avoid_ids, brief_opts, opts \\ []) do
    attempts = Keyword.get(opts, :attempts, @default_attempts)
    names = Keyword.get(opts, :avoid_names, %{})
    label = Keyword.get(opts, :label, "recipe")
    do_generate_avoiding(description, avoid_ids, brief_opts, names, label, attempts)
  end

  defp do_generate_avoiding(_description, avoid_ids, _brief_opts, _names, label, 0) do
    Logger.warning(
      "[RecipeGeneration] #{label}: exhausted avoid-guard attempts; every candidate contained " <>
        "one of the #{MapSet.size(avoid_ids)} avoided ingredient(s). Giving up on this recipe."
    )

    {:error, "#{label}: could not generate a recipe free of avoided ingredients"}
  end

  defp do_generate_avoiding(description, avoid_ids, brief_opts, names, label, attempts_left) do
    case RecipeAgent.run(description, brief_opts) do
      {:ok, attrs, _} ->
        case offending_ingredient_ids(attrs, avoid_ids) do
          [] ->
            {:ok, attrs}

          offending ->
            Logger.warning(
              "[RecipeGeneration] #{label}: recipe contained avoided ingredients " <>
                "#{describe_ingredients(offending, names)}, retrying (#{attempts_left - 1} left)"
            )

            do_generate_avoiding(
              description,
              avoid_ids,
              brief_opts,
              names,
              label,
              attempts_left - 1
            )
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Deduped recipe ingredient ids that fall within `avoid_ids`."
  def offending_ingredient_ids(attrs, avoid_ids) do
    (attrs["recipe_ingredients"] || [])
    |> Enum.map(fn ri -> ri["ingredient_id"] || ri[:ingredient_id] end)
    |> Enum.filter(&MapSet.member?(avoid_ids, &1))
    |> Enum.uniq()
  end

  defp describe_ingredients(ids, names) do
    ids
    |> Enum.map(fn id ->
      case Map.get(names, id) do
        name when is_binary(name) -> "#{name} (##{id})"
        _ -> "##{id}"
      end
    end)
    |> Enum.join(", ")
  end
end
