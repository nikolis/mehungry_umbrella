defmodule Mehungry.Repo.Migrations.CreateConditionTranslations do
  use Ecto.Migration

  def change do
    create table(:condition_translations) do
      add :name, :string
      add :description, :text

      add :condition_id, references(:conditions, on_delete: :delete_all), null: false

      add :language_name,
          references(:languages, column: :name, type: :string, on_delete: :delete_all),
          null: false

      add :status, :string, default: "verified", null: false
      add :verified_at, :utc_datetime
      add :verified_by_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:condition_translations, [:condition_id, :language_name])
    create index(:condition_translations, [:language_name, :status])
  end
end
