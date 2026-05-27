defmodule Mehungry.Subscriptions do
  @moduledoc """
  Manages user subscription tiers and AI feature quota enforcement.

  Tiers: "free" (3 recipe / 0 meal_plan per month),
         "pro"  (15 recipe / 4 meal_plan per month).
  """

  import Ecto.Query
  alias Mehungry.Repo
  alias Mehungry.Subscriptions.{UserSubscription, AiUsage}

  @monthly_limits %{
    "free" => %{"recipe_generation" => 0, "meal_plan" => 0},
    "pro"  => %{"recipe_generation" => 15, "meal_plan" => 4}
  }

  # ── Subscription ──────────────────────────────────────────────────────────────

  def get_subscription(user_id) do
    case Repo.get_by(UserSubscription, user_id: user_id) do
      nil -> %UserSubscription{user_id: user_id, tier: "free", status: "active"}
      sub -> sub
    end
  end

  def upsert_subscription(user_id, attrs) do
    case Repo.get_by(UserSubscription, user_id: user_id) do
      nil ->
        %UserSubscription{}
        |> UserSubscription.changeset(Map.put(attrs, :user_id, user_id))
        |> Repo.insert()

      existing ->
        existing
        |> UserSubscription.changeset(attrs)
        |> Repo.update()
    end
  end

  def activate_pro(user_id, stripe_customer_id, stripe_subscription_id, period_end) do
    upsert_subscription(user_id, %{
      tier: "pro",
      status: "active",
      stripe_customer_id: stripe_customer_id,
      stripe_subscription_id: stripe_subscription_id,
      period_start: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      period_end: period_end
    })
  end

  def cancel_subscription(stripe_subscription_id) do
    case Repo.get_by(UserSubscription, stripe_subscription_id: stripe_subscription_id) do
      nil ->
        {:error, :not_found}

      sub ->
        sub
        |> UserSubscription.changeset(%{tier: "free", status: "canceled"})
        |> Repo.update()
    end
  end

  def update_subscription_status(stripe_subscription_id, status, period_end \\ nil) do
    case Repo.get_by(UserSubscription, stripe_subscription_id: stripe_subscription_id) do
      nil ->
        {:error, :not_found}

      sub ->
        attrs =
          if period_end do
            %{status: status, period_end: period_end}
          else
            %{status: status}
          end

        sub |> UserSubscription.changeset(attrs) |> Repo.update()
    end
  end

  @owner_email "nikolisgal@gmail.com"

  # ── Quota ─────────────────────────────────────────────────────────────────────

  @doc """
  Returns :ok if the user has remaining quota for feature this month,
  or {:error, :quota_exceeded}.
  """
  def check_quota(user_id, feature) do
    user = Mehungry.Accounts.get_user!(user_id)

    if user.email == @owner_email do
      :ok
    else
      subscription = get_subscription(user_id)
      limit = monthly_limit(subscription.tier, feature)

      cond do
        limit == 0 ->
          {:error, :quota_exceeded}

        get_usage_this_month(user_id, feature) < limit ->
          :ok

        true ->
          {:error, :quota_exceeded}
      end
    end
  end

  @doc "Records one use of a feature for the user."
  def record_usage(user_id, feature) do
    %AiUsage{}
    |> AiUsage.changeset(%{
      user_id: user_id,
      feature: feature,
      used_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    })
    |> Repo.insert()
  end

  @doc "How many times a user has used a feature in the current calendar month."
  def get_usage_this_month(user_id, feature) do
    start_of_month = Date.beginning_of_month(Date.utc_today())
    {:ok, start_dt} = NaiveDateTime.new(start_of_month, ~T[00:00:00])

    Repo.one(
      from u in AiUsage,
        where:
          u.user_id == ^user_id and
            u.feature == ^feature and
            u.used_at >= ^start_dt,
        select: count(u.id)
    )
  end

  @doc "Returns {used, limit} for a user+feature this month."
  def quota_status(user_id, feature) do
    subscription = get_subscription(user_id)
    limit = monthly_limit(subscription.tier, feature)
    used = if limit > 0, do: get_usage_this_month(user_id, feature), else: 0
    {used, limit}
  end

  def monthly_limit(tier, feature) do
    @monthly_limits
    |> Map.get(tier, @monthly_limits["free"])
    |> Map.get(feature, 0)
  end

  def pro?(user_id) do
    get_subscription(user_id).tier == "pro"
  end

  @doc "Returns a map of %{user_id => UserSubscription} for all users that have a subscription row."
  def subscriptions_by_user_id do
    Repo.all(UserSubscription)
    |> Map.new(fn sub -> {sub.user_id, sub} end)
  end
end
