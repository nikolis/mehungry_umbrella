defmodule Mehungry.AI.Agents.MealPlanCore.Rules do
  @moduledoc """
  The **composition rules** for an AI meal plan: what each slot of a day may hold.
  Pure — no DB, no model — so every rule is unit-testable on its own. `submit_plan`
  (`MealPlanCore.submit_plan_tool/2`) calls `errors/2` and hands any errors back to
  the model to fix.

  A plan entry is one `(date, slot)` cell holding a list of **items**, each a recipe
  (`recipe_id`, `servings`, `cooking_portions`, `part`) or an ingredient
  (`ingredient_id`, `quantity`, `unit_selection`). A recipe's `part` is `"main"`
  (default), `"salad"` or `"dessert"`.

  | Slot | Allowed |
  |---|---|
  | Breakfast | exactly 1 `breakfast` recipe (+ fruit / nut ingredients) |
  | Lunch | exactly 1 `main`/`soup` recipe, optionally + 1 `salad` part and + 1 `dessert` part; no ingredients |
  | Dinner | exactly 1 `main`/`soup`/`dinner` recipe; nothing else |
  | Morning snack | ingredients only, ≥ 1 (with snack kinds on: ≥ 1 seasonal fruit, rest fruit/nuts) |
  | Afternoon snack | ingredients only, ≥ 1 (with snack kinds on: ≥ 1 nut, rest fruit/nuts) |

  Rule groups, switched on per run through `ctx.rules`:

    * always — a main recipe's meal roles fit its slot (`MealRoles.fits_slot?/2`);
      unclassified recipes always fit.
    * `:composition` — the item counts / kinds / parts in the table above.
    * `:time` — Breakfast's recipe takes ≤ #{15} min; Dinner's recipe takes
      ≤ #{40} min unless it has the `dinner` role. Unknown time fails
      (`Food.total_time_minutes/1`; recipe meta carries it as `total_minutes`).
    * `:snack_kinds` — snack (and breakfast) ingredients must come from the run's
      seasonal-fruit / curated-nut sets (`ctx.fruit_ids`, `ctx.nut_ids`).

  Errors are written for the model: what is wrong, and which tool call fixes it.
  """

  alias Mehungry.Food.MealRoles

  @breakfast_max_minutes 15
  @dinner_max_minutes 40
  @parts ~w(main salad dessert)
  @snack_slots ["Morning Snack", "Afternoon Snack"]

  def breakfast_max_minutes, do: @breakfast_max_minutes
  def dinner_max_minutes, do: @dinner_max_minutes
  def parts, do: @parts

  @doc """
  Every composition error in `entries` (string-keyed `%{"date", "slot", "items"}`
  maps, as `MealPlanCore.expand_entry/1` builds them). `ctx`:

    * `:recipe_meta` — `%{recipe_id => %{title, roles, total_minutes}}`
    * `:rules` — `MapSet` of enabled groups (`:composition`, `:time`, `:snack_kinds`)
    * `:fruit_ids`, `:nut_ids` — `MapSet`s, read only with `:snack_kinds`
  """
  def errors(entries, ctx) do
    Enum.flat_map(entries, &entry_errors(&1, ctx))
  end

  defp entry_errors(%{"slot" => slot, "items" => items} = entry, ctx) when is_list(items) do
    on? = &MapSet.member?(Map.get(ctx, :rules, MapSet.new()), &1)
    cell = "#{entry["date"]} #{slot}"
    {recipes, ingredients} = Enum.split_with(items, &is_integer(&1["recipe_id"]))
    {mains, extras} = Enum.split_with(recipes, &(part(&1) == "main"))

    part_errors(recipes, cell) ++
      role_errors(mains, slot, cell, ctx) ++
      if(on?.(:composition),
        do: composition_errors(slot, cell, mains, extras, ingredients, ctx),
        else: []
      ) ++
      if(on?.(:time), do: time_errors(slot, cell, mains, ctx), else: []) ++
      if(on?.(:snack_kinds), do: snack_kind_errors(slot, cell, ingredients, ctx), else: [])
  end

  defp entry_errors(_entry, _ctx), do: []

  defp part(item), do: item["part"] || "main"

  # ── parts + roles ────────────────────────────────────────────────────────────

  defp part_errors(recipes, cell) do
    for item <- recipes, part(item) not in @parts do
      "#{cell}: part \"#{item["part"]}\" is not one of #{Enum.join(@parts, ", ")}."
    end
  end

  # A leftover Dinner eats that day's Lunch main: it was judged at Lunch, and
  # reheating takes no prep — so neither the role nor the time check applies.
  defp role_errors(mains, slot, cell, ctx) do
    for item <- mains,
        item["leftover"] != true,
        %{roles: roles, title: title} <- [meta(ctx, item)],
        not MealRoles.fits_slot?(roles, slot) do
      is_a = Enum.map_join(roles, "/", &MealRoles.label/1) |> String.downcase()

      "#{cell}: \"#{title}\" (recipe_id #{item["recipe_id"]}) is a #{is_a}, not " <>
        "#{needs(slot)}. Replace it — call the search tool with slot: \"#{slot}\" to get " <>
        "dishes that fit."
    end
  end

  defp needs("Breakfast"), do: "a breakfast dish"
  defp needs("Lunch"), do: "a main or a meal soup — a complete Lunch"
  defp needs("Dinner"), do: "a main, a dinner dish or a meal soup — a complete Dinner"
  defp needs(_snack), do: "a snack, dessert or drink — or better, a whole-food ingredient"

  defp meta(ctx, item), do: Map.get(Map.get(ctx, :recipe_meta, %{}), item["recipe_id"])

  # ── composition ──────────────────────────────────────────────────────────────

  defp composition_errors("Breakfast", cell, mains, extras, _ingredients, _ctx) do
    one_main(cell, mains, "Breakfast") ++
      no_extras(
        cell,
        extras,
        "Breakfast takes one breakfast recipe, optionally with fruit or nuts"
      )
  end

  defp composition_errors("Lunch", cell, mains, extras, ingredients, ctx) do
    {salads, desserts} = Enum.split_with(extras, &(part(&1) == "salad"))

    one_main(cell, mains, "Lunch") ++
      at_most_one(cell, salads, "salad") ++
      at_most_one(cell, desserts, "dessert") ++
      part_role_errors(cell, salads, "salad", ctx) ++
      part_role_errors(cell, desserts, "dessert", ctx) ++
      no_ingredients(
        cell,
        ingredients,
        "Lunch is a recipe, optionally with a salad and/or a dessert recipe"
      )
  end

  defp composition_errors("Dinner", cell, mains, extras, ingredients, _ctx) do
    one_main(cell, mains, "Dinner") ++
      no_extras(cell, extras, "Dinner is a single recipe") ++
      no_ingredients(cell, ingredients, "Dinner is a single recipe")
  end

  defp composition_errors(slot, cell, mains, extras, ingredients, ctx)
       when slot in @snack_slots do
    recipe_errors =
      case mains ++ extras do
        [] ->
          []

        _ ->
          [
            "#{cell}: a snack is whole foods, not a recipe — use ingredients from " <>
              "#{snack_tool(ctx)} (e.g. a piece of fruit, a handful of nuts)."
          ]
      end

    empty_errors =
      if ingredients == [],
        do: ["#{cell}: a snack needs at least one ingredient."],
        else: []

    recipe_errors ++ empty_errors
  end

  defp composition_errors(_slot, _cell, _mains, _extras, _ingredients, _ctx), do: []

  defp snack_tool(ctx) do
    if MapSet.member?(Map.get(ctx, :rules, MapSet.new()), :snack_kinds),
      do: "list_snack_options",
      else: "search_ingredients"
  end

  defp one_main(_cell, [_one], _slot), do: []

  defp one_main(cell, [], slot),
    do: ["#{cell}: #{slot} needs one main recipe (part \"main\")."]

  defp one_main(cell, _many, slot),
    do: ["#{cell}: #{slot} takes exactly one main recipe — keep one and remove the others."]

  defp no_extras(_cell, [], _why), do: []
  defp no_extras(cell, _extras, why), do: ["#{cell}: remove the salad/dessert items — #{why}."]

  defp no_ingredients(_cell, [], _why), do: []

  defp no_ingredients(cell, _ingredients, why),
    do: ["#{cell}: remove the ingredient items — #{why}."]

  defp at_most_one(_cell, list, _part) when length(list) <= 1, do: []

  defp at_most_one(cell, _list, part),
    do: ["#{cell}: Lunch takes at most one #{part} — keep one."]

  # A salad / dessert part must be a dish with that role (unclassified passes).
  defp part_role_errors(cell, items, role, ctx) do
    for item <- items,
        %{roles: roles, title: title} <- [meta(ctx, item)],
        roles not in [nil, []],
        role not in roles do
      "#{cell}: \"#{title}\" (recipe_id #{item["recipe_id"]}) is not a #{role}. Call the " <>
        "search tool with slot: \"Lunch\" and part: \"#{role}\" to find one."
    end
  end

  # ── time ─────────────────────────────────────────────────────────────────────

  defp time_errors("Breakfast", cell, mains, ctx) do
    for item <- mains,
        %{title: title} = m <- [meta(ctx, item)],
        not within?(m[:total_minutes], @breakfast_max_minutes) do
      "#{cell}: \"#{title}\" #{takes(m[:total_minutes])}; breakfast needs a recipe of at most " <>
        "#{@breakfast_max_minutes} minutes. Call the search tool with slot: \"Breakfast\"."
    end
  end

  defp time_errors("Dinner", cell, mains, ctx) do
    for item <- mains,
        item["leftover"] != true,
        %{title: title} = m <- [meta(ctx, item)],
        "dinner" not in (m[:roles] || []),
        not within?(m[:total_minutes], @dinner_max_minutes) do
      "#{cell}: \"#{title}\" #{takes(m[:total_minutes])}; dinner needs a recipe of at most " <>
        "#{@dinner_max_minutes} minutes or a dinner dish. Call the search tool with slot: \"Dinner\"."
    end
  end

  defp time_errors(_slot, _cell, _mains, _ctx), do: []

  defp within?(minutes, max) when is_integer(minutes), do: minutes <= max
  defp within?(_unknown, _max), do: false

  defp takes(minutes) when is_integer(minutes), do: "takes #{minutes} min"
  defp takes(_), do: "has no known prep/cook time"

  # ── snack kinds ──────────────────────────────────────────────────────────────

  defp snack_kind_errors(slot, cell, ingredients, ctx)
       when slot in ["Breakfast" | @snack_slots] do
    fruit = Map.get(ctx, :fruit_ids) || MapSet.new()
    nuts = Map.get(ctx, :nut_ids) || MapSet.new()
    ids = Enum.map(ingredients, & &1["ingredient_id"])

    stray =
      for id <- ids, not MapSet.member?(fruit, id), not MapSet.member?(nuts, id) do
        "#{cell}: ingredient_id #{id} is not one of the seasonal fruits or nuts — use only " <>
          "ingredients from list_snack_options."
      end

    stray ++ required_kind(slot, cell, ids, fruit, nuts)
  end

  defp snack_kind_errors(_slot, _cell, _ingredients, _ctx), do: []

  # With no seasonal fruit available the morning snack falls back to nuts.
  defp required_kind("Morning Snack", cell, ids, fruit, nuts) do
    cond do
      Enum.any?(ids, &MapSet.member?(fruit, &1)) -> []
      MapSet.size(fruit) == 0 and Enum.any?(ids, &MapSet.member?(nuts, &1)) -> []
      true -> ["#{cell}: the morning snack needs at least one seasonal fruit."]
    end
  end

  defp required_kind("Afternoon Snack", cell, ids, _fruit, nuts) do
    if Enum.any?(ids, &MapSet.member?(nuts, &1)),
      do: [],
      else: ["#{cell}: the afternoon snack needs at least one nut."]
  end

  defp required_kind(_slot, _cell, _ids, _fruit, _nuts), do: []
end
