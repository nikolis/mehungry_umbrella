defmodule Mehungry.Repo.Migrations.AddInsertedAtIndexToPosts do
  use Ecto.Migration

  # The feed loads its candidate window ordered by `inserted_at desc, id desc`
  # with a LIMIT. This composite index lets Postgres satisfy that ordered scan
  # directly instead of sorting the whole table.
  def change do
    create index(:posts, [:inserted_at, :id])
  end
end
