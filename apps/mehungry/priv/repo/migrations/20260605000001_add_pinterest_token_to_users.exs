defmodule Mehungry.Repo.Migrations.AddPinterestTokenToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :pinterest_token, :map, default: %{}
    end
  end
end
