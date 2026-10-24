defmodule Mehungry.IngredientUserMealPutNutrientsWorker do
  @moduledoc """
  Backfills the denormalized `nutrients` tree on a single `IngredientUserMeal`,
  the ingredient-meal analogue of `Mehungry.RecipePutNutrientsWorker`. Enqueued in
  bulk by `Mehungry.History.start_ingredient_nutrient_backfill/0` to populate rows
  that predate the write-time hook (and to refresh rows after a catalog change).
  """
  use Oban.Worker, max_attempts: 3

  alias Mehungry.History
  alias Mehungry.History.IngredientUserMeal
  alias Mehungry.Food.NutrientCalculation
  alias Mehungry.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ingredient_user_meal_id" => id}}) do
    case Repo.get(IngredientUserMeal, id) do
      # A row deleted between enqueue and run is not an error — retrying won't help.
      nil ->
        :ok

      ium ->
        ium =
          Repo.preload(ium,
            ingredient: [:ingredient_portions, ingredient_nutrients: [nutrient: :measurement_unit]]
          )

        tree = History.scaled_ingredient_nutrient_tree(ium, NutrientCalculation.gram_unit_ids())

        ium
        |> Ecto.Changeset.change(nutrients: tree)
        |> Repo.update()
    end
  end
end
