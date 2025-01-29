defmodule Mehungry.Food.Recipe do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Accounts.User
  alias Mehungry.Languages.Language
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
    field :primary_nutrients_size, :integer
    field :servings, :integer
    field :private, :boolean
    field :title, :string
    field :difficulty, :integer
    field :nutrients, :map, default: %{}

    has_many :ratings, Rating
    has_many :user_recipes, Mehungry.Accounts.UserRecipe
    has_one :post, Mehungry.Posts.Post

    belongs_to :user, User

    belongs_to :language, Language,
      references: :name,
      foreign_key: :language_name,
      type: :string

    has_many :recipe_ingredients, Mehungry.Food.RecipeIngredient, on_replace: :delete
    has_many :recipe_hashtags, Mehungry.Food.RecipeHashtag, on_replace: :nilify
    has_many :annotations, Mehungry.Food.Annotation
    has_many :comments, Mehungry.Posts.Comment

    embeds_many :steps, Mehungry.Food.Step

    timestamps()
  end

  defp get_hashtags(%{"recipe_hashtags" => _hashtags} = attrs) do
    %{
      attrs
      | "recipe_hashtags" =>
          Enum.map(attrs["recipe_hashtags"], fn x ->
            title = x.hashtag.title
            existing = Mehungry.Hashtag.get_hashtag_by_title(title)

            case is_nil(existing) do
              true ->
                x

              false ->
                %{hashtag: %{id: existing.id}}
            end
          end)
    }
  end

  defp get_hashtags(attrs) do
    attrs
  end

  @doc false
  def changeset(recipe, attrs) do
    attrs = get_hashtags(attrs)

    recipe
    |> cast(attrs, [
      :recipe_image_remote,
      :servings,
      :primary_nutrients_size,
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
      :nutrients,
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
    |> cast_assoc(:recipe_hashtags, required: false)
  end
end
