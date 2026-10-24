defmodule Mehungry.Food.Recipe do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Accounts.User
  alias Mehungry.Languages.Language

  schema "recipes" do
    field :author, :string
    field :cooking_time_lower_limit, :integer
    field :cooking_time_upper_limit, :integer
    field :cousine, :string
    field :description, :string
    field :list_image_url, :string
    field :image_url, :string
    field :detail_image_url, :string
    field :recipe_image_remote, :string
    field :original_url, :string
    # Provenance marker: "myplate" for USDA MyPlate imports, nil for in-app
    # (user/AI/bot) recipes. Lets imported batches be group-managed. See
    # Food.Recipes source helpers and docs/food/myplate_import.md.
    field :source, :string
    # Content license notice for imported recipes that carry a reuse obligation
    # (e.g. "CC BY-SA 4.0" for UniTools). nil for public-domain/in-app recipes.
    # Rendered next to the "Source" credit on the Steps tab to satisfy
    # ShareAlike's visible-license requirement. See docs/food/unitools_import.md.
    field :license, :string
    field :preperation_time_lower_limit, :integer
    field :preperation_time_upper_limit, :integer
    field :primary_nutrients_size, :integer
    field :servings, :integer
    field :private, :boolean
    field :title, :string
    field :difficulty, :integer, default: 1
    field :nutrients, :map, default: %{}
    # Derived per-serving nutrient claims written by Recipes.put_nutrient_info/2
    # alongside :nutrients (see Food.NutrientClaims). Each element reloads as
    # %{"nutrient" => _, "level" => "high"|"source", "percent_nrv" => int}.
    # Derived-only — never cast from user params.
    field :badges, {:array, :map}, default: []
    # pgvector column created by 20260622000001_add_pgvector_and_recipe_embeddings.exs;
    # written by RecipeEmbeddingWorker, read by Search.RecipeVectorSearch.
    field :embedding, Pgvector.Ecto.Vector
    # Populated by Recipes.search_recipes_for_admin/2 for the admin recipes tab.
    field :ingredient_count, :integer, virtual: true

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
          Enum.map(attrs["recipe_hashtags"], fn
            %{"hashtag_id" => _} = x ->
              x

            x ->
              title = x.hashtag.title
              existing = Mehungry.Hashtag.get_hashtag_by_title(title)

              case is_nil(existing) do
                true -> x
                false -> %{"hashtag_id" => existing.id}
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
      :preperation_time_upper_limit,
      :preperation_time_lower_limit,
      :cooking_time_upper_limit,
      :cooking_time_lower_limit,
      :description,
      :nutrients,
      :image_url,
      :original_url,
      :source,
      :license,
      :detail_image_url,
      :user_id,
      :language_name,
      :difficulty
    ])
    |> unique_constraint(:title,
      name: :title_user_index,
      message: "you already have a recipe with this title"
    )
    |> foreign_key_constraint(:language_name, name: :recipes_language_name_fkey)
    |> foreign_key_constraint(:language_id)
    |> foreign_key_constraint(:user_id)
    |> validate_required([
      :title,
      :language_name,
      :user_id,
      :cooking_time_lower_limit,
      :preperation_time_lower_limit
    ])
    |> cast_embed(:steps, sort_param: :steps_sort, drop_param: :steps_drop)
    |> cast_assoc(:recipe_ingredients,
      required: true,
      sort_param: :recipe_ingredients_sort,
      drop_param: :recipe_ingredients_drop
    )
    |> cast_assoc(:recipe_hashtags, required: false)
  end
end
