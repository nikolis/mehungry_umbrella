defmodule Mehungry.Repo.Migrations.AddHashtagsTable do
  use Ecto.Migration

  def change do
    create table(:hashtags) do
      add :title, :string
    end

    create unique_index(:hashtags, [:title])
  end
end
