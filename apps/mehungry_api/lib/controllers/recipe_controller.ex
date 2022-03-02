defmodule MehungryApi.RecipeController do
  use MehungryApi, :controller
  use OpenApiSpex.ControllerSpecs

  alias Mehungry.Food
  alias Mehungry.Food.Recipe
  alias MehungryApi.Schemas.{RecipeSearchResponse, RecipeDetailed, CreatedResponse, NoContent}

  action_fallback(MehungryApi.FallbackController)

  operation(:index,
    summary: "Index Recipes",
    responses: [
      ok: {"Recipe Search Response", "application/json", RecipeSearchResponse}
    ]
  )

  def index(conn, _params) do
    recipes = Food.list_recipes()
    render(conn, "index.json", recipes: recipes)
  end

  operation(:index_user_recipes,
    summary: "Index Recipes for user",
    responses: [
      ok: {"Recipe response ", "application/json", RecipeSearchResponse}
    ]
  )

  def index_user_recipes(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    recipes = Food.list_user_recipes(user.id)
    # recipes = get_recipes_from_cache_or_repo(elem(Integer.parse(user_id),0))
    render(conn, "index.json", recipes: recipes)
  end

  defp get_recipes_from_cache_or_repo(user_id) do
    ConCache.get_or_store(:user_recipes, user_id, fn ->
      Food.list_user_recipes(user_id)
    end)
  end

  operation(:search,
    summary: "Search For ingredient",
    parameters: [
      search_term: [in: :path, type: :string, description: "Search term"]
    ],
    responses: [
      ok: {"Recipe Search Response", "application/json", RecipeSearchResponse}
    ]
  )

  def search(conn, %{"search_term" => search_term}) do
    recipes = Food.search_recipe(search_term)
    render(conn, "index.json", recipes: recipes)
  end

  """
  def like(conn, %{"recipe_id" => recipe_id}) do
    user = Guardian.Plug.current_resource(conn)
    {rec_id, _} = Integer.parse(recipe_id)
    Food.like_recipe(user.id, rec_id)

    conn
    |> put_status(:ok)
    |> send_resp(:ok, "Deleted")
  end
  """

  operation(:create,
    summary: "Create Recipe",
    request_body: {"Recipe params", "application/json", RecipeDetailed},
    responses: [
      created: {"Created Response", "application/json", CreatedResponse}
    ]
  )

  def create(conn, %{"recipe" => recipe_params}) do
    user = Guardian.Plug.current_resource(conn)
    recipe_params = Map.put_new(recipe_params, "user_id", user.id)
    result = Food.create_recipe(recipe_params)

    case result do
      {:ok, %Recipe{} = recipe} ->
        MehungryApi.Endpoint.broadcast!("recipes:1", "new_recipe", %{
          data: %{recipe_id: recipe.id}
        })

        # ConCache.dirty_delete(:user_recipes, user.id)

        recipe =
          Mehungry.Repo.preload(recipe, [
            :user,
            {:recipe_ingredients,
             [
               {:measurement_unit, :translation},
               {:ingredient, [:category, :measurement_unit]}
             ]}
          ])

        conn =
          conn
          |> put_status(:created)

        json(conn, %{data: %{recipe_id: recipe.id}})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render("error.json", changeset: changeset)
    end
  end

  operation(:show,
    summary: "Show recipe",
    parameters: [
      id: [in: :path, type: :integer, description: "Recipe ID"]
    ],
    responses: [
      ok: {"Recipe Detailed Response", "application/json", RecipeDetailed}
    ]
  )

  def show(conn, %{"id" => id}) do
    recipe = Food.get_recipe!(id)

    if is_nil(recipe) do
      conn
      |> put_status(:not_found)
      |> send_resp(:not_found, "Not found")
    else
      recipe =
        Mehungry.Repo.preload(recipe, [
          :user,
          {:recipe_ingredients,
           [
             {:measurement_unit, :translation},
             {:ingredient, [:category, :measurement_unit]}
           ]}
        ])

      render(conn, "show.json", recipe: recipe)
    end
  end

  operation(:update,
    summary: "Update Recipe",
    parameters: [
      id: [in: :path, type: :integer, description: "Recipe ID"]
    ],
    request_body: {"Recipe Params", "application/json", RecipeDetailed},
    responses: [
      ok: {"Recipe Params", "application/json", RecipeDetailed}
    ]
  )

  def update(conn, %{"id" => id, "recipe" => recipe_params}) do
    recipe = Food.get_recipe!(id)

    with {:ok, %Recipe{} = recipe} <- Food.update_recipe(recipe, recipe_params) do
      recipe =
        Mehungry.Repo.preload(recipe, [
          :user,
          {:recipe_ingredients,
           [
             {:measurement_unit, :translation},
             {:ingredient, [:category, :measurement_unit]}
           ]}
        ])

      render(conn, "show.json", recipe: recipe)
    end
  end

  operation(:delete,
    summary: "Delete Recipe",
    parameters: [
      id: [in: :path, description: "Recipe id", type: :integer, example: 1001]
    ],
    responses: [
      no_content: {"No Content", "application/json", NoContent}
    ]
  )

  def delete(conn, %{"id" => id}) do
    case Food.delete_recipe(id) do
      {:ok, struct} ->
        conn
        |> put_status(:no_content)
        |> send_resp(:no_content, "")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:bad_request)
        |> render("error.json", changeset: changeset)
    end
  end
end
