defmodule Mehungry.FoodProducts.FoodProduct do
  @moduledoc """
  A retail food product identified by its GTIN/EAN barcode, sourced from
  Open Food Facts. `nutriments` holds the raw OFF nutriment map (JSONB);
  the known `_100g` subset is exposed through accessor functions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @barcode_format ~r/^\d{8,14}$/

  @match_statuses ~w(unmatched auto manual rejected unmatched_reviewed)

  schema "food_products" do
    field :barcode, :string
    field :name, :string
    field :brands, :string
    field :quantity, :string
    field :countries, {:array, :string}, default: []
    field :categories_tags, {:array, :string}, default: []
    field :nutriments, :map, default: %{}
    field :image_url, :string
    field :image_small_url, :string
    field :nutriscore_grade, :string
    field :ecoscore_grade, :string
    field :completeness, :float
    field :off_last_modified_t, :integer
    field :data_source, :string, default: "open_food_facts"
    field :ingredient_match_score, :float
    field :ingredient_match_status, :string, default: "unmatched"

    belongs_to :ingredient, Mehungry.Food.Ingredient

    has_many :translations, Mehungry.FoodProducts.FoodProductTranslation

    timestamps()
  end

  def changeset(food_product, attrs) do
    food_product
    |> cast(attrs, [
      :barcode,
      :name,
      :brands,
      :quantity,
      :countries,
      :categories_tags,
      :nutriments,
      :image_url,
      :image_small_url,
      :nutriscore_grade,
      :ecoscore_grade,
      :completeness,
      :off_last_modified_t,
      :data_source,
      :ingredient_id,
      :ingredient_match_score,
      :ingredient_match_status
    ])
    |> validate_required([:barcode])
    |> validate_format(:barcode, @barcode_format)
    |> validate_inclusion(:ingredient_match_status, @match_statuses)
    |> unique_constraint(:barcode)
  end

  def barcode_format, do: @barcode_format

  def match_statuses, do: @match_statuses

  @doc "Energy in kcal per 100g, or nil when OFF has no data."
  def kcal_100g(%__MODULE__{nutriments: n}), do: nutriment(n, "energy-kcal_100g")

  @doc """
  A named macro per 100g: `:fat`, `:saturated_fat`, `:carbohydrates`,
  `:sugars`, `:proteins`, `:fiber`, `:salt` or `:sodium`.
  """
  def macro_100g(%__MODULE__{nutriments: n}, macro) do
    key =
      case macro do
        :fat -> "fat_100g"
        :saturated_fat -> "saturated-fat_100g"
        :carbohydrates -> "carbohydrates_100g"
        :sugars -> "sugars_100g"
        :proteins -> "proteins_100g"
        :fiber -> "fiber_100g"
        :salt -> "salt_100g"
        :sodium -> "sodium_100g"
      end

    nutriment(n, key)
  end

  defp nutriment(nutriments, key) when is_map(nutriments) do
    case Map.get(nutriments, key) do
      value when is_number(value) -> value
      _ -> nil
    end
  end

  defp nutriment(_, _), do: nil
end
