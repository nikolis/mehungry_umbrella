defmodule Mehungry.Repo.Migrations.CreateMealBlueprints do
  use Ecto.Migration

  def change do
    create table(:meal_blueprints) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # Optional disease/condition scoping the whole blueprint (applies to all
      # days/meals); nilify if the condition is later deleted.
      add :condition_id, references(:conditions, on_delete: :nilify_all)
      add :name, :string, null: false
      add :description, :text
      # Blueprint-level "general" targets (apply across every day): nutrient +
      # bioactive-compound names sourced from the DB via the picker (each with a
      # required and an avoid list), plus free-text preferred foods.
      add :required_nutrients, {:array, :string}, default: [], null: false
      add :avoid_nutrients, {:array, :string}, default: [], null: false
      add :required_compounds, {:array, :string}, default: [], null: false
      add :avoid_compounds, {:array, :string}, default: [], null: false
      add :preferred_foods, {:array, :string}, default: [], null: false

      timestamps()
    end

    create index(:meal_blueprints, [:user_id])
    create index(:meal_blueprints, [:condition_id])

    create table(:meal_blueprint_days) do
      add :blueprint_id, references(:meal_blueprints, on_delete: :delete_all), null: false
      add :day_index, :integer, null: false
      add :total_calorie_target, :integer

      timestamps()
    end

    create index(:meal_blueprint_days, [:blueprint_id])
    create unique_index(:meal_blueprint_days, [:blueprint_id, :day_index])

    create table(:meal_blueprint_meals) do
      add :blueprint_day_id, references(:meal_blueprint_days, on_delete: :delete_all), null: false
      add :meal_type, :string, null: false
      add :protein_min_g, :float
      add :protein_max_g, :float
      add :sugar_max_g, :float
      add :carbs_max_g, :float
      add :note, :text

      timestamps()
    end

    create index(:meal_blueprint_meals, [:blueprint_day_id])
    create unique_index(:meal_blueprint_meals, [:blueprint_day_id, :meal_type])
  end
end
