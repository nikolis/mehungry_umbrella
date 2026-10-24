defmodule Mehungry.PublishedPlans.PublishedMealPlan do
  @moduledoc """
  An immutable, public snapshot of a user's calendar week, published to a
  crawlable `/meal-plans/:slug` page for SEO + sharing.

  Unlike the live calendar (private, `noindex`, WebSocket-driven) this is a
  self-contained copy taken at publish time: it never changes when the author
  later edits their calendar, and it carries no live PII — only the meal titles,
  recipe ids (so the page can link to `/browse/:id`), the truthful daily-average
  macro summary, an aggregated grocery list, and a deterministic prose summary.

  The numbers here are the *same* numbers the calendar shows, because the
  snapshot is built from `Mehungry.NutrientUtils.summarize_meals_nutrients/1` —
  the one shared function the calendar day/week headers use.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Accounts.User

  schema "published_meal_plans" do
    field :slug, :string
    field :title, :string
    field :goal_label, :string
    field :locale, :string
    field :week_start, :date

    field :days, {:array, :map}, default: []
    field :macros, :map, default: %{}
    field :grocery, {:array, :string}, default: []
    # Grocery list grouped into shopping aisles (see PublishedPlans.GroceryAisle);
    # each element is %{"aisle" => key, "label" => label, "items" => [item]} where
    # an item is %{"ingredient_id" => id | nil, "name" => name} — the id (nil for
    # free foods) lets the public page localize each entry by id, like the per-day
    # ingredient meals. `grocery` (flat names) is kept as a backward-compatible
    # fallback; legacy rows may still carry plain-string items (handled on read).
    field :grocery_groups, {:array, :map}, default: []
    field :summary_text, :string
    field :og_image_url, :string
    field :recipe_count, :integer, default: 0

    field :visibility, :string, default: "public"
    field :published_at, :utc_datetime

    belongs_to :user, User

    timestamps()
  end

  @castable [
    :user_id,
    :slug,
    :title,
    :goal_label,
    :locale,
    :week_start,
    :days,
    :macros,
    :grocery,
    :grocery_groups,
    :summary_text,
    :og_image_url,
    :recipe_count,
    :visibility,
    :published_at
  ]

  def changeset(plan, attrs) do
    plan
    |> cast(attrs, @castable)
    |> validate_required([:slug, :title, :days])
    |> validate_inclusion(:visibility, ["public", "private"])
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:user_id)
  end
end
