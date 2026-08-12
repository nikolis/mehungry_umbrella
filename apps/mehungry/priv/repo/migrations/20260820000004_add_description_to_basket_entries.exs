defmodule Mehungry.Repo.Migrations.AddDescriptionToBasketEntries do
  use Ecto.Migration

  # Free-text label carried when a recipe ingredient uses a description-only
  # portion (a USDA "undetermined" unit, e.g. "1 medium banana") and therefore
  # has no measurement unit to convert into the basket.
  def change do
    alter table(:basket_ingredients) do
      add :description, :string
    end

    alter table(:basket_items) do
      add :description, :string
    end
  end
end
