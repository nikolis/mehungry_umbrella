defmodule Mehungry.Repo.Migrations.AddInstagramTokenToUser do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :instagram_token, :map, default: %{}
      add :facebook_token, :map, default: %{}
    end
  end
end
