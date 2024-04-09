defmodule MehungryServer.Repo.Migrations.CreateIngredients do
  use Ecto.Migration

  def change do
    create table(:ingredients) do
      add :url, :string
      add :name, :string
      add :food_class, :string
      add :category_id, references(:categories, on_delete: :nothing)
      add :measurement_unit_id, references(:measurement_units, on_delete: :nothing)

      timestamps()
    end

    create index(:ingredients, [:category_id])
    create index(:ingredients, [:measurement_unit_id])
    create unique_index(:ingredients, [:name])
  end
end
