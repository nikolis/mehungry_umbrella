defmodule Mehungry.Food.WeeklyPlanGraphic do
  @moduledoc """
  A shareable social-media card generated from a user's calendar week: a
  deterministic, fully-SVG parchment card showing the 7-day meal grid, the week's
  truthful daily-average macro donut, and the m3hungry wordmark.

  Unlike `RecipeSocialGraphic`, nothing here is AI-authored and there is no base
  photo — the card is drawn entirely from the calendar data the user already sees,
  so the numbers on the card are exactly the numbers on the calendar
  (`Mehungry.NutrientUtils.macro_summary/1`). One user may have several over time
  (regeneration / different weeks); the newest row for a `(user, week)` is what the
  share UI offers. `macros` snapshots the daily-average summary used for the post
  caption and any API consumer.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Accounts.User

  schema "weekly_plan_graphics" do
    field :week_start, :date
    field :locale, :string
    field :goal_label, :string
    field :image_url, :string
    field :macros, :map
    field :caption, :string

    belongs_to :user, User

    timestamps(updated_at: false)
  end

  def changeset(graphic, attrs) do
    graphic
    |> cast(attrs, [:user_id, :week_start, :locale, :goal_label, :image_url, :macros, :caption])
    |> validate_required([:user_id, :week_start, :image_url])
    |> foreign_key_constraint(:user_id)
  end
end
