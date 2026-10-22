defmodule Mehungry.Repo.Migrations.CreateIngredientPortionTranslations do
  use Ecto.Migration

  def change do
    create table(:ingredient_portion_translations) do
      add :description, :string

      add :ingredient_portion_id, references(:ingredient_portions, on_delete: :delete_all),
        null: false

      add :language_name,
          references(:languages, column: :name, type: :string, on_delete: :delete_all),
          null: false

      add :status, :string, default: "verified", null: false
      add :verified_at, :utc_datetime
      add :verified_by_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:ingredient_portion_translations, [:ingredient_portion_id, :language_name])
    create index(:ingredient_portion_translations, [:language_name, :status])
  end
end
