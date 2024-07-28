defmodule Mehungry.Repo.Migrations.CreateBasketIngredients do
  use Ecto.Migration

  def change do
    create table(:basket_ingredients) do
      add :quantity, :float
      add :in_storage, :boolean
      add :ingredient_id, references(:ingredients, on_delete: :nothing)
      add :shopping_basket_id, references(:shopping_baskets, on_delete: :delete_all)
      add :measurement_unit_id, references(:measurement_units, on_delete: :nothing)


      timestamps()
    end

    create index(:basket_ingredients, [:ingredient_id])
    create index(:basket_ingredients, [:shopping_basket_id])
    create index(:basket_ingredients, [:measurement_unit_id])

  end
end
