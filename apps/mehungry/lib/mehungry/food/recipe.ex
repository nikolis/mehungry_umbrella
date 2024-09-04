defmodule Mehungry.Food.Recipe do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Accounts.User
  alias Mehungry.Language
  alias Mehungry.Survey.Rating

  schema "recipes" do
    field :author, :string
    field :cooking_time_lower_limit, :integer
    field :cooking_time_upper_limit, :integer
    field :cousine, :string
    field :description, :string
    field :image_url, :string
    field :list_image_url, :string
    field :detail_image_url, :string
    field :recipe_image_remote, :string
    field :original_url, :string
    field :preperation_time_lower_limit, :integer
    field :preperation_time_upper_limit, :integer
    field :servings, :integer
    field :private, :boolean
    field :title, :string
    field :difficulty, :integer

    has_many :ratings, Rating
    has_one :post, Mehungry.Posts.Post

    belongs_to :user, User

    belongs_to :language, Language,
      references: :name,
      foreign_key: :language_name,
      type: :string

    has_many :recipe_ingredients, Mehungry.Food.RecipeIngredient, on_replace: :delete
    has_many :annotations, Mehungry.Food.Annotation

    embeds_many :steps, Mehungry.Food.Step

    timestamps()
  end

  @doc false
  def changeset(recipe, attrs) do
    recipe
    |> cast(attrs, [
      :recipe_image_remote,
      :servings,
      :private,
      :cousine,
      :title,
      :author,
      :original_url,
      :preperation_time_upper_limit,
      :preperation_time_lower_limit,
      :cooking_time_upper_limit,
      :cooking_time_lower_limit,
      :description,
      :image_url,
      :user_id,
      :language_name,
      :difficulty
    ])
    |> unique_constraint(:title_user_constraint, name: :title_user_index)
    |> foreign_key_constraint(:language_id)
    |> foreign_key_constraint(:user_id)
    |> validate_required([
      :title,
      :language_name,
      :user_id,
      :cooking_time_lower_limit,
      :preperation_time_lower_limit,
      :difficulty
    ])
    |> cast_embed(:steps, [:required_message])
    |> cast_assoc(:recipe_ingredients, required: true)
  end
end
