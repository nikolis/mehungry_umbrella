defmodule Mehungry.Repo.Migrations.AdditionsToIngredientTable do
  use Ecto.Migration

  def change do
    alter table(:ingredients) do
      add :food_class, :string
      add :nutrient_conversion_factors, {:array, :map}
      add :publication_date, :string
    end

    alter table(:measurement_units) do
      add :alternate_name, :string
    end

    alter table(:measurement_unit_translations) do
      add :alternate_name, :string
    end

    create unique_index(:categories, :name)
  end
end
