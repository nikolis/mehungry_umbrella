defmodule Mehungry.Repo.Migrations.DropFriendsTables do
  use Ecto.Migration

  # The Friends concept (symmetric friend graph + friends-only ingredient
  # sharing) was removed from the product. Drop its tables. Irreversible — the
  # feature is gone, there is nothing to restore to.
  def up do
    drop_if_exists table(:friendships)
    drop_if_exists table(:friend_requests)
  end

  def down do
    raise Ecto.MigrationError, message: "Cannot reverse dropping the removed Friends tables"
  end
end
