defmodule Mehungry.AI.Agents.MealPlanCore do
  @moduledoc """
  The machinery both meal-plan agents share, so their guarantees cannot drift:

    * `UserMealPlanAgent` — a person planning their own week (calendar, blueprint
      plans, the mobile "Plan with AI" job).
    * `NutritionistMealPlanAgent` — a nutritionist drafting a client's week.

  The two agents differ only in **how they learn about the person** (prompt +
  context tools). Everything that decides what may end up in a plan lives here:

    * **Guards** (`guards/1`) — the deterministic diet / avoid / hashtag filters
      the search tools apply. A filtered-out id never reaches the model.
    * **Search tools** (`search_recipes_tool/2`, `search_ingredients_tool/2`) —
      catalog search with the guards applied and per-serving calories attached.
    * **Provenance + validation** (`submit_plan_tool/2`, `validate_plan/7`) — a
      plan may only use ids the search tools returned this run.
    * **Meal roles** (`Mehungry.Food.MealRoles`) — recipe search can be scoped to
      a slot (`slot` input → only recipes whose roles fit it), every result shows
      its roles, and `submit_plan` rejects a recipe whose roles don't fit its
      slot (a meze as Dinner). Unclassified recipes always pass.
    * **Normalization** (`normalize_entries/2`) — the model's dated entries become
      calendar-independent entries (`day_index`, `meal_type`, resolved unit FKs).

  Agents are pure generators: neither persists. The caller writes the returned
  entries to a calendar (`MealPlanGenerator.persist_entries_to_calendar/5`) or to
  an independent blueprint plan (`MealBlueprints.store_plan_meals/2`).
  """

  require Logger

  alias Mehungry.{Food, Repo, Search.RecipeVectorSearch}
  alias Mehungry.Food.{Categories, IngredientPortion, MealRoleAssignments, MealRoles, Recipe}
  alias Mehungry.History.MealType

  import Ecto.Query, only: [from: 2]

  @model "claude-haiku-4-5-20251001"
  @history_days 21

  # The 5 calendar slots, in the label form the model emits and
  # MealType.from_slot/1 maps back to canonical values.
  @slots ["Breakfast", "Morning Snack", "Lunch", "Afternoon Snack", "Dinner"]

  @diet_modes [:vegan, :vegetarian, :pescatarian]

  def model, do: @model
  def history_days, do: @history_days
  def slots, do: @slots

  # ── guards ────────────────────────────────────────────────────────────────────

  @doc """
  Builds the guard set the search tools enforce. Options:

    * `:catalog` — whose recipes `search_recipes` draws from: `{:user, id}` (that
      user's own recipes) or `:public` (every non-private recipe).
    * `:ingredient_owner_id` — the user whose custom ingredients are searchable
      alongside the shared ones.
    * `:avoid_terms` — downcased substrings; a recipe title / ingredient name
      containing one is dropped.
    * `:avoid_ingredient_ids` — exact ingredient ids to drop, together with any
      recipe that contains one (ingredient-composition aware).
    * `:diet_mode` — `:vegan | :vegetarian | :pescatarian | nil`.
    * `:required_tags` — recipe hashtags every candidate recipe must carry.
  """
  def guards(opts) do
    avoid_terms = opts |> Keyword.get(:avoid_terms, []) |> normalize_terms()

    %{
      catalog: Keyword.fetch!(opts, :catalog),
      ingredient_owner_id: Keyword.get(opts, :ingredient_owner_id),
      avoid_terms: avoid_terms,
      avoid_word_terms:
        (opts |> Keyword.get(:avoid_word_terms, []) |> free_text_terms()) -- avoid_terms,
      avoid_ingredient_ids: opts |> Keyword.get(:avoid_ingredient_ids, []) |> MapSet.new(),
      diet_mode: Keyword.get(opts, :diet_mode),
      required_tags: opts |> Keyword.get(:required_tags, []) |> normalize_terms()
    }
  end

  @doc """
  The catalog a professional's drafts draw from: their own recipes, or — when
  they have authored none yet — the public catalog.
  """
  def catalog_for_professional(professional_id) do
    own? = Repo.exists?(from r in Recipe, where: r.user_id == ^professional_id)
    if own?, do: {:user, professional_id}, else: :public
  end

  @doc "Maps a profile/client `diet` string to a planner diet mode (pescatarian included)."
  def diet_mode_for_diet("vegan"), do: :vegan
  def diet_mode_for_diet("vegetarian"), do: :vegetarian
  def diet_mode_for_diet("pescatarian"), do: :pescatarian
  def diet_mode_for_diet(_), do: nil

  @doc false
  # Downcased, trimmed, non-blank, deduped terms (nil-safe).
  def normalize_terms(terms) when is_list(terms) do
    terms
    |> Enum.map(&(&1 |> to_string() |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  def normalize_terms(_), do: []

  # What people type into a free-text "allergies / intolerances / aversions" box
  # when they mean "nothing".
  @non_answers ~w(no none nil nothing n/a na nope όχι οχι κανένα κανενα καμία καμια τίποτα τιποτα)

  @doc false
  # Avoid terms taken from **free text** (a client intake), made safe to enforce:
  # normalized, with non-answers and fragments under three characters dropped —
  # a stray "-" or "no" must not empty the catalog. These are matched at word
  # starts (`reject_avoided_words/3`), not as substrings.
  def free_text_terms(terms) do
    terms
    |> normalize_terms()
    |> Enum.reject(&(String.length(&1) < 3 or &1 in @non_answers))
  end

  @doc "Every avoid term the guards enforce (curated + free-text), for display."
  def enforced_avoid_terms(guards),
    do: guards.avoid_terms ++ Map.get(guards, :avoid_word_terms, [])

  @doc false
  # Downcased, non-blank avoid terms from anything carrying `avoid_foods`
  # (a blueprint, a profile — nil-safe).
  def avoid_terms(%{avoid_foods: foods}) when is_list(foods), do: normalize_terms(foods)
  def avoid_terms(_), do: []

  @doc false
  # Downcased, non-blank required recipe hashtags from a blueprint's
  # `required_hashtags` (nil-safe), e.g. ["raw"].
  def required_recipe_tags(%{required_hashtags: tags}) when is_list(tags),
    do: normalize_terms(tags)

  def required_recipe_tags(_), do: []

  @doc false
  # Infers `:vegan | :vegetarian | :pescatarian | nil` from a blueprint's
  # `avoid_foods`, using the same keywords the DietPatterns encode: the three
  # flesh foods plus dairy + eggs ⇒ vegan; the three flesh foods alone ⇒
  # vegetarian; meat + poultry but *not* fish ⇒ pescatarian.
  def diet_mode_from_blueprint(%{avoid_foods: foods}) when is_list(foods) do
    f = MapSet.new(Enum.map(foods, &String.downcase(String.trim(&1))))
    flesh = MapSet.new(["meat", "poultry", "fish"])

    cond do
      MapSet.subset?(flesh, f) and MapSet.member?(f, "dairy") and MapSet.member?(f, "eggs") ->
        :vegan

      MapSet.subset?(flesh, f) ->
        :vegetarian

      MapSet.member?(f, "meat") and MapSet.member?(f, "poultry") ->
        :pescatarian

      true ->
        nil
    end
  end

  def diet_mode_from_blueprint(_), do: nil

  @doc false
  # Drop any result whose name contains an avoid term (case-insensitive
  # substring) — a filtered-out id never enters the provenance set, so the model
  # cannot submit it even if it guesses the id.
  def reject_avoided(results, [], _name_fun), do: results

  def reject_avoided(results, terms, name_fun) do
    Enum.reject(results, fn result ->
      name = result |> name_fun.() |> to_string() |> String.downcase()
      Enum.any?(terms, &String.contains?(name, &1))
    end)
  end

  @doc false
  # The avoid terms (case-insensitive substring) that appear in any of `names` —
  # the detection counterpart of `reject_avoided/3`, used to flag (not drop) a
  # logged meal whose food names contain a term.
  @doc false
  # Like `reject_avoided/3`, but a term must begin a word: "oil" drops "Olive
  # oil" and "Oils", not "Boiled eggs"; "ham" drops "Ham sandwich", not
  # "Graham crackers". Used for free-text terms, which are too loose for
  # substring matching.
  def reject_avoided_words(results, [], _name_fun), do: results

  def reject_avoided_words(results, terms, name_fun) do
    patterns = Enum.map(terms, &Regex.compile!("(?<![\\p{L}])" <> Regex.escape(&1), "u"))

    Enum.reject(results, fn result ->
      name = result |> name_fun.() |> to_string() |> String.downcase()
      Enum.any?(patterns, &Regex.match?(&1, name))
    end)
  end

  def matched_avoid_terms(_names, []), do: []

  def matched_avoid_terms(names, terms) do
    downcased = Enum.map(names, &(&1 |> to_string() |> String.downcase()))

    Enum.filter(terms, fn term ->
      Enum.any?(downcased, &String.contains?(&1, term))
    end)
  end

  @doc false
  # Keep only recipes carrying every required hashtag (e.g. #raw).
  def reject_without_required_tags(recipes, []), do: recipes

  def reject_without_required_tags(recipes, tags) do
    keep = Food.recipe_ids_with_all_hashtags(Enum.map(recipes, & &1.recipe_id), tags)
    Enum.filter(recipes, &MapSet.member?(keep, &1.recipe_id))
  end

  @doc false
  # Keep only recipes carrying the diet hashtag (`#vegan`/`#vegetarian`, the same
  # tag browse/home filter on). Pescatarian has no positive hashtag — keep
  # recipes with no meat/poultry ingredient (fish allowed). No-op without a mode.
  def reject_off_diet_recipes(recipes, mode) when mode in [:vegan, :vegetarian] do
    keep = Food.recipe_ids_with_diet_tag(Enum.map(recipes, & &1.recipe_id), mode)
    Enum.filter(recipes, &MapSet.member?(keep, &1.recipe_id))
  end

  def reject_off_diet_recipes(recipes, :pescatarian) do
    keep = Food.pescatarian_recipe_ids(Enum.map(recipes, & &1.recipe_id))
    Enum.filter(recipes, &MapSet.member?(keep, &1.recipe_id))
  end

  def reject_off_diet_recipes(recipes, _mode), do: recipes

  @doc false
  # Drop recipes that contain any of the avoided ingredient ids.
  def reject_recipes_containing(recipes, avoid_ingredient_ids) do
    if MapSet.size(avoid_ingredient_ids) == 0 do
      recipes
    else
      hit =
        Food.recipe_ids_containing_ingredients(
          Enum.map(recipes, & &1.recipe_id),
          MapSet.to_list(avoid_ingredient_ids)
        )

      Enum.reject(recipes, &MapSet.member?(hit, &1.recipe_id))
    end
  end

  @doc false
  # Drop ingredients in a diet-excluded category (Meats/Fish/Dairy/… per
  # `Categories.diet_category_ids/1`); no-op when there's no diet mode.
  def reject_off_diet_ingredients(ingredients, mode) when mode in @diet_modes do
    excluded =
      Food.ingredient_ids_in_categories(
        Enum.map(ingredients, & &1.id),
        Categories.diet_category_ids(mode)
      )

    Enum.reject(ingredients, &MapSet.member?(excluded, &1.id))
  end

  def reject_off_diet_ingredients(ingredients, _mode), do: ingredients

  # ── prompt blocks ─────────────────────────────────────────────────────────────

  @doc "The enforcement paragraphs both agents append to their system prompt."
  def guard_blocks(guards) do
    diet_block(guards.diet_mode) <>
      raw_block(guards.required_tags) <> avoid_block(enforced_avoid_terms(guards))
  end

  defp avoid_block([]), do: ""

  defp avoid_block(terms) do
    "\nSTRICT RULE — NEVER include these foods, or any dish containing them: " <>
      Enum.join(terms, ", ") <> ".\n"
  end

  defp diet_block(mode) when mode in @diet_modes do
    "\nDIET: this plan must be #{mode}. The search tools return only " <>
      "#{mode}-compatible recipes and ingredients — build the whole plan from those.\n"
  end

  defp diet_block(_), do: ""

  # A raw/uncooked instruction when the #raw tag is required. The search tools
  # already return only #raw recipes; this steers the model's queries toward
  # no-cook dishes and keeps ingredient snacks raw.
  defp raw_block(tags) do
    if "raw" in tags do
      "\nRAW: this is a raw-food plan — every meal must be uncooked (nothing heated " <>
        "above ~46°C/115°F). The recipe search returns only raw-tagged recipes; search " <>
        "for no-cook dishes (salads, smoothies, overnight oats-style soaks, raw wraps) " <>
        "and choose only raw whole-food ingredients (fresh fruit, raw vegetables, nuts, " <>
        "seeds) for snacks.\n"
    else
      ""
    end
  end

  # ── shared tool definitions ───────────────────────────────────────────────────

  @doc "Tool definition for the recipe search, under the agent's own tool `name`."
  def search_recipes_tool_def(name) do
    %{
      name: name,
      description:
        "Semantically search the available recipe catalog by natural language query. " <>
          "Returns matching recipes with their recipe_id, title, difficulty (1–3), servings, " <>
          "per-serving calories (use these to keep each day near the calorie target), and " <>
          "meal roles (e.g. main, soup, side, meze, salad, breakfast, snack, dessert). " <>
          "Pass `slot` to get only recipes that can fill that slot on their own — e.g. " <>
          "slot 'Dinner' returns mains and meal soups, never a meze or side. " <>
          "Use descriptive phrases like 'light high-protein breakfast', " <>
          "'quick vegetarian lunch', or 'hearty Mediterranean dinner'. " <>
          "Call with different queries to find recipes for each meal slot type.",
      input_schema: %{
        type: "object",
        properties: %{
          query: %{
            type: "string",
            description:
              "Natural language query, e.g. 'light high-protein breakfast', 'quick vegetarian lunch', 'hearty Mediterranean dinner'"
          },
          slot: %{
            type: "string",
            enum: @slots,
            description:
              "The meal slot you are searching for. Only recipes whose meal roles fit that slot are returned."
          }
        },
        required: ["query"]
      }
    }
  end

  @doc "Tool definition for the whole-food ingredient search."
  def search_ingredients_tool_def do
    %{
      name: "search_ingredients",
      description:
        "Search whole-food ingredients (fruit, nuts, cheese, yogurt, vegetables) to use " <>
          "as standalone snack items or light sides. Returns each ingredient's ingredient_id, " <>
          "name, and a list of unit options — each option has a unit_selection value and a " <>
          "human label (e.g. '1 medium', 'gram'). Use an ingredient's ingredient_id plus one " <>
          "of its unit_selection values and a quantity in a submit_plan entry.",
      input_schema: %{
        type: "object",
        properties: %{
          query: %{
            type: "string",
            description:
              "Ingredient name to search for, e.g. 'apple', 'almonds', 'feta cheese', 'greek yogurt'"
          }
        },
        required: ["query"]
      }
    }
  end

  @doc "Tool definition for `submit_plan`; `rationale_description` is agent-specific."
  def submit_plan_tool_def(rationale_description, rationale_required? \\ false) do
    %{
      name: "submit_plan",
      description:
        "Validate and submit the 7-day meal plan. Pass every entry at once (up to 5 slots " <>
          "× 7 days). Each entry is EITHER a recipe (set recipe_id and cooking_portions) OR an " <>
          "ingredient (set ingredient_id, quantity, and unit_selection). Returns success, or a " <>
          "list of errors to fix before resubmitting.",
      input_schema: %{
        type: "object",
        properties: %{
          entries: %{
            type: "array",
            description: "The meal entries (35 for a full week)",
            items: %{
              type: "object",
              properties: %{
                date: %{type: "string", description: "YYYY-MM-DD"},
                slot: %{type: "string", description: "One of: #{Enum.join(@slots, ", ")}"},
                recipe_id: %{type: "integer", description: "For a recipe entry"},
                cooking_portions: %{type: "integer", description: "Recipe entry: 1–4"},
                ingredient_id: %{type: "integer", description: "For an ingredient entry"},
                unit_selection: %{
                  type: "integer",
                  description: "Ingredient entry: a unit_selection value from search_ingredients"
                },
                quantity: %{
                  type: "number",
                  description: "Ingredient entry: amount in the chosen unit"
                }
              },
              required: ["date", "slot"]
            }
          },
          rationale: %{type: "string", description: rationale_description}
        },
        required: if(rationale_required?, do: ["entries", "rationale"], else: ["entries"])
      }
    }
  end

  # ── shared tool handlers ──────────────────────────────────────────────────────
  #
  # Each takes the run accumulator, which must carry `:guards`, `:offered`,
  # `:offered_ingredients`, `:start_date` and `:submitted`, and returns
  # `{result, new_acc}` like any `AI.Agent` handler.

  @doc """
  Recipe search with the guards applied. Every returned id joins the `offered`
  provenance set; a filtered-out id never does.
  """
  def search_recipes_tool(query, %{guards: guards, offered: offered} = acc, slot \\ nil) do
    recipes = search_recipes(query, guards, slot)

    acc = %{
      acc
      | offered: Enum.reduce(recipes, offered, &MapSet.put(&2, &1.recipe_id))
    }

    acc = remember_recipe_meta(acc, recipes)

    result =
      if recipes == [] do
        %{found: false, message: no_recipes_message(query, slot)}
      else
        %{found: true, count: length(recipes), recipes: recipes}
      end

    {result, acc}
  end

  defp no_recipes_message(query, slot) when slot in @slots do
    "No recipes found for '#{query}' that can fill #{slot}. Try a different query " <>
      "(searching with the slot only returns dishes that fit it)."
  end

  defp no_recipes_message(query, _slot),
    do: "No recipes found for '#{query}'. Try a different query."

  # Title + roles of every offered recipe, so submit_plan can check slot fit
  # without another query.
  defp remember_recipe_meta(acc, recipes) do
    meta = Map.new(recipes, &{&1.recipe_id, %{title: &1.title, roles: &1.roles}})
    Map.update(acc, :recipe_meta, meta, &Map.merge(&1, meta))
  end

  @doc false
  def search_recipes(query, guards, slot \\ nil) do
    roles = MealRoles.slot_roles(slot)

    recipes =
      query
      |> RecipeVectorSearch.search(catalog_opts(guards.catalog) ++ [limit: 20, meal_roles: roles])
      |> Enum.map(fn r ->
        %{
          recipe_id: r.id,
          title: r.title,
          difficulty: r.difficulty || 1,
          servings: r.servings || 2,
          calories: per_serving_calories(r)
        }
      end)
      |> reject_avoided(guards.avoid_terms, & &1.title)
      |> reject_avoided_words(guards.avoid_word_terms, & &1.title)
      |> reject_off_diet_recipes(guards.diet_mode)
      |> reject_without_required_tags(guards.required_tags)
      |> reject_recipes_containing(guards.avoid_ingredient_ids)

    roles_by_id = MealRoleAssignments.roles_for(Enum.map(recipes, & &1.recipe_id))

    recipes
    |> Enum.map(&Map.put(&1, :roles, Map.get(roles_by_id, &1.recipe_id, [])))
    # `component` (sauces, doughs, stocks) is never a meal on its own.
    |> Enum.reject(&(&1.roles == ["component"]))
  end

  defp catalog_opts({:user, user_id}), do: [user_id: user_id]
  defp catalog_opts(:public), do: [public_only: true]

  @doc "Ingredient search with the guards applied; feeds `offered_ingredients`."
  def search_ingredients_tool(query, %{guards: guards, offered_ingredients: offered} = acc) do
    ingredients = search_ingredients(query, guards)

    acc = %{
      acc
      | offered_ingredients: Enum.reduce(ingredients, offered, &MapSet.put(&2, &1.ingredient_id))
    }

    result =
      if ingredients == [] do
        %{found: false, message: "No ingredients found for '#{query}'. Try a different query."}
      else
        %{found: true, count: length(ingredients), ingredients: ingredients}
      end

    {result, acc}
  end

  @doc false
  def search_ingredients(query, guards) do
    query
    |> Food.IngredientSearch.search([], guards.ingredient_owner_id)
    |> Enum.take(15)
    |> reject_off_diet_ingredients(guards.diet_mode)
    |> Enum.reject(&MapSet.member?(guards.avoid_ingredient_ids, &1.id))
    |> reject_avoided(guards.avoid_terms, & &1.name)
    |> reject_avoided_words(guards.avoid_word_terms, & &1.name)
    |> Enum.map(fn i ->
      %{ingredient_id: i.id, name: i.name, units: ingredient_units(i.id)}
    end)
  end

  @doc """
  Validates a submitted plan against the provenance sets and, when clean, stores
  `%{entries: normalized, rationale: text}` in `acc.submitted`. Nothing is
  persisted here.
  """
  def submit_plan_tool(%{"entries" => entries} = input, acc) when is_list(entries) do
    %{start_date: start_date, offered: offered, offered_ingredients: offered_ing} = acc
    # An agent may plan only part of the week (a nutritionist never plans a
    # client's past days): `first_day` narrows the accepted range.
    first_day = Map.get(acc, :first_day, start_date)

    # Provenance is the guard: every offered id came from a real, guard-filtered
    # search result this run, so the offered sets double as the valid sets.
    errors =
      validate_plan(
        entries,
        offered,
        offered,
        offered_ing,
        offered_ing,
        first_day,
        Date.add(start_date, 6)
      )

    # A recipe must be able to fill its slot on its own (no meze as Dinner).
    errors = errors ++ slot_role_errors(entries, Map.get(acc, :recipe_meta, %{}))

    # Replacing a week deletes what is there, so the plan must be able to stand
    # in for it: all three main meals on every day in range.
    errors =
      if errors == [] and entries != [] and Map.get(acc, :mode) == :replace_week,
        do: missing_main_meals(entries, first_day, Date.add(start_date, 6)),
        else: errors

    cond do
      errors != [] ->
        Logger.warning("MealPlanCore: submit_plan errors: #{inspect(errors)}")
        {%{success: false, errors: errors}, acc}

      entries == [] ->
        {%{success: false, errors: ["The plan has no entries — add meals and resubmit"]}, acc}

      true ->
        normalized = normalize_entries(entries, start_date)
        rationale = Map.get(input, "rationale") || ""

        {%{success: true, count: length(normalized), message: "Plan accepted."},
         %{acc | submitted: %{entries: normalized, rationale: rationale}}}
    end
  end

  @doc false
  # One error per recipe entry whose known meal roles don't fit its slot.
  # Unclassified recipes (no roles) and ingredient entries always pass.
  def slot_role_errors(entries, recipe_meta) do
    Enum.flat_map(entries, fn entry ->
      with id when is_integer(id) <- entry["recipe_id"],
           slot when slot in @slots <- entry["slot"],
           %{roles: roles, title: title} <- Map.get(recipe_meta, id),
           false <- MealRoles.fits_slot?(roles, slot) do
        [slot_role_error(entry["date"], slot, id, title, roles)]
      else
        _ -> []
      end
    end)
  end

  defp slot_role_error(date, slot, id, title, roles) do
    is_a = Enum.map_join(roles, "/", &MealRoles.label/1) |> String.downcase()

    needs =
      case slot do
        "Breakfast" -> "a breakfast dish"
        s when s in ["Lunch", "Dinner"] -> "a main or a meal soup — a complete #{s}"
        _ -> "a snack, dessert or drink — or better, a whole-food ingredient"
      end

    "#{date} #{slot}: \"#{title}\" (recipe_id #{id}) is a #{is_a}, not #{needs}. " <>
      "Replace it — call the search tool with slot: \"#{slot}\" to get dishes that fit."
  end

  @main_slots ["Breakfast", "Lunch", "Dinner"]

  # [] when every day in first_day..last_day has Breakfast, Lunch and Dinner;
  # otherwise one error naming the missing cells (capped, so the model can act).
  defp missing_main_meals(entries, first_day, last_day) do
    planned = MapSet.new(entries, &{&1["date"], &1["slot"]})

    missing =
      for date <- Date.range(first_day, last_day),
          slot <- @main_slots,
          not MapSet.member?(planned, {Date.to_string(date), slot}),
          do: "#{date} #{slot}"

    case missing do
      [] ->
        []

      _ ->
        shown = missing |> Enum.take(12) |> Enum.join(", ")
        more = if length(missing) > 12, do: " (and #{length(missing) - 12} more)", else: ""

        [
          "This plan replaces the whole week, so every day needs Breakfast, Lunch and " <>
            "Dinner. Missing: #{shown}#{more}. Add them and resubmit the full plan."
        ]
    end
  end

  def submit_plan_tool(_input, acc) do
    {%{success: false, errors: ["submit_plan needs an `entries` array"]}, acc}
  end

  # ── recent meals (shared history tool body) ───────────────────────────────────

  @doc """
  The recipe meals `user_id` logged in the #{@history_days} days up to
  `start_date`, as `%{date, slot, recipe_title}` maps.
  """
  def recent_meal_entries(user_id, start_date) do
    lookback_start = Date.add(start_date, -@history_days)
    {:ok, start_dt} = NaiveDateTime.new(lookback_start, ~T[00:00:00])
    {:ok, end_dt} = NaiveDateTime.new(start_date, ~T[23:59:59])

    user_id
    |> Mehungry.History.list_history_user_meals_for_user(start_dt, end_dt)
    |> Enum.flat_map(fn meal ->
      date_str = meal.start_dt |> NaiveDateTime.to_date() |> Date.to_string()

      Enum.map(meal.recipe_user_meals, fn rum ->
        %{
          date: date_str,
          slot: meal.title,
          recipe_title: get_in(rum, [Access.key(:recipe), Access.key(:title)]) || "Unknown"
        }
      end)
    end)
  end

  # ── units + calories ──────────────────────────────────────────────────────────

  # The unit_selection/label options for an ingredient, mirroring the manual meal
  # form's `unit_options/1`: each meaningful portion (positive measurement_unit_id
  # or negative -portion_id) plus grams.
  @doc false
  def ingredient_units(ingredient_id) do
    portion_units =
      ingredient_id
      |> Food.get_measurement_unit_portions_for_ingredient()
      |> Enum.filter(&IngredientPortion.meaningful_label?(IngredientPortion.display_name(&1)))
      |> Enum.map(fn portion ->
        value = if portion.measurement_unit_id, do: portion.measurement_unit_id, else: -portion.id
        %{unit_selection: value, label: IngredientPortion.display_name(portion) || "portion"}
      end)

    portion_units ++ gram_units()
  end

  defp gram_units do
    Food.get_measurement_unit_by_name("gram")
    |> Enum.map(fn mu -> %{unit_selection: mu.id, label: mu.name} end)
  end

  @doc false
  # Per-serving kcal from a recipe's stored aggregate `nutrients` tree, reusing the
  # same `NutrientUtils.macro_summary/1` the calendar + SEO JSON-LD use. nil when
  # there's no usable energy value.
  def per_serving_calories(%{nutrients: nutrients} = recipe)
      when is_map(nutrients) and map_size(nutrients) > 0 do
    case Mehungry.NutrientUtils.macro_summary(nutrients).energy_kcal do
      kcal when is_number(kcal) and kcal > 0 ->
        servings =
          if is_integer(recipe.servings) and recipe.servings > 0, do: recipe.servings, else: 1

        round(kcal / servings)

      _ ->
        nil
    end
  end

  def per_serving_calories(_), do: nil

  # ── plan validation ───────────────────────────────────────────────────────────

  @doc """
  Recipe-only validation (kept for the provenance tests): delegates to the mixed
  validator with empty ingredient sets.
  """
  def validate_plan(entries, offered, valid_ids, start_date, end_date) do
    validate_plan(
      entries,
      offered,
      valid_ids,
      MapSet.new(),
      MapSet.new(),
      start_date,
      end_date
    )
  end

  @doc false
  def validate_plan(
        entries,
        offered_recipes,
        valid_recipes,
        offered_ingredients,
        valid_ingredients,
        start_date,
        end_date
      ) do
    slot_errors = check_duplicate_slots(entries)

    entry_errors =
      Enum.flat_map(entries, fn entry ->
        validate_date(entry, start_date, end_date) ++
          validate_slot(entry) ++
          validate_item(
            entry,
            offered_recipes,
            valid_recipes,
            offered_ingredients,
            valid_ingredients
          )
      end)

    slot_errors ++ entry_errors
  end

  defp check_duplicate_slots(entries) do
    entries
    |> Enum.group_by(fn e -> {e["date"], e["slot"]} end)
    |> Enum.filter(fn {_key, group} -> length(group) > 1 end)
    |> Enum.map(fn {{date, slot}, _} -> "Duplicate slot: #{date} #{slot}" end)
  end

  defp validate_date(entry, start_date, end_date) do
    case Date.from_iso8601(to_string(entry["date"] || "")) do
      {:ok, date} ->
        if Date.compare(date, start_date) in [:gt, :eq] and
             Date.compare(date, end_date) in [:lt, :eq] do
          []
        else
          ["Date #{entry["date"]} is outside the plan range #{start_date} – #{end_date}"]
        end

      _ ->
        ["Invalid date format '#{entry["date"]}' — use YYYY-MM-DD"]
    end
  end

  defp validate_slot(entry) do
    if entry["slot"] in @slots do
      []
    else
      ["Invalid slot '#{entry["slot"]}' — must be one of: #{Enum.join(@slots, ", ")}"]
    end
  end

  # Exactly one of recipe_id / ingredient_id, then per-kind provenance checks.
  defp validate_item(
         entry,
         offered_recipes,
         valid_recipes,
         offered_ingredients,
         valid_ingredients
       ) do
    recipe_id = entry["recipe_id"]
    ingredient_id = entry["ingredient_id"]

    cond do
      is_integer(recipe_id) and is_integer(ingredient_id) ->
        ["Entry has both recipe_id and ingredient_id — set exactly one: #{inspect(entry)}"]

      is_integer(recipe_id) ->
        validate_recipe_id(recipe_id, offered_recipes, valid_recipes)

      is_integer(ingredient_id) ->
        validate_ingredient_entry(entry, ingredient_id, offered_ingredients, valid_ingredients)

      true ->
        ["Entry needs a recipe_id or ingredient_id: #{inspect(entry)}"]
    end
  end

  defp validate_recipe_id(id, offered, valid) do
    cond do
      # Provenance first: an id the model never received from the search tool is
      # the dominant failure mode — reject it and steer back to search.
      not MapSet.member?(offered, id) ->
        [
          "recipe_id #{id} was not in your search results — search the catalog " <>
            "and only use recipe_ids it returns"
        ]

      not MapSet.member?(valid, id) ->
        ["recipe_id #{id} is not in the catalog — search the catalog to find valid IDs"]

      true ->
        []
    end
  end

  defp validate_ingredient_entry(entry, id, offered, valid) do
    id_errors =
      cond do
        not MapSet.member?(offered, id) ->
          [
            "ingredient_id #{id} was not in your search results — call search_ingredients " <>
              "and only use ingredient_ids it returns"
          ]

        not MapSet.member?(valid, id) ->
          ["ingredient_id #{id} is not a valid ingredient — use search_ingredients"]

        true ->
          []
      end

    quantity_errors =
      case entry["quantity"] do
        q when is_number(q) and q > 0 -> []
        _ -> ["ingredient entry for ingredient_id #{id} needs a positive quantity"]
      end

    id_errors ++ quantity_errors
  end

  # ── entry normalization ───────────────────────────────────────────────────────

  @doc """
  Turns the model's raw, calendar-dated entries into clean, calendar-independent
  plan entries: relative `day_index` (1..7), canonical `meal_type`, and either a
  recipe or an ingredient with its unit resolved to real FKs.
  """
  def normalize_entries(entries, start_date) do
    entries
    |> Enum.filter(fn e ->
      is_binary(e["date"]) and e["slot"] in @slots and
        (is_integer(e["recipe_id"]) or is_integer(e["ingredient_id"]))
    end)
    |> Enum.flat_map(fn e ->
      case normalize_entry(e, start_date) do
        {:ok, entry} -> [entry]
        :error -> []
      end
    end)
  end

  @doc false
  def normalize_entry(entry, start_date) do
    with {:ok, date} <- Date.from_iso8601(entry["date"] || "") do
      base = %{
        day_index: Date.diff(date, start_date) + 1,
        meal_type: MealType.from_slot(entry["slot"])
      }

      {:ok, Map.merge(base, item_fields(entry))}
    else
      _ -> :error
    end
  end

  defp item_fields(%{"recipe_id" => recipe_id} = entry) when is_integer(recipe_id) do
    %{
      recipe_id: recipe_id,
      cooking_portions: cooking_portions(entry["cooking_portions"]),
      ingredient_id: nil,
      quantity: nil,
      measurement_unit_id: nil,
      ingredient_portion_id: nil
    }
  end

  defp item_fields(%{"ingredient_id" => ingredient_id} = entry) when is_integer(ingredient_id) do
    {mu_id, portion_id} =
      decode_unit(resolve_unit_selection(ingredient_id, entry["unit_selection"]))

    %{
      recipe_id: nil,
      cooking_portions: nil,
      ingredient_id: ingredient_id,
      quantity: (entry["quantity"] || 1) / 1,
      measurement_unit_id: mu_id,
      ingredient_portion_id: portion_id
    }
  end

  # 1–4 per the tool contract; anything else falls back to 2.
  defp cooking_portions(n) when is_integer(n) and n in 1..4, do: n
  defp cooking_portions(_), do: 2

  # The unit_selection encoding: positive → measurement_unit_id, negative →
  # -ingredient_portion_id (mirrors IngredientUserMeal.apply_unit_selection/1).
  defp decode_unit(sel) when is_integer(sel) and sel >= 0, do: {sel, nil}
  defp decode_unit(sel) when is_integer(sel), do: {nil, -sel}
  defp decode_unit(_), do: {nil, nil}

  # Keep the model's unit_selection only if it's a real unit for this ingredient;
  # otherwise fall back to grams so a bad pick can't create an invalid row.
  defp resolve_unit_selection(ingredient_id, unit_selection) do
    valid =
      ingredient_id
      |> ingredient_units()
      |> MapSet.new(& &1.unit_selection)

    if is_integer(unit_selection) and MapSet.member?(valid, unit_selection) do
      unit_selection
    else
      gram_units() |> List.first() |> then(&(&1 && &1.unit_selection))
    end
  end

  # ── submit retry ──────────────────────────────────────────────────────────────

  @firm_submit_instruction "\n\nIMPORTANT: Do not reply with prose, questions, or a summary. " <>
                             "Use the search tools to find real recipes and ingredients, then " <>
                             "finish by calling submit_plan with the plan — calling submit_plan " <>
                             "is the ONLY way to complete this task. If the preferences are " <>
                             "vague, make reasonable choices instead of asking."

  @doc """
  Runs a meal-plan agent pass and, if it ends without a plan in `acc.submitted`
  (the model answered in prose — a clarifying question, a description, a
  refusal), logs what it said and retries **once** with a firmer instruction
  appended to the user message — the same safety net `RecipeAgent` uses.

  `run_fun` receives the extra instruction (`""` on the first pass) and returns
  the `AI.Agent.run/6` result. Returns that result, or
  `{:error, :no_plan_submitted}` when neither pass submitted. Emits
  `[:mehungry, :ai, :agent, :no_submit_retry]` (tagged `agent`) on a retry.
  """
  def run_until_submitted(agent, run_fun) when is_function(run_fun, 1) do
    case run_fun.("") do
      {:ok, text, %{submitted: nil}} ->
        Logger.warning(
          "MealPlanCore[#{agent}]: run ended without submit_plan; retrying once. " <>
            "Model said: " <> Mehungry.AI.Agent.excerpt(text)
        )

        :telemetry.execute([:mehungry, :ai, :agent, :no_submit_retry], %{count: 1}, %{
          agent: agent
        })

        case run_fun.(@firm_submit_instruction) do
          {:ok, text, %{submitted: nil}} ->
            Logger.warning(
              "MealPlanCore[#{agent}]: retry also ended without submit_plan. " <>
                "Model said: " <> Mehungry.AI.Agent.excerpt(text)
            )

            {:error, :no_plan_submitted}

          other ->
            other
        end

      other ->
        other
    end
  end

  # ── errors ────────────────────────────────────────────────────────────────────

  @doc """
  A message a person can read for a failed generation. Internal reasons (loop
  limits, API errors) never reach the UI verbatim.
  """
  def error_message(:max_iterations_reached),
    do: "The planner could not finish a plan in time. Please try again."

  def error_message(:max_tokens_reached),
    do: "The plan was too long to finish. Please try again."

  def error_message(:no_plan_submitted),
    do:
      "The planner could not build a plan from the available recipes. " <>
        "Try loosening the preferences or adding more recipes."

  def error_message(:no_meals_created),
    do:
      "The plan produced no new meals, so nothing was changed. " <>
        "When filling gaps this usually means the week is already full."

  def error_message(:replace_failed),
    do:
      "The new plan could not be saved, so the existing meals were left untouched. " <>
        "Please try again."

  def error_message(:week_in_past),
    do: "That week is already over — pick the current or a future week."

  def error_message(_reason), do: "Meal plan generation failed. Please try again."
end
