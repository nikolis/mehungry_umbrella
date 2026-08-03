defmodule Mehungry.Repo.Migrations.CreateConditionIdentifiers do
  use Ecto.Migration

  # Cross-database identity for a `Condition`, mirroring `compound_identifiers`.
  # Lets a PubTator disease mention (a MeSH id) resolve to one of our seeded
  # conditions instead of being carried around as a bare string. Looked up and
  # deduplicated by `(namespace, identifier)`.
  def change do
    create table(:condition_identifiers) do
      add :condition_id, references(:conditions, on_delete: :delete_all), null: false
      add :namespace, :string, null: false
      add :identifier, :string, null: false
      add :is_primary, :boolean, null: false, default: false
      add :source, :string

      timestamps()
    end

    create unique_index(:condition_identifiers, [:namespace, :identifier])
    create index(:condition_identifiers, [:condition_id])
  end
end
