defmodule Mehungry.Hashtag do
  @moduledoc """
  Hash tag str.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  schema "hashtags" do
    field :title, :string

    has_many :recipe_hashtags, Mehungry.Food.RecipeHashtag
  end

  @doc false
  def changeset(hashtag, attrs) do
    hashtag
    |> cast(attrs, [
      :title
    ])
    |> validate_required([:title])
    # The DB enforces a unique index on title (tags are deduped by text and
    # reused across recipes). Reflect it here so the get-or-create path in
    # `Recipes.ensure_recipe_hashtags/1` surfaces a changeset error on a race
    # instead of a raw DB exception.
    |> unique_constraint(:title)
  end

  def get_hashtag_by_title(title) do
    Mehungry.Repo.one(from tag in Mehungry.Hashtag, where: tag.title == ^title)
  end
end
