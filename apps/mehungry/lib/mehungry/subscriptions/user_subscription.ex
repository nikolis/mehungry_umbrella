defmodule Mehungry.Subscriptions.UserSubscription do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "user_subscriptions" do
    field :tier, :string, default: "free"
    field :status, :string, default: "active"
    field :stripe_customer_id, :string
    field :stripe_subscription_id, :string
    field :period_start, :naive_datetime
    field :period_end, :naive_datetime

    belongs_to :user, Mehungry.Accounts.User

    timestamps()
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :user_id,
      :tier,
      :status,
      :stripe_customer_id,
      :stripe_subscription_id,
      :period_start,
      :period_end
    ])
    |> validate_required([:user_id, :tier, :status])
    |> validate_inclusion(:tier, ["free", "pro"])
    |> validate_inclusion(:status, ["active", "canceled", "past_due", "trialing"])
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end
end
