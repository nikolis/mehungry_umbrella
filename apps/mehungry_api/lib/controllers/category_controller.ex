defmodule MehungryApi.CategoryController do
  use MehungryApi, :controller

  alias Mehungry.Food
  alias Mehungry.Food.Category

  action_fallback(MehungryApi.FallbackController)

  def index(conn, _params) do
    categories = Food.list_categories()
    render(conn, "index.json", categories: categories)
  end

  """
  def swagger_definitions do
    %{
      Category:
        swagger_schema do
          title("Category")
          description("The general category an ingredient belongs e.g Dairy , Meats or Spices")

          properties do
            name(:string, "The name of the category", required: true)
            description(:string, "Some description for the category")
            category_translation(Schema.ref(:CategoryTranslation))
          end
        end,
      CategoryTranslation:
        swagger_schema do
          title("Category Transalation")
          description("Structs representing the translation of a category")

          properties do
            name(
              :string,
              "The name of the category translated in the language infered e.g grammar",
              required: true
            )

            language(Schema.ref(:Language))
          end
        end
    }
  end
  """
end
