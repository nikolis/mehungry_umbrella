defmodule Mehungry.Repo.Migrations.AddMeasurementUnitInBasketIngredients do
  use Ecto.Migration

  def change do
    alter table(:basket_ingredients) do
      add :measurement_unit_id, references(:measurement_units, on_delete: :nothing)
    end

    create index(:basket_ingredients, [:measurement_unit_id])
  end
end
