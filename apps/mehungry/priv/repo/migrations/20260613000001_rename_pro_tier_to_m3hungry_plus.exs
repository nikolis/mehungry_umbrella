defmodule Mehungry.Repo.Migrations.RenameProTierToM3hungryPlus do
  use Ecto.Migration

  def up do
    execute("UPDATE user_subscriptions SET tier = 'm3hungry_plus' WHERE tier = 'pro'")
  end

  def down do
    execute("UPDATE user_subscriptions SET tier = 'pro' WHERE tier = 'm3hungry_plus'")
  end
end
