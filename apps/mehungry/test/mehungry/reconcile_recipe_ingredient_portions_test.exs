defmodule Mehungry.ReconcileRecipeIngredientPortionsTest do
  use Mehungry.DataCase

  import Mehungry.{FoodFixtures, AccountsFixtures}

  import ExUnit.CaptureIO

  alias Mehungry.Repo
  alias Mehungry.ReconcileRecipeIngredientPortions, as: Reconcile
  alias Mehungry.Food.{IngredientPortion, RecipeIngredient}

  # Inserts a recipe_ingredient bypassing the changeset so we can seed the exact
  # (ingredient_portion_id) state a legacy row would have — the changeset would
  # otherwise auto-resolve it.
  defp seed_ri(recipe, ingredient, unit, portion_id) do
    Repo.insert!(%RecipeIngredient{
      recipe_id: recipe.id,
      ingredient_id: ingredient.id,
      measurement_unit_id: unit.id,
      ingredient_portion_id: portion_id,
      quantity: 2.0
    })
  end

  defp seed_portion(ingredient, unit, gram_weight) do
    Repo.insert!(%IngredientPortion{
      ingredient_id: ingredient.id,
      measurement_unit_id: unit.id,
      gram_weight: gram_weight,
      amount: 1.0
    })
  end

  setup do
    user = user_fixture()
    recipe = recipe_fixture(user)

    %{
      recipe: recipe,
      gram_unit: measurement_unit_fixture(%{name: "gram"}),
      cup: measurement_unit_fixture(%{name: "cup"}),
      oz: measurement_unit_fixture(%{name: "oz"}),
      slice: measurement_unit_fixture(%{name: "slice"})
    }
  end

  test "links resolvable rows, synthesizes mass/volume portions, reports the rest", ctx do
    # Bucket 1: already linked — must be left untouched.
    already = ingredient_fixture()
    already_portion = seed_portion(already, ctx.cup, 240.0)
    ri_already = seed_ri(ctx.recipe, already, ctx.cup, already_portion.id)

    # Bucket 2: resolvable — portion exists but the row isn't linked yet.
    resolvable = ingredient_fixture()
    resolvable_portion = seed_portion(resolvable, ctx.cup, 250.0)
    ri_resolvable = seed_ri(ctx.recipe, resolvable, ctx.cup, nil)

    # Bucket 3a: synthesizable mass unit — no portion at all.
    mass = ingredient_fixture()
    ri_mass = seed_ri(ctx.recipe, mass, ctx.oz, nil)

    # Bucket 3b: synthesizable volume unit — has a cup anchor, needs a new one.
    #            (uses `oz`? no — use a second volume unit via the cup anchor)
    volume = ingredient_fixture()
    _anchor = seed_portion(volume, ctx.cup, 120.0)
    tbsp = measurement_unit_fixture(%{name: "tablespoon"})
    ri_volume = seed_ri(ctx.recipe, volume, tbsp, nil)

    # Bucket 4: unfixable — unit has no conversion and no portion.
    unfixable = ingredient_fixture()
    ri_unfixable = seed_ri(ctx.recipe, unfixable, ctx.slice, nil)

    capture_io(fn -> send(self(), {:report, Reconcile.run()}) end)
    report = receive_report()

    # Already-linked row is unchanged.
    assert Repo.get!(RecipeIngredient, ri_already.id).ingredient_portion_id ==
             already_portion.id

    # Resolvable row is now linked to the existing portion.
    assert Repo.get!(RecipeIngredient, ri_resolvable.id).ingredient_portion_id ==
             resolvable_portion.id

    # Mass row: a portion was synthesized (grams-per-oz) and the row linked to it.
    mass_ri = Repo.get!(RecipeIngredient, ri_mass.id)
    assert mass_ri.ingredient_portion_id
    mass_portion = Repo.get!(IngredientPortion, mass_ri.ingredient_portion_id)
    assert mass_portion.measurement_unit_id == ctx.oz.id
    assert_in_delta mass_portion.gram_weight, 28.3495, 0.001

    # Volume row: derived from the cup anchor (120 g / cup → 7.5 g / tbsp).
    volume_ri = Repo.get!(RecipeIngredient, ri_volume.id)
    assert volume_ri.ingredient_portion_id
    volume_portion = Repo.get!(IngredientPortion, volume_ri.ingredient_portion_id)
    assert volume_portion.measurement_unit_id == tbsp.id
    assert_in_delta volume_portion.gram_weight, 7.5, 0.001

    # Unfixable row stays NULL and is reported for review.
    assert Repo.get!(RecipeIngredient, ri_unfixable.id).ingredient_portion_id == nil

    assert [entry] =
             Enum.filter(report.unresolved, &(&1.ingredient_id == unfixable.id))

    assert entry.measurement_unit_id == ctx.slice.id
    assert entry.reason == :no_conversion
    assert entry.row_count == 1
    assert ctx.recipe.id in entry.recipe_ids

    assert report.backfilled >= 3
    assert report.synthesized_portions >= 2
  end

  test "dry_run writes nothing", ctx do
    resolvable = ingredient_fixture()
    seed_portion(resolvable, ctx.cup, 250.0)
    ri = seed_ri(ctx.recipe, resolvable, ctx.cup, nil)

    portion_count_before = Repo.aggregate(IngredientPortion, :count)

    capture_io(fn -> send(self(), {:report, Reconcile.run(dry_run: true)}) end)
    report = receive_report()

    assert report.dry_run
    assert Repo.get!(RecipeIngredient, ri.id).ingredient_portion_id == nil
    assert Repo.aggregate(IngredientPortion, :count) == portion_count_before
    assert report.backfilled == 0
    assert report.synthesized_portions == 0
  end

  defp receive_report do
    receive do
      {:report, report} -> report
    after
      0 -> flunk("reconciliation did not return a report")
    end
  end
end
