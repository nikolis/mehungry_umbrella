defmodule Mehungry.Repo.Migrations.AddSubcategoryToConditions do
  use Ecto.Migration

  # A finer taxonomy hop under `category` — e.g. category "Endocrine" →
  # subcategory "Diabetes", category "Digestive" → subcategory "Liver Disease".
  # Optional, like `category`; indexed so conditions can be filtered by it.
  def change do
    alter table(:conditions) do
      add :subcategory, :string
    end

    create index(:conditions, [:subcategory])
  end
end
