defmodule Mehungry.Repo.Migrations.AddLanguageNameToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :language_name, :string, null: true
    end

    create index(:posts, [:reference_id, :language_name])
  end
end
