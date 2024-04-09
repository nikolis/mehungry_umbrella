defmodule Mehungry.Repo.Migrations.CreateIngredientPortionsTable do
  use Ecto.Migration

  def change do
    create table(:ingredient_portions) do
      add :amount, :float
      add :value, :float
      add :gram_weight, :float
      add :reference_id, :integer
      add :min_year_acquired, :integer
      add :sequence_number, :integer

      add :ingredient_id, references(:ingredients)
      add :measurement_unit_id, references(:measurement_units)

      timestamps()
    end
  end
end
