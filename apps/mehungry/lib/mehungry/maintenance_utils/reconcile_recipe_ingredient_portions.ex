defmodule Mehungry.ReconcileRecipeIngredientPortions do
  @moduledoc """
  One-shot reconciliation of legacy `recipe_ingredients` rows onto the
  `IngredientPortion` model.

  ## Background

  A `recipe_ingredients` row now carries **both** a legacy `measurement_unit_id`
  and the newer `ingredient_portion_id` (added in migration
  `20260820000003_add_ingredient_portion_id_to_recipe_ingredients`, which also
  bulk-backfilled the FK from the `(ingredient_id, measurement_unit_id)` pair).
  The nutrition engine (`Mehungry.Food.NutrientCalculation.calculate_gram_weight/5`)
  prefers `ingredient_portion_id` and falls back to matching a portion by
  `measurement_unit_id`, so any old row whose `(ingredient, unit)` pair *has* a
  portion already computes correctly.

  The rows that stay broken after that migration are those where **no
  `IngredientPortion` exists** for the row's `(ingredient, unit)` pair. They keep
  `ingredient_portion_id = NULL`, the read-path fallback also finds nothing, and
  the ingredient silently contributes **0 g**. This is mostly pre-2023 recipes
  (the `ingredient_portions` table only exists from `20231229`) whose ingredients
  never got portion rows for the referenced units.

  A second, subtler class is a legacy row that references a **measurement unit**
  by name (e.g. the "piece" unit) while the ingredient's matching portion is a
  **description-only portion** (`measurement_unit_id: nil`, `description: "piece"`).
  The two describe the same portion but were never linked, so a plain
  `measurement_unit_id` match misses it. `run/1` resolves these by name.

  ## What `run/1` does

  1. **Assess** — classifies every row with a non-null `measurement_unit_id`.
  2. **Backfill resolvable rows** — sets `ingredient_portion_id` from the lowest
     portion matching `(ingredient_id, measurement_unit_id)`. Idempotent.
  3. **Link named portions** — for rows whose unit has no matching portion, links
     a **description-only** portion of the same ingredient whose `description`
     matches the unit's name. Matching is case-insensitive and alias-aware, so
     the "piece" unit ↔ a "piece"/"Piece" description portion links, and so does
     a "teaspoon" unit ↔ a "tsp" description portion.
  4. **Synthesize missing portions** (opt-out via `synthesize: false`) — for each
     still-unresolved mass/volume `(ingredient, unit)` pair, creates the missing
     `IngredientPortion`, then re-runs step 2. Mass units use the
     ingredient-independent grams-per-unit constant; volume units are derived from
     an existing volume portion of the same ingredient — a measurement-unit
     portion *or* a description-only one that names a volume unit (e.g. a "cup"
     portion) — via density through mL.
  5. **Report the remainder** — pairs that still cannot be resolved by any of the
     above (units with no mass/volume conversion and no matching named portion,
     or volume units with no anchor portion) are returned and logged for admin
     review. Nothing is guessed and no unit is collapsed to grams. In a dry run
     the same classifier predicts this set without writing.

  ## Usage

      # dry run — assessment only, no writes:
      Mehungry.ReconcileRecipeIngredientPortions.run(dry_run: true)

      # full reconciliation:
      Mehungry.ReconcileRecipeIngredientPortions.run()

      # backfill/link only, do not create any portions:
      Mehungry.ReconcileRecipeIngredientPortions.run(synthesize: false)

  Returns a report map (see `t:report/0`).

  ## Note on the existing backfill scripts

  This module computes conversions **inline** and does not call
  `Mehungry.BackfillAllMassUnits` / `Mehungry.BackfillAllVolumeUnits`: both of
  those store the *inverse* factor as `gram_weight` (e.g. oz → `1/28.3495`
  instead of `28.3495`), which would corrupt nutrition. The constants below are
  the correct grams-per-unit / millilitres-per-unit values.
  """

  import Ecto.Query

  alias Mehungry.Repo
  alias Mehungry.Food.{IngredientPortion, MeasurementUnit}

  # Correct grams-per-one-unit for mass units, keyed by canonical token.
  # Ingredient-independent, so a mass portion can be created without an anchor.
  @grams_per_unit %{
    "g" => 1.0,
    "mg" => 0.001,
    "kg" => 1000.0,
    "oz" => 28.3495,
    "lb" => 453.592
  }

  # Millilitres-per-one-unit for volume units, keyed by canonical token.
  # Grams-per-unit for a volume depends on density, so synthesis needs an
  # existing volume portion of the same ingredient as an anchor.
  @ml_per_unit %{
    "ml" => 1.0,
    "tsp" => 5.0,
    "tbsp" => 15.0,
    "cup" => 240.0,
    "liter" => 1000.0,
    "fl_oz" => 29.5735,
    "pint" => 473.0,
    "quart" => 946.0,
    "gallon" => 3785.0
  }

  # Maps the many surface spellings of a unit — the DB has both "teaspoon" (a
  # measurement-unit name) and "tsp" (a portion description) — onto one canonical
  # token so name-matching and volume anchoring treat them as equal. Keys are
  # already lower-cased; lookups downcase first, so matching is case-insensitive.
  @unit_aliases %{
    # mass
    "g" => "g",
    "gr" => "g",
    "gram" => "g",
    "grams" => "g",
    "grammar" => "g",
    "mg" => "mg",
    "milligram" => "mg",
    "milligrams" => "mg",
    "kg" => "kg",
    "kilogram" => "kg",
    "kilograms" => "kg",
    "oz" => "oz",
    "ounce" => "oz",
    "ounces" => "oz",
    "lb" => "lb",
    "lbs" => "lb",
    "pound" => "lb",
    "pounds" => "lb",
    # volume
    "ml" => "ml",
    "cc" => "ml",
    "milliliter" => "ml",
    "millilitre" => "ml",
    "milliliters" => "ml",
    "millilitres" => "ml",
    "tsp" => "tsp",
    "teaspoon" => "tsp",
    "teaspoons" => "tsp",
    "tbsp" => "tbsp",
    "tbs" => "tbsp",
    "tbl" => "tbsp",
    "tablespoon" => "tbsp",
    "tablespoons" => "tbsp",
    "cup" => "cup",
    "cups" => "cup",
    "l" => "liter",
    "liter" => "liter",
    "litre" => "liter",
    "liters" => "liter",
    "litres" => "liter",
    "fl oz" => "fl_oz",
    "fl. oz." => "fl_oz",
    "floz" => "fl_oz",
    "fluid ounce" => "fl_oz",
    "fluid ounces" => "fl_oz",
    "fluid_ounce" => "fl_oz",
    "pint" => "pint",
    "pints" => "pint",
    "pt" => "pint",
    "quart" => "quart",
    "quarts" => "quart",
    "qt" => "quart",
    "gallon" => "gallon",
    "gallons" => "gallon",
    "gal" => "gallon",
    # count
    "piece" => "piece",
    "pieces" => "piece"
  }

  @typedoc """
  Structured outcome. `unresolved` entries are the admin-review queue: one per
  `(ingredient, unit)` pair still lacking a portion, with the affected recipes.
  """
  @type report :: %{
          dry_run: boolean(),
          total_with_unit: non_neg_integer(),
          already_set: non_neg_integer(),
          gram_skipped: non_neg_integer(),
          needs_work: non_neg_integer(),
          backfilled: non_neg_integer(),
          description_linked: non_neg_integer(),
          synthesized_portions: non_neg_integer(),
          unresolved: [
            %{
              ingredient_id: integer(),
              ingredient_name: String.t() | nil,
              measurement_unit_id: integer(),
              unit_name: String.t() | nil,
              reason: :no_conversion | :no_anchor_portion,
              row_count: non_neg_integer(),
              recipe_ids: [integer()]
            }
          ]
        }

  @doc """
  Runs the reconciliation. Options:

    * `:dry_run` (default `false`) — classify and report only, no writes.
    * `:synthesize` (default `true`) — create missing mass/volume portions.
  """
  @spec run(keyword()) :: report()
  def run(opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)
    synthesize? = Keyword.get(opts, :synthesize, true)

    units_by_id = load_units_by_id()
    gram_ids = gram_unit_ids(units_by_id)

    assessment = assess(gram_ids)

    IO.puts("""

    ── RecipeIngredient → IngredientPortion reconciliation #{if dry_run?, do: "(DRY RUN)", else: ""} ──
      rows with a measurement_unit : #{assessment.total_with_unit}
      already linked to a portion  : #{assessment.already_set}
      gram-family (no portion needed): #{assessment.gram_skipped}
      need work                    : #{assessment.needs_work}
    """)

    {backfilled, description_linked, synthesized} =
      if dry_run? do
        {0, 0, 0}
      else
        backfilled_1 = backfill_resolvable()
        IO.puts("  ✔ linked #{backfilled_1} row(s) to existing portions")

        linked = link_named_portions(gram_ids, units_by_id)
        IO.puts("  ✔ linked #{linked} row(s) to matching named portions")

        {synthesized, backfilled_2} =
          if synthesize? do
            created = synthesize_missing_portions(gram_ids, units_by_id)
            IO.puts("  ✔ created #{created} missing portion(s)")
            relinked = if created > 0, do: backfill_resolvable(), else: 0
            IO.puts("  ✔ linked #{relinked} newly-portioned row(s)")
            {created, relinked}
          else
            {0, 0}
          end

        {backfilled_1 + backfilled_2, linked, synthesized}
      end

    finalize(%{
      dry_run: dry_run?,
      total_with_unit: assessment.total_with_unit,
      already_set: assessment.already_set,
      gram_skipped: assessment.gram_skipped,
      needs_work: assessment.needs_work,
      backfilled: backfilled,
      description_linked: description_linked,
      synthesized_portions: synthesized,
      unresolved: build_unresolved_report(gram_ids, units_by_id)
    })
  end

  # ── Assessment ────────────────────────────────────────────────────────────

  defp assess(gram_ids) do
    total_with_unit = Repo.aggregate(with_unit(), :count)

    already_set =
      with_unit()
      |> where([ri], not is_nil(ri.ingredient_portion_id))
      |> Repo.aggregate(:count)

    gram_skipped =
      with_unit()
      |> where([ri], is_nil(ri.ingredient_portion_id) and ri.measurement_unit_id in ^gram_ids)
      |> Repo.aggregate(:count)

    %{
      total_with_unit: total_with_unit,
      already_set: already_set,
      gram_skipped: gram_skipped,
      needs_work: total_with_unit - already_set - gram_skipped
    }
  end

  # ── Pass: backfill rows whose (ingredient, unit) portion already exists ─────

  # Correlated UPDATE mirroring migration 20260820000003, but only touches rows
  # where a matching portion actually exists (so the count reflects real links
  # and NULL→NULL no-ops are excluded). Safe to re-run.
  defp backfill_resolvable do
    %{num_rows: n} =
      Repo.query!(
        """
        UPDATE recipe_ingredients ri
        SET ingredient_portion_id = (
          SELECT MIN(ip.id) FROM ingredient_portions ip
          WHERE ip.ingredient_id = ri.ingredient_id
            AND ip.measurement_unit_id = ri.measurement_unit_id
        )
        WHERE ri.measurement_unit_id IS NOT NULL
          AND ri.ingredient_portion_id IS NULL
          AND EXISTS (
            SELECT 1 FROM ingredient_portions ip2
            WHERE ip2.ingredient_id = ri.ingredient_id
              AND ip2.measurement_unit_id = ri.measurement_unit_id
          )
        """,
        []
      )

    n
  end

  # ── Pass: link legacy rows to a matching description-only portion by name ────

  # A legacy row references a measurement unit (e.g. "piece") while the matching
  # portion is a description-only portion (`measurement_unit_id: nil`,
  # `description: "piece"`). Links the row's `ingredient_portion_id` to that
  # portion when the unit name matches the portion description.
  defp link_named_portions(gram_ids, units_by_id) do
    pairs = unresolved_pairs(gram_ids)
    desc_by_ingredient = description_portions_by_ingredient(pair_ingredient_ids(pairs))

    Enum.reduce(pairs, 0, fn {ingredient_id, unit_id}, linked ->
      unit_name = unit_name(units_by_id, unit_id)

      case find_named_portion(desc_by_ingredient[ingredient_id], unit_name) do
        nil ->
          linked

        portion ->
          {n, _} =
            from(ri in "recipe_ingredients",
              where:
                ri.ingredient_id == ^ingredient_id and ri.measurement_unit_id == ^unit_id and
                  is_nil(ri.ingredient_portion_id)
            )
            |> Repo.update_all(set: [ingredient_portion_id: portion.id])

          IO.puts(
            "    ↳ ingredient #{ingredient_id}: unit \"#{unit_name}\" → named portion " <>
              "##{portion.id} (\"#{portion.description}\")"
          )

          linked + n
      end
    end)
  end

  # ── Pass: synthesize the missing mass/volume portions ───────────────────────

  defp synthesize_missing_portions(gram_ids, units_by_id) do
    unresolved_pairs(gram_ids)
    |> Enum.reduce(0, fn {ingredient_id, unit_id}, created ->
      unit_name = unit_name(units_by_id, unit_id)

      case synth_gram_weight(ingredient_id, unit_name, units_by_id) do
        {:ok, gram_weight} ->
          insert_portion(ingredient_id, unit_id, gram_weight)
          IO.puts("    + portion: ingredient #{ingredient_id}, #{unit_name} = #{gram_weight} g")
          created + 1

        :skip ->
          created
      end
    end)
  end

  # Mass units: the constant is ingredient-independent.
  # Volume units: derive grams/unit from any existing volume portion (density).
  defp synth_gram_weight(ingredient_id, unit_name, units_by_id) do
    cond do
      grams = mass_grams(unit_name) ->
        {:ok, grams}

      ml = volume_ml(unit_name) ->
        case volume_anchor(ingredient_id, units_by_id) do
          {:ok, grams_per_ml} -> {:ok, grams_per_ml * ml}
          :none -> :skip
        end

      true ->
        :skip
    end
  end

  # grams-per-millilitre from any existing volume portion of the ingredient —
  # either a measurement-unit-bearing portion (unit name is a volume unit) or a
  # description-only portion whose description names a volume unit (e.g. a "cup"
  # portion with `measurement_unit_id: nil`).
  defp volume_anchor(ingredient_id, units_by_id) do
    IngredientPortion
    |> where([ip], ip.ingredient_id == ^ingredient_id)
    |> where([ip], not is_nil(ip.gram_weight) and ip.gram_weight > 0.0)
    |> order_by([ip], asc: ip.id)
    |> select([ip], %{gw: ip.gram_weight, amount: ip.amount, mu_id: ip.measurement_unit_id, desc: ip.description})
    |> Repo.all()
    |> Enum.find_value(:none, fn p ->
      ml =
        cond do
          p.mu_id -> volume_ml(unit_name(units_by_id, p.mu_id))
          is_binary(p.desc) -> volume_ml(p.desc)
          true -> nil
        end

      if ml do
        amount = if is_number(p.amount) and p.amount > 0, do: p.amount, else: 1.0
        {:ok, p.gw / amount / ml}
      end
    end)
  end

  defp insert_portion(ingredient_id, unit_id, gram_weight) do
    unless mu_portion_exists?(ingredient_id, unit_id) do
      %IngredientPortion{}
      |> IngredientPortion.changeset(%{
        ingredient_id: ingredient_id,
        measurement_unit_id: unit_id,
        gram_weight: gram_weight,
        amount: 1.0
      })
      |> Repo.insert!()
    end
  end

  # ── Report ──────────────────────────────────────────────────────────────────

  # Only genuinely-unresolvable pairs, using the shared `classify/4` so a dry run
  # predicts the same set the real run leaves behind.
  defp build_unresolved_report(gram_ids, units_by_id) do
    pairs = unresolved_pairs(gram_ids)
    desc_by_ingredient = description_portions_by_ingredient(pair_ingredient_ids(pairs))

    reasons =
      pairs
      |> Enum.map(fn {ingredient_id, unit_id} = pair ->
        unit_name = unit_name(units_by_id, unit_id)

        {pair, classify(ingredient_id, unit_id, unit_name, units_by_id, desc_by_ingredient)}
      end)
      |> Enum.filter(fn {_pair, res} -> match?({:unresolved, _}, res) end)
      |> Map.new(fn {pair, {:unresolved, reason}} -> {pair, reason} end)

    unresolved_rows(gram_ids)
    |> Enum.filter(fn r -> Map.has_key?(reasons, {r.ingredient_id, r.measurement_unit_id}) end)
    |> Enum.group_by(fn r -> {r.ingredient_id, r.measurement_unit_id} end)
    |> Enum.map(fn {{ingredient_id, unit_id} = pair, rows} ->
      %{
        ingredient_id: ingredient_id,
        ingredient_name: rows |> List.first() |> Map.get(:ingredient_name),
        measurement_unit_id: unit_id,
        unit_name: unit_name(units_by_id, unit_id),
        reason: Map.fetch!(reasons, pair),
        row_count: length(rows),
        recipe_ids: rows |> Enum.map(& &1.recipe_id) |> Enum.uniq()
      }
    end)
    |> Enum.sort_by(& &1.row_count, :desc)
  end

  # Single source of truth for "can this (ingredient, unit) pair be resolved?".
  defp classify(ingredient_id, unit_id, unit_name, units_by_id, desc_by_ingredient) do
    cond do
      mu_portion_exists?(ingredient_id, unit_id) ->
        {:resolvable, :existing_portion}

      find_named_portion(desc_by_ingredient[ingredient_id], unit_name) ->
        {:resolvable, :named_portion}

      mass_grams(unit_name) ->
        {:resolvable, :mass_synth}

      volume_ml(unit_name) ->
        case volume_anchor(ingredient_id, units_by_id) do
          {:ok, _} -> {:resolvable, :volume_synth}
          :none -> {:unresolved, :no_anchor_portion}
        end

      true ->
        {:unresolved, :no_conversion}
    end
  end

  defp finalize(report) do
    IO.puts(
      "  → linked #{report.backfilled}, named-linked #{report.description_linked}, " <>
        "portions created #{report.synthesized_portions}"
    )

    if report.unresolved == [] do
      IO.puts("\n✅ No unresolved recipe ingredients. Every non-gram row is portioned.\n")
    else
      IO.puts("\n⚠️  #{length(report.unresolved)} (ingredient, unit) pair(s) need admin review:")

      Enum.each(report.unresolved, fn u ->
        IO.puts(
          "   • ingredient #{u.ingredient_id} (#{u.ingredient_name}) × unit #{u.measurement_unit_id} " <>
            "(#{u.unit_name}) — #{u.reason}, #{u.row_count} row(s) in recipes #{inspect(u.recipe_ids)}"
        )
      end)

      IO.puts("")
    end

    report
  end

  # ── Named-portion matching ──────────────────────────────────────────────────

  defp find_named_portion(nil, _unit_name), do: nil
  defp find_named_portion(_portions, nil), do: nil

  defp find_named_portion(portions, unit_name) do
    Enum.find(portions, fn p -> unit_tokens_match?(p.description, unit_name) end)
  end

  # Case-insensitive, alias-aware ("teaspoon" ↔ "tsp"), and tolerant of a single
  # trailing plural "s" for tokens not covered by the alias table (so "sprig" ↔
  # "sprigs" still match) without mangling words like "glass".
  defp unit_tokens_match?(a, b) when is_binary(a) and is_binary(b) do
    a = canon(a)
    b = canon(b)
    a != "" and (a == b or a == b <> "s" or b == a <> "s")
  end

  defp unit_tokens_match?(_a, _b), do: false

  # Lower-case + trim, then collapse known synonyms to a canonical token. The
  # downcase makes all matching case-insensitive.
  defp canon(s) do
    n = s |> String.downcase() |> String.trim()
    Map.get(@unit_aliases, n, n)
  end

  defp mass_grams(name) when is_binary(name), do: Map.get(@grams_per_unit, canon(name))
  defp mass_grams(_), do: nil

  defp volume_ml(name) when is_binary(name), do: Map.get(@ml_per_unit, canon(name))
  defp volume_ml(_), do: nil

  # ── Shared queries ──────────────────────────────────────────────────────────

  defp with_unit do
    from(ri in "recipe_ingredients", where: not is_nil(ri.measurement_unit_id))
  end

  # Distinct (ingredient_id, measurement_unit_id) pairs still needing a portion.
  defp unresolved_pairs(gram_ids) do
    from(ri in "recipe_ingredients",
      where:
        not is_nil(ri.measurement_unit_id) and is_nil(ri.ingredient_portion_id) and
          ri.measurement_unit_id not in ^gram_ids,
      distinct: true,
      select: {ri.ingredient_id, ri.measurement_unit_id}
    )
    |> Repo.all()
  end

  # Row-level detail for the still-unresolved pairs, joined for display.
  defp unresolved_rows(gram_ids) do
    from(ri in "recipe_ingredients",
      join: i in "ingredients",
      on: i.id == ri.ingredient_id,
      where:
        not is_nil(ri.measurement_unit_id) and is_nil(ri.ingredient_portion_id) and
          ri.measurement_unit_id not in ^gram_ids,
      select: %{
        ingredient_id: ri.ingredient_id,
        ingredient_name: i.name,
        measurement_unit_id: ri.measurement_unit_id,
        recipe_id: ri.recipe_id
      }
    )
    |> Repo.all()
  end

  # description-only portions (no unit) for the given ingredients, grouped.
  defp description_portions_by_ingredient([]), do: %{}

  defp description_portions_by_ingredient(ingredient_ids) do
    from(p in IngredientPortion,
      where:
        p.ingredient_id in ^ingredient_ids and is_nil(p.measurement_unit_id) and
          not is_nil(p.description),
      select: %{id: p.id, ingredient_id: p.ingredient_id, description: p.description}
    )
    |> Repo.all()
    |> Enum.group_by(& &1.ingredient_id)
  end

  defp mu_portion_exists?(ingredient_id, unit_id) do
    IngredientPortion
    |> where([ip], ip.ingredient_id == ^ingredient_id and ip.measurement_unit_id == ^unit_id)
    |> Repo.exists?()
  end

  defp pair_ingredient_ids(pairs), do: pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

  defp unit_name(units_by_id, unit_id), do: units_by_id |> Map.get(unit_id, %{}) |> Map.get(:name)

  defp load_units_by_id do
    MeasurementUnit
    |> select([mu], %{id: mu.id, name: mu.name, alternate_name: mu.alternate_name})
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  # Mirrors NutrientCalculation.load_gram_unit_ids/0.
  defp gram_unit_ids(units_by_id) do
    for {id, u} <- units_by_id,
        u.alternate_name == "g" or u.name in ["g", "gram", "grammar"],
        do: id
  end
end
