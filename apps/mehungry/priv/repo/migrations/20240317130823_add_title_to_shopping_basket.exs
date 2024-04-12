defmodule Mehungry.Repo.Migrations.AddTitleToShoppingBasket do
  use Ecto.Migration

  def change do
    alter table(:shopping_baskets) do
      add :title, :string
    end
  end
end
