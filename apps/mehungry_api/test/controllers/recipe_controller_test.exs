defmodule MehungryApi.RecipeControllerTest do
  use MehungryApi.ConnCase

  import OpenApiSpex.TestAssertions

  alias Mehungry.Food
  alias Mehungry.Food.Recipe
  alias Mehungry.Accounts
  alias Mehungry.TestDataHelpers

  @update_attrs %{
    author: "some updated author",
    cooking_time_lower_limit: 43,
    cooking_time_upper_limit: 43,
    cousine: "some updated cousine",
    description: "some updated description",
    image_url: "some updated image_url",
    original_url: "some updated original_url",
    preperation_time_lower_limit: 43,
    preperation_time_upper_limit: 43,
    servings: 43,
    title: "some updated title"
  }

  @invalid_attrs %{
    author: nil,
    cooking_time_lower_limit: nil,
    cooking_time_upper_limit: nil,
    cousine: nil,
    description: nil,
    image_url: nil,
    original_url: nil,
    preperation_time_lower_limit: nil,
    preperation_time_upper_limit: nil,
    servings: nil,
    title: nil
  }

  def fixture(:recipe, title \\ "test1") do
    mu = TestDataHelpers.measurement_unit_fixture()
    ingredient = TestDataHelpers.ingredient_fixture(%{name: title})
    recipe_params = MehungryApi.Schemas.Recipe.schema().example

    valid_attrs =
      Map.put(recipe_params, "recipe_ingredients", [
        %{
          "quantity" => 20,
          "measurement_unit_id" => mu.id,
          "ingredient_id" => ingredient.id,
          "ingredient_allias" => "Pork"
        },
        %{"quantity" => 30, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient.id}
      ])

    valid_attrs = Map.put(valid_attrs, "title", title)

    result = Food.create_recipe(valid_attrs)

    {:ok, recipe} = result
    recipe
  end

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
    user_params = MehungryApi.Schemas.RegisterUserParams.schema().example
    user_resp = Accounts.register_user(user_params.user)
    login_params = MehungryApi.Schemas.LoginWithCredentialsParams.schema().example

    conn_login = build_conn()

    conn_login =
      post(conn_login, Routes.auth_path(conn_login, :login_with_credential, login_params))

    body_login_request = json_response(conn_login, 200)

    %{conn: conn, user: user_resp, jwt: body_login_request["jwt"]}
  end

  describe "index" do
    setup [:create_recipe]

    test "lists all recipes", %{conn: conn, jwt: jwt} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> jwt)

      conn = get(conn, Routes.recipe_path(conn, :index))
      assert Enum.count(json_response(conn, 200)["data"]) == 2
    end

    test "lists all user recipes", %{conn: conn, jwt: jwt} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> jwt)

      conn = get(conn, Routes.recipe_path(conn, :index_user_recipes))
      assert Enum.count(json_response(conn, 200)["data"]) == 0

      mu = TestDataHelpers.measurement_unit_fixture()
      ingredient = TestDataHelpers.ingredient_fixture()

      recipe_params = MehungryApi.Schemas.Recipe.schema().example

      valid_attrs =
        Map.put(recipe_params, "recipe_ingredients", [
          %{
            "quantity" => 20,
            "measurement_unit_id" => mu.id,
            "ingredient_id" => ingredient.id,
            "ingredient_allias" => "Pork"
          },
          %{"quantity" => 30, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient.id}
        ])

      conn = post(conn, Routes.recipe_path(conn, :create), recipe: valid_attrs)

      conn = get(conn, Routes.recipe_path(conn, :index_user_recipes))
      assert Enum.count(json_response(conn, 200)["data"]) == 1
    end

    test "search for recipe", %{conn: conn, recipe: recipe, jwt: jwt} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> jwt)

      conn = get(conn, Routes.recipe_path(conn, :search, String.slice(recipe.title, 0, 3)))
      assert Enum.count(json_response(conn, 200)["data"]) == 1
      api_spec = MehungryApi.ApiSpec.spec()
      assert_schema(json_response(conn, 200), "RecipeSearchResponse", api_spec)
    end
  end

  describe "create recipe" do
    test "renders recipe when data is valid", %{conn: conn, jwt: jwt} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> jwt)

      mu = TestDataHelpers.measurement_unit_fixture()
      ingredient = TestDataHelpers.ingredient_fixture()

      recipe_params = MehungryApi.Schemas.Recipe.schema().example

      valid_attrs =
        Map.put(recipe_params, "recipe_ingredients", [
          %{
            "quantity" => 20,
            "measurement_unit_id" => mu.id,
            "ingredient_id" => ingredient.id,
            "ingredient_allias" => "Pork"
          },
          %{"quantity" => 30, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient.id}
        ])

      conn = post(conn, Routes.recipe_path(conn, :create), recipe: valid_attrs)
      assert %{"recipe_id" => _id} = json_response(conn, 201)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn, jwt: jwt} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> jwt)

      conn = post(conn, Routes.recipe_path(conn, :create), recipe: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "update recipe" do
    setup [:create_recipe]

    test "renders recipe when data is valid", %{
      conn: conn,
      recipe: %Recipe{id: id} = recipe,
      jwt: jwt
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> jwt)

      conn = put(conn, Routes.recipe_path(conn, :update, recipe), recipe: @update_attrs)
      assert %{"id" => ^id} = json_response(conn, 200)["data"]

      conn = get(conn, Routes.recipe_path(conn, :show, id))

      assert %{
               "id" => _id,
               "author" => "some updated author",
               "cooking_time_lower_limit" => 43,
               "cooking_time_upper_limit" => 43,
               "cousine" => "some updated cousine",
               "description" => "some updated description",
               "image_url" => "some updated image_url",
               "original_url" => "some updated original_url",
               "preperation_time_lower_limit" => 43,
               "preperation_time_upper_limit" => 43,
               "servings" => 43,
               "title" => "some updated title"
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn, recipe: recipe, jwt: jwt} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> jwt)

      conn = put(conn, Routes.recipe_path(conn, :update, recipe), recipe: @invalid_attrs)
      assert json_response(conn, 422) != %{}
    end
  end

  describe "delete recipe" do
    setup [:create_recipe]

    test "deletes chosen recipe", %{conn: conn, recipe: recipe, jwt: jwt} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> jwt)

      conn = delete(conn, Routes.recipe_path(conn, :delete, recipe))
      assert response(conn, 204)
    end
  end

  defp create_recipe(_user) do
    _recipe_0 = fixture(:recipe, "other_name")
    recipe = fixture(:recipe)
    {:ok, recipe: recipe}
  end
end
