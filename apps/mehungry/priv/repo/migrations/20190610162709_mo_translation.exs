defmodule MehungryServer.Repo.Migrations.MoTranslation do
  use Ecto.Migration

  def change do
    create table(:measurement_unit_translations) do
      add :name, :string
      add :alternate_name, :string

      add :measurement_unit_id, references(:measurement_units, on_delete: :delete_all)

      add :language_name,
          references(:languages, column: :name, type: :string, on_delete: :delete_all)

      timestamps()
    end

    create unique_index(:measurement_unit_translations, [:name])
  end
end
