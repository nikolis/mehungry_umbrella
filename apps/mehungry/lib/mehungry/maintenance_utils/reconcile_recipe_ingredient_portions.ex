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
  the ingredient silently contributes **0 g** (with a `Logger.warning`). This is
  mostly pre-2023 recipes (the `ingredient_portions` table only exists from
  `20231229`) whose ingredients never got portion rows for the referenced units.

  ## What `run/1` does

  1. **Assess** — classifies every row with a non-null `measurement_unit_id` into
     `already_set`, `gram_skipped` (grams need no portion — the quantity *is*
     grams), `resolvable` (a portion exists, just not linked), and `unresolved`.
  2. **Backfill resolvable rows** — sets `ingredient_portion_id` from the lowest
     matching portion id. Idempotent; the same resolve the changeset does at save.
  3. **Synthesize missing portions** (opt-out via `synthesize: false`) — for each
     still-unresolved `(ingredient, unit)` pair whose unit is a mass or volume
     unit, creates the missing `IngredientPortion`, then re-runs step 2. Mass
     units use the ingredient-independent grams-per-unit constant; volume units
     are derived from an existing volume portion of the same ingredient (density
     through millilitres).
  4. **Report the remainder** — pairs that still cannot be resolved (units with no
     mass/volume conversion such as "medium banana"/"slice", or volume units with
     no anchor portion for the ingredient) are returned and logged for admin
     review. Nothing is guessed and no unit is collapsed to grams.

  ## Usage

      # dry run — assessment only, no writes:
      Mehungry.ReconcileRecipeIngredientPortions.run(dry_run: true)

      # full reconciliation:
      Mehungry.ReconcileRecipeIngredientPortions.run()

      # backfill only, do not create any portions:
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

  # Correct grams-per-one-unit for mass units. Ingredient-independent, so a mass
  # portion can always be created without an anchor portion.
  @mass_grams_per_unit %{
    "g" => 1.0,
    "gram" => 1.0,
    "grammar" => 1.0,
    "mg" => 0.001,
    "kg" => 1000.0,
    "oz" => 28.3495,
    "lb" => 453.592
  }

  # Millilitres-per-one-unit for volume units. Grams-per-unit for a volume
  # depends on the ingredient's density, so synthesis needs an existing volume
  # portion of the same ingredient as an anchor.
  @volume_ml_per_unit %{
    "ml" => 1.0,
    "teaspoon" => 5.0,
    "tsp" => 5.0,
    "tablespoon" => 15.0,
    "tbsp" => 15.0,
    "cup" => 240.0,
    "liter" => 1000.0,
    "fluid_ounce" => 29.5735,
    "pint" => 473.0,
    "quart" => 946.0,
    "gallon" => 3785.0
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
          backfilled: non_neg_integer(),
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

    if dry_run? do
      unresolved = build_unresolved_report(gram_ids, units_by_id)

      finalize(%{
        dry_run: true,
        total_with_unit: assessment.total_with_unit,
        already_set: assessment.already_set,
        gram_skipped: assessment.gram_skipped,
        backfilled: 0,
        synthesized_portions: 0,
        unresolved: unresolved
      })
    else
      backfilled_1 = backfill_resolvable()
      IO.puts("  ✔ linked #{backfilled_1} row(s) to existing portions")

      {synthesized, backfilled_2} =
        if synthesize? do
          created = synthesize_missing_portions(gram_ids, units_by_id)
          IO.puts("  ✔ created #{created} missing portion(s)")
          linked = if created > 0, do: backfill_resolvable(), else: 0
          IO.puts("  ✔ linked #{linked} newly-portioned row(s)")
          {created, linked}
        else
          {0, 0}
        end

      unresolved = build_unresolved_report(gram_ids, units_by_id)

      finalize(%{
        dry_run: false,
        total_with_unit: assessment.total_with_unit,
        already_set: assessment.already_set,
        gram_skipped: assessment.gram_skipped,
        backfilled: backfilled_1 + backfilled_2,
        synthesized_portions: synthesized,
        unresolved: unresolved
      })
    end
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

  # ── Pass: synthesize the missing mass/volume portions ───────────────────────

  defp synthesize_missing_portions(gram_ids, units_by_id) do
    unresolved_pairs(gram_ids)
    |> Enum.reduce(0, fn {ingredient_id, unit_id}, created ->
      unit_name = units_by_id |> Map.get(unit_id, %{}) |> Map.get(:name)

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
  defp synth_gram_weight(_ingredient_id, unit_name, _units_by_id)
       when is_map_key(@mass_grams_per_unit, unit_name),
       do: {:ok, Map.fetch!(@mass_grams_per_unit, unit_name)}

  defp synth_gram_weight(ingredient_id, unit_name, units_by_id)
       when is_map_key(@volume_ml_per_unit, unit_name) do
    case volume_anchor(ingredient_id, units_by_id) do
      {:ok, grams_per_ml} ->
        {:ok, grams_per_ml * Map.fetch!(@volume_ml_per_unit, unit_name)}

      :none ->
        :skip
    end
  end

  defp synth_gram_weight(_ingredient_id, _unit_name, _units_by_id), do: :skip

  # grams-per-millilitre from any existing volume portion of the ingredient.
  defp volume_anchor(ingredient_id, units_by_id) do
    volume_ids =
      for {id, u} <- units_by_id, is_map_key(@volume_ml_per_unit, u.name), do: id

    anchor =
      IngredientPortion
      |> where([ip], ip.ingredient_id == ^ingredient_id and ip.measurement_unit_id in ^volume_ids)
      |> where([ip], not is_nil(ip.gram_weight) and ip.gram_weight > 0.0)
      |> order_by([ip], asc: ip.id)
      |> limit(1)
      |> Repo.one()

    case anchor do
      nil ->
        :none

      %IngredientPortion{gram_weight: gw, amount: amount, measurement_unit_id: mu_id} ->
        ml = units_by_id |> Map.fetch!(mu_id) |> Map.get(:name) |> then(&@volume_ml_per_unit[&1])
        amount = if is_number(amount) and amount > 0, do: amount, else: 1.0
        {:ok, gw / amount / ml}
    end
  end

  defp insert_portion(ingredient_id, unit_id, gram_weight) do
    unless portion_exists?(ingredient_id, unit_id) do
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

  defp portion_exists?(ingredient_id, unit_id) do
    IngredientPortion
    |> where([ip], ip.ingredient_id == ^ingredient_id and ip.measurement_unit_id == ^unit_id)
    |> Repo.exists?()
  end

  # ── Report ──────────────────────────────────────────────────────────────────

  defp build_unresolved_report(gram_ids, units_by_id) do
    volume_ids =
      for {id, u} <- units_by_id, is_map_key(@volume_ml_per_unit, u.name), into: MapSet.new(), do: id

    unresolved_rows(gram_ids)
    |> Enum.group_by(fn r -> {r.ingredient_id, r.measurement_unit_id} end)
    |> Enum.map(fn {{ingredient_id, unit_id}, rows} ->
      unit = Map.get(units_by_id, unit_id, %{})
      unit_name = Map.get(unit, :name)

      reason =
        cond do
          is_map_key(@mass_grams_per_unit, unit_name) -> :no_anchor_portion
          MapSet.member?(volume_ids, unit_id) -> :no_anchor_portion
          true -> :no_conversion
        end

      %{
        ingredient_id: ingredient_id,
        ingredient_name: rows |> List.first() |> Map.get(:ingredient_name),
        measurement_unit_id: unit_id,
        unit_name: unit_name,
        reason: reason,
        row_count: length(rows),
        recipe_ids: rows |> Enum.map(& &1.recipe_id) |> Enum.uniq()
      }
    end)
    |> Enum.sort_by(& &1.row_count, :desc)
  end

  defp finalize(report) do
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
