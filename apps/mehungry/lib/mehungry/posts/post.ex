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
    field :reference_id, :integer
    field :reference_url, :string
    field :sm_media_url, :string
    field :title, :string
    field :type_, :string

    belongs_to :user, Mehungry.Accounts.User
    belongs_to :recipe, Mehungry.Food.Recipe

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
      :reference_id,
      :title,
      :reference_url,
      :sm_media_url,
      :md_media_url,
      :bg_media_url,
      :description
    ])
    |> validate_required([:type_, :reference_id, :title, :md_media_url])
  end
end
