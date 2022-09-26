defmodule Mehungry.TestDataHelpers do
  alias Mehungry.Languages

  alias Mehungry.{
    Accounts,
    Food
  }

  def user_fixture(attrs \\ %{}) do
    username = "user#{System.unique_integer([:positive])}"

    {:ok, user} =
      attrs
      |> Enum.into(%{
        name: "Some user",
        username: username,
        credential: %{
          email: attrs[:email] || "#{username}@example.com",
          password: attrs[:password] || "supersecret"
        }
      })
      |> Accounts.register_user()

    user
  end

  def ingredient_fixture(attrs \\ %{}) do
    name =
      case Map.get(attrs, :name) do
        nil ->
          "ingredient_name"

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

  def category_fixture(attrs) do
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

    lang2 = Languages.get_language_by_name("Gr")

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
        category_translation: [
          %{
            language_name: lang.name,
            name: "category"
          },
          %{
            language_name: lang2.name,
            name: category_name
          }
        ]
      })

    category
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

    {:ok, mu} =
      Food.create_measurement_unit(%{
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

    mu
  end

  def recipe_ingredient_fixture(
        %Food.Recipe{} = recipe,
        %Food.Ingredient{} = ingredient,
        %Food.MeasurementUnit{} = mo,
        attrs \\ %{}
      ) do
    attrs =
      Enum.into(attrs, %{
        quantity: 3
      })

    {:ok, recipe_ingredient} = Food.create_recipe_ingredient(recipe, ingredient, mo, attrs)

    recipe_ingredient
  end

  def recipe_fixture(%Accounts.User{} = user, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        title: "some title",
        author: "another author",
        cousine: "some cusine",
        description: "some description",
        servings: 4
      })
  end
end
