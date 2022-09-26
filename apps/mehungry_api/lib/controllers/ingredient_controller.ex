defmodule MehungryApi.IngredientController do
  use MehungryApi, :controller
  use OpenApiSpex.ControllerSpecs

  alias Mehungry.Food
  alias Mehungry.Food.Ingredient
  alias Mehungry.Repo

  require Logger
  alias MehungryApi.Schemas.{IngredientSearchParams, IngredientSearchResponse}

  action_fallback(MehungryApi.FallbackController)

  """
    def index(conn, _params) do
      ingredients = Food.list_ingredients()
      render(conn, "index.json", ingredients: ingredients)
    end
  """

  """
    def create(conn, %{"ingredient" => ingredient_params}) do
      with {:ok, %Ingredient{} = ingredient} <- Food.create_ingredient(ingredient_params) do
        ingredient =
          Repo.preload(ingredient, [:category, :measurement_unit, :ingredient_translation])

        conn
        |> put_status(:created)
        |> put_resp_header("location", Routes.ingredient_path(conn, :show, ingredient))
        |> render("ingredient_complete.json", ingredient: ingredient)
      end
    end
  """

  def show(conn, %{"id" => id}) do
    ingredient = Food.get_ingredient!(id)
    render(conn, "show.json", ingredient: ingredient)
  end

  operation(:search,
    summary: "Search For ingredient",
    parameters: [
      language: [in: :path, type: :string, description: "Labguage abriviation like \"En\""],
      name: [
        in: :path,
        type: :string,
        description: "Search string representing part of the name of the ingredient"
      ]
    ],
    responses: [
      ok: {"IngredientSearch Response", "application/json", IngredientSearchResponse}
    ]
  )

  def search(conn, %{"name" => name, "language" => language}) do
    ingredients = Food.search_ingredient(name, language)
    render(conn, "index.json", ingredients: ingredients)
  end

  """
    def update(conn, %{"id" => id, "ingredient" => ingredient_params}) do
      ingredient = Food.get_ingredient!(id)

      with {:ok, %Ingredient{} = ingredient} <-
             Food.update_ingredient(ingredient, ingredient_params) do
        render(conn, "ingredient_complete.json", ingredient: ingredient)
      end
    end

    def delete(conn, %{"id" => id}) do
      ingredient = Food.get_ingredient!(id)

      with {:ok, %Ingredient{}} <- Food.delete_ingredient(ingredient) do
        send_resp(conn, :no_content, "")
      end
    end
  """

  """
    def swagger_definitions do
      %{
        Ingredient:
          swagger_schema do
            title("Ingredient")
            description("An ingredient used in Recipes")

            properties do
              description(:string, "The description", required: false)
              name(:string, "The name of the ingredient", required: true)

              field :string, "A url pointing to a site with more information on the ingredient",
                required: false

              measurement_unit(Schema.ref(:MeasurementUnit))
              category(Schema.ref(:Category))
            end
          end
      }
    end
  """
end
