defmodule Mehungry.FoodFixtures do
  @moduledoc false

  alias Mehungry.Languages

  alias Mehungry.{
    Accounts,
    Food
  }

  def unique_ingredient, do: "ingredient#{System.unique_integer()}"

  def ingredient_fixture(attrs \\ %{}) do
    name =
      case Map.get(attrs, :name) do
        nil ->
          unique_ingredient()

        name ->
          name
      end

    lang = Languages.get_language_by_name("En")

    lang =
      case lang do
        nil ->
          {:ok, lang} = Languages.create_language(%{name: "En"})
          lang

        value ->
          value
      end

    attrs =
      Enum.into(attrs, %{
        name: name,
        url: "http://example.com",
        description: "a description",
        ingredient_translation: [
          %{
            name: name,
            language_name: lang.name
          }
        ]
      })

    category = category_fixture(attrs)
    mu = measurement_unit_fixture()
    valid_attrs = Map.put(attrs, :category_id, category.id)
    valid_attrs = Map.put(valid_attrs, :measurement_unit_id, mu.id)

    {:ok, ingredient} = Food.create_ingredient(valid_attrs)

    ingredient
  end

  def category_fixture(attrs \\ %{}) do
    case Food.get_category_by_name(Map.get(attrs, :catgeory_name, "category")) do
      nil ->
        category_name =
          case Map.get(attrs, :category_name) do
            nil ->
              "category"

            name ->
              name
          end

        lang = Languages.get_language_by_name("En")

        lang =
          case lang do
            nil ->
              {:ok, lang} = Languages.create_language(%{name: "En"})
              lang

            value ->
              value
          end

        _lang2 = Languages.get_language_by_name("Gr")

        lang2 =
          case lang do
            nil ->
              {:ok, lang2} = Languages.create_language(%{name: "Gr"})
              lang2

            value ->
              value
          end

        {:ok, category} =
          Food.create_category(%{
            name: category_name,
            description: "basic descr",
            category_translation: [
              %{
                language_name: lang.name,
                name: "category",
                description: "asome sdfa"
              },
              %{
                language_name: lang2.name,
                name: category_name,
                description: "asdfdfsaf"
              }
            ]
          })

        category

      category ->
        category
    end
  end

  def measurement_unit_fixture(attrs \\ %{}) do
    lang = Languages.get_language_by_name("En")

    lang =
      case lang do
        nil ->
          {:ok, lang} = Languages.create_language(%{name: "En"})
          lang

        value ->
          value
      end

    lang2 = Languages.get_language_by_name("Gr")

    lang2 =
      case lang2 do
        nil ->
          {:ok, lang2} = Languages.create_language(%{name: "Gr"})
          lang2

        value ->
          value
      end

    attrs =
      Enum.into(attrs, %{
        name: "gram",
        translation: [
          %{
            language_name: lang.name,
            name: "gram"
          },
          %{
            language_name: lang2.name,
            name: "γραμμάριο"
          }
        ]
      })

    {:ok, mu} = Food.create_measurement_unit(attrs)

    mu
  end

  def recipe_fixture(%Accounts.User{} = user, attrs \\ %{}) do
    ingredient = ingredient_fixture()
    mu = measurement_unit_fixture()

    {:ok, recipe} =
      Enum.into(attrs, %{
        title: "some title",
        user_id: user.id,
        author: "another author",
        cousine: "some cusine",
        description: "some description",
        servings: 4,
        language_name: "En",
        recipe_ingredients: [
          %{ingredient_id: ingredient.id, measurement_unit_id: mu.id, quantity: 5}
        ]
      })
      |> Food.create_recipe()

    recipe
  end

  """
  @doc
  Generate a food_restriction_type.
  
  def food_restriction_type_fixture(attrs \\ %{}) do
    {:ok, food_restriction_type} =
      attrs
      |> Enum.into(%{
        alias: "some alias",
        title: "some title"
      })
      |> Mehungry.Food.create_food_restriction_type()

    food_restriction_type
  end
  """
end
