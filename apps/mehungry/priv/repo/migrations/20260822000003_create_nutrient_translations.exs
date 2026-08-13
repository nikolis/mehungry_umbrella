defmodule Mehungry.Repo.Migrations.CreateNutrientTranslations do
  use Ecto.Migration

  def change do
    create table(:nutrient_translations) do
      add :name, :string
      add :alternate_name, :string
      add :description, :text

      add :nutrient_id, references(:nutrients, on_delete: :delete_all), null: false

      add :language_name,
          references(:languages, column: :name, type: :string, on_delete: :delete_all),
          null: false

      add :status, :string, default: "verified", null: false
      add :verified_at, :utc_datetime
      add :verified_by_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:nutrient_translations, [:nutrient_id, :language_name])
    create index(:nutrient_translations, [:language_name, :status])
  end
end
