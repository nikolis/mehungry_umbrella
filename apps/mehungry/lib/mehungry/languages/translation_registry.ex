defmodule Mehungry.Languages.TranslationRegistry do
  @moduledoc """
  The single source of truth for every user-facing DB resource that carries
  per-language translations. Each descriptor declares its base schema, its
  `*_translation` schema, the FK that links them, the translatable text fields,
  and how it is machine-translated. `Mehungry.Languages.{Translations, Coverage}`
  and the professional translation hub are all driven off this list.

  A descriptor is a plain map:

    * `:key`               — URL/identifier slug (e.g. `"compounds"`)
    * `:label`             — human label for the hub
    * `:base_schema`       — the translated entity (e.g. `Food.Compound`)
    * `:translation_schema`— its `*_translation` schema
    * `:fk`                — translation → base foreign key (e.g. `:compound_id`)
    * `:fields`            — translatable text fields, primary/name field first
    * `:name_field`        — base field to show as the item's title
    * `:ai`                — `:fields` (generic) or `:recipe` (structured steps)
    * `:ai_hint`           — domain hint passed to `AI.FieldTranslator`
  """

  alias Mehungry.Food
  alias Mehungry.FoodProducts
  alias Mehungry.Health
  alias Mehungry.AI.Bot.RecipeTranslation

  @registry [
    %{
      key: "recipes",
      label: "Recipes",
      base_schema: Food.Recipe,
      translation_schema: RecipeTranslation,
      fk: :recipe_id,
      fields: [:title, :description],
      name_field: :title,
      ai: :recipe,
      ai_hint: "recipe"
    },
    %{
      key: "ingredients",
      label: "Ingredients",
      base_schema: Food.Ingredient,
      translation_schema: Food.IngredientTranslation,
      fk: :ingredient_id,
      fields: [:name, :description],
      name_field: :name,
      ai: :fields,
      ai_hint: "USDA food ingredient name, as a Greek home cook would say it"
    },
    %{
      key: "measurement_units",
      label: "Measurement Units",
      base_schema: Food.MeasurementUnit,
      translation_schema: Food.MeasurementUnitTranslation,
      fk: :measurement_unit_id,
      fields: [:name, :alternate_name],
      name_field: :name,
      ai: :fields,
      ai_hint: "cooking measurement unit"
    },
    %{
      key: "categories",
      label: "Categories",
      base_schema: Food.Category,
      translation_schema: Food.CategoryTranslation,
      fk: :category_id,
      fields: [:name],
      name_field: :name,
      ai: :fields,
      ai_hint: "food category"
    },
    %{
      key: "species",
      label: "Food Species",
      base_schema: Food.FoundementalFoodSpecies,
      translation_schema: Food.FoundementalFoodSpeciesTranslation,
      fk: :foundemental_species_id,
      fields: [:name, :description],
      name_field: :name,
      ai: :fields,
      ai_hint: "edible food species / plant or animal"
    },
    %{
      key: "food_products",
      label: "Food Products",
      base_schema: FoodProducts.FoodProduct,
      translation_schema: FoodProducts.FoodProductTranslation,
      fk: :food_product_id,
      fields: [:name, :ingredients_text],
      name_field: :name,
      ai: :fields,
      ai_hint: "packaged food product"
    },
    %{
      key: "compounds",
      label: "Compounds",
      base_schema: Food.Compound,
      translation_schema: Food.CompoundTranslation,
      fk: :compound_id,
      fields: [:name, :description],
      name_field: :name,
      ai: :fields,
      ai_hint: "bioactive / chemical compound"
    },
    %{
      key: "conditions",
      label: "Health Conditions",
      base_schema: Health.Condition,
      translation_schema: Health.ConditionTranslation,
      fk: :condition_id,
      fields: [:name, :description],
      name_field: :name,
      ai: :fields,
      ai_hint: "health condition / medical term"
    },
    %{
      key: "nutrients",
      label: "Nutrients",
      base_schema: Food.Nutrient,
      translation_schema: Food.NutrientTranslation,
      fk: :nutrient_id,
      fields: [:name, :alternate_name, :description],
      name_field: :name,
      ai: :fields,
      ai_hint: "nutrient (vitamin / mineral / macronutrient)"
    }
  ]

  @doc "All translatable-resource descriptors."
  def all, do: @registry

  @doc "Fetch a descriptor by its `:key`, or nil."
  def get(key), do: Enum.find(@registry, &(&1.key == key))

  @doc "All descriptor keys."
  def keys, do: Enum.map(@registry, & &1.key)
end
