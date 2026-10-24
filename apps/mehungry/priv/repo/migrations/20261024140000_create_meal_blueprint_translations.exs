defmodule Mehungry.Repo.Migrations.CreateMealBlueprintTranslations do
  use Ecto.Migration

  def change do
    create table(:meal_blueprint_translations) do
      add :name, :string
      add :description, :text

      add :blueprint_id, references(:meal_blueprints, on_delete: :delete_all), null: false

      add :language_name,
          references(:languages, column: :name, type: :string, on_delete: :delete_all),
          null: false

      add :status, :string, default: "verified", null: false
      add :verified_at, :utc_datetime
      add :verified_by_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:meal_blueprint_translations, [:blueprint_id, :language_name])
    create index(:meal_blueprint_translations, [:language_name, :status])
  end
end
