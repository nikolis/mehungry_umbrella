defmodule Mehungry.SocialMediaPosts.Instagram do
  @moduledoc """
  Records of Instagram posts made by users
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "social_media_posts_intagram" do
    field :resource_id, :integer
    field :type_, :string, default: "Recipe"

    belongs_to :user, Mehungry.Account.User

    timestamps()
  end

  def changeset(recipe, attrs) do
    recipe
    |> cast(attrs, [:resource_id, :user_id, :type_])
    |> validate_required([:resource_id, :user_id, :type_])
  end
end
