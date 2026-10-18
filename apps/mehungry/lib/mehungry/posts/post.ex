defmodule Mehungry.Posts.Post do
  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Posts.Comment
  alias Mehungry.Posts.Comment
  alias Mehungry.Posts.PostUpvote
  alias Mehungry.Posts.PostDownvote

  schema "posts" do
    field :bg_media_url, :string
    field :description, :string
    field :md_media_url, :string
    field :reference_url, :string
    field :sm_media_url, :string
    field :title, :string
    field :type_, :string
    field :language_name, :string

    belongs_to :user, Mehungry.Accounts.User
    belongs_to :recipe, Mehungry.Food.Recipe
    belongs_to :reference, Mehungry.Food.Recipe
    belongs_to :weekly_plan_graphic, Mehungry.Food.WeeklyPlanGraphic
    belongs_to :published_meal_plan, Mehungry.PublishedPlans.PublishedMealPlan

    has_many :comments, Comment
    has_many :upvotes, PostUpvote
    has_many :downvotes, PostDownvote

    timestamps()
  end

  @doc false
  def changeset(post, attrs) do
    post
    |> cast(attrs, [
      :type_,
      :user_id,
      :reference_id,
      :weekly_plan_graphic_id,
      :published_meal_plan_id,
      :title,
      :reference_url,
      :sm_media_url,
      :md_media_url,
      :bg_media_url,
      :description,
      :language_name
    ])
    |> validate_required([:type_, :title, :md_media_url])
    |> validate_type_reference()
  end

  # A recipe post points at a recipe (`reference_id`); a weekly-plan post points at
  # a `weekly_plan_graphic` and carries its author. Each kind requires its own
  # link, so a reference-less recipe post (or a plan post with no graphic) is
  # rejected rather than silently rendering wrong in the feed.
  defp validate_type_reference(changeset) do
    case get_field(changeset, :type_) do
      "WEEKLY_PLAN" -> validate_required(changeset, [:user_id, :weekly_plan_graphic_id])
      _ -> validate_required(changeset, [:reference_id])
    end
  end
end
