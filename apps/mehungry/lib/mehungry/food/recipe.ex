defmodule Mehungry.Food.Recipe do
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Food.RecipeIngredient
  alias Mehungry.Food.Step
  alias Mehungry.Accounts.User
  alias Mehungry.Language

  schema "recipes" do
    field :author, :string
    field :cooking_time_lower_limit, :integer
    field :cooking_time_upper_limit, :integer
    field :cousine, :string
    field :description, :string
    field :image_url, :string
    field :recipe_image_remote, :string
    field :original_url, :string
    field :preperation_time_lower_limit, :integer
    field :preperation_time_upper_limit, :integer
    field :servings, :integer
    field :private, :boolean
    field :title, :string

    belongs_to :user, User

    belongs_to :language, Mehungry.Language,
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
      :language_name
    ])
    |> unique_constraint(:title_user_constraint, name: :title_user_index)
    |> foreign_key_constraint(:language_id)
    |> foreign_key_constraint(:user_id)
    |> validate_required([:title, :language_name])
    |> cast_embed(:steps, [:required_message])
    |> cast_assoc(:recipe_ingredients, with: &RecipeIngredient.changeset/2, required: true)
  end
end
