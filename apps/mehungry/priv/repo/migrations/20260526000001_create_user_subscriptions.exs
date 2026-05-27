defmodule Mehungry.Repo.Migrations.CreateUserSubscriptions do
  use Ecto.Migration

  def change do
    create table(:user_subscriptions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :tier, :string, null: false, default: "free"
      add :status, :string, null: false, default: "active"
      add :stripe_customer_id, :string
      add :stripe_subscription_id, :string
      add :period_start, :naive_datetime
      add :period_end, :naive_datetime

      timestamps()
    end

    create unique_index(:user_subscriptions, [:user_id])
    create index(:user_subscriptions, [:stripe_customer_id])
    create index(:user_subscriptions, [:stripe_subscription_id])
  end
end
