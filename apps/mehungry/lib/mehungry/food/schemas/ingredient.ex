defmodule Mehungry.Food.Ingredient do
  @moduledoc false
  alias Mehungry.Food.{IngredientPortion, IngredientNutrient}

  use Ecto.Schema
  import Ecto.Changeset

  schema "ingredients" do
    field :description, :string
    field :name, :string
    field :url, :string
    # Add this line
    field :search_name, :string

    field :food_class, :string
    field :data_type, :string
    field :fdc_id, :integer
    field :ndb_number, :integer
    # Monotonic reconciliation counter, bumped by IngredientReconciliationWorker.
    field :version, :integer, default: 0
    field :nutrient_conversion_factors, {:array, :map}, default: []
    field :publication_date, :string
    field :nutrient_data_source, :string

    belongs_to :category, Mehungry.Food.Category
    belongs_to :measurement_unit, Mehungry.Food.MeasurementUnit

    # Owner of a private, user-created ingredient. NULL for the shared/global
    # USDA + admin-created catalog. Visibility scoping lives in the search layer.
    belongs_to :user, Mehungry.Accounts.User

    # `on_replace: :delete` so the admin form (see ProfessionalLive.Ingredients*)
    # can remove a row via cast_assoc's `drop_param` and have the orphaned child
    # deleted rather than raising. The USDA ingestion/reconciliation path never
    # passes these keys to the changeset (it replaces rows with its own
    # delete_all + create), so this only affects the form-driven edits.
    has_many :ingredient_portions, IngredientPortion, on_replace: :delete
    has_many :ingredient_nutrients, IngredientNutrient, on_replace: :delete

    has_many :ingredient_translation, Mehungry.Food.IngredientTranslation, on_replace: :delete

    # Scientific enrichment sidecar (read-only here). These are intentionally NOT
    # added to `changeset/2`'s cast_assoc list — enrichment is written only via
    # `Mehungry.Food.Enrichment`, never by the USDA ingestion/reconciliation path.
    has_many :scientific_properties, Mehungry.Food.IngredientScientificProperty
    has_many :classifications, Mehungry.Food.IngredientClassification
    has_many :health_attributes, Mehungry.Food.IngredientHealthAttribute
    has_many :compound_relationships, Mehungry.Food.IngredientCompoundRelationship
    has_many :compounds, through: [:compound_relationships, :compound]
    has_many :study_links, Mehungry.Literature.StudyIngredient
    has_many :studies, through: [:study_links, :study]

    timestamps()
  end

  @doc false
  def changeset(ingredient, attrs) do
    ingredient
    |> cast(attrs, [
      :url,
      :name,
      :description,
      :measurement_unit_id,
      :category_id,
      :user_id,
      :nutrient_conversion_factors,
      :publication_date,
      :food_class,
      :data_type,
      :fdc_id,
      :ndb_number,
      :nutrient_data_source
    ])
    |> cast_assoc(:ingredient_portions,
      with: &Mehungry.Food.IngredientPortion.changeset/2,
      sort_param: :ingredient_portions_sort,
      drop_param: :ingredient_portions_drop
    )
    # Add this line
    |> update_search_name()
    |> cast_assoc(:ingredient_translation,
      with: &Mehungry.Food.IngredientTranslation.changeset/2,
      sort_param: :ingredient_translation_sort,
      drop_param: :ingredient_translation_drop
    )
    |> cast_assoc(:ingredient_nutrients,
      with: &Mehungry.Food.IngredientNutrient.changeset/2,
      sort_param: :ingredient_nutrients_sort,
      drop_param: :ingredient_nutrients_drop
    )
    |> foreign_key_constraint(:category_id)
    |> validate_required([:name, :category_id])
    # Global names are unique across the shared catalog; each user's own names are
    # unique per user. These map to the two partial indexes from the migration.
    |> unique_constraint(:name, name: :ingredients_global_name_index)
    |> unique_constraint([:user_id, :name], name: :ingredients_user_name_index)
  end

  defp update_search_name(changeset) do
    if name = get_change(changeset, :name) do
      search_name = normalize_string(name)
      put_change(changeset, :search_name, search_name)
    else
      changeset
    end
  end

  def normalize_string(str) when is_binary(str) do
    str
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  def normalize_string(_), do: ""
end
