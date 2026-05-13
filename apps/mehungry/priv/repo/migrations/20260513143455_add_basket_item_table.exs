defmodule Mehungry.Repo.Migrations.AddBasketItemTable do
  use Ecto.Migration

  def change do
    create table(:basket_items) do
      add :quantity, :float
      add :in_storage, :boolean
      add :name, :string
      add :shopping_basket_id, references(:shopping_baskets, on_delete: :delete_all)
      add :measurement_unit_id, references(:measurement_units, on_delete: :nothing)
      add :nutrition_data, :map
      add :usda_fdc_id, :integer
      add :recipe_id, references(:recipes, on_delete: :nothing)

      timestamps()
    end

    create index(:basket_items, [:shopping_basket_id])
    create index(:basket_items, [:measurement_unit_id])
  end
end
