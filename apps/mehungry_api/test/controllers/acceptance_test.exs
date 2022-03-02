"""
defmodule MehungryServerWeb.AcceptanceTest do
use MehungryServerWeb.ConnCase

alias MehungryServer.Food
alias MehungryServer.Food.Ingredient
alias MehungryServer.Food.Recipe
alias MehungryServer.Accounts.User
alias MehungryServer.Accounts
alias MehungryServer.TestDataHelpers
alias MehungryServer.Languages

describe "category test" do
  test "Index categories", %{conn: conn} do
    assert {:ok, %User{} = user} =
             Accounts.register_user(%{
               credential: %{email: "someemail@domain.com", password: "123456"}
             })

    conn2 =
      post(build_conn(), Routes.login_path(conn, :login_with_credential),
        credential: %{
          "email" => "someemail@domain.com",
          "password" => "123456",
          "captcha_token" => "googletoklen"
        }
      )

    body = json_response(conn2, 200)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> body["jwt"])

    conn = get(conn, Routes.category_path(conn, :index))
    result = json_response(conn, 200)
    assert length(result["data"]) > 5
  end
end

describe "measurement units" do
  test "Index measurement units", %{conn: conn} do
    assert {:ok, %User{} = user} =
             Accounts.register_user(%{
               credential: %{email: "someemail@domain.com", password: "123456"}
             })

    conn2 =
      post(build_conn(), Routes.login_path(conn, :login_with_credential),
        credential: %{
          "email" => "someemail@domain.com",
          "password" => "123456",
          "captcha_token" => "googletoklen"
        }
      )

    body = json_response(conn2, 200)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> body["jwt"])

    conn = get(conn, Routes.measurement_unit_path(conn, :index))
    result = json_response(conn, 200)
    assert length(result["data"]) >= 4
  end
end

describe "Ingredients test " do
  test "Index ingredients", %{conn: conn} do
    assert {:ok, %User{} = user} =
             Accounts.register_user(%{
               credential: %{email: "someemail@domain.com", password: "123456"}
             })

    conn2 =
      post(build_conn(), Routes.login_path(conn, :login_with_credential),
        credential: %{
          "email" => "someemail@domain.com",
          "password" => "123456",
          "captcha_token" => "googletoklen"
        }
      )

    body = json_response(conn2, 200)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> body["jwt"])

    conn = get(conn, Routes.ingredient_path(conn, :index))
    assert length(json_response(conn, 200)["data"]) > 5
  end

  test "Create ingredient with translation", %{conn: conn} do
    assert {:ok, %User{} = user} =
             Accounts.register_user(%{
               credential: %{email: "someemail@domain.com", password: "123456"}
             })

    conn2 =
      post(build_conn(), Routes.login_path(conn, :login_with_credential),
        credential: %{
          "email" => "someemail@domain.com",
          "password" => "123456",
          "captcha_token" => "googletoklen"
        }
      )

    body = json_response(conn2, 200)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> body["jwt"])

    ingredient = %{
      "url" => "https://el.wikipedia.org/wiki/%CE%94%CE%AF%CE%BA%CF%84%CE%B1%CE%BC%CE%BF",
      "description" => "Είναι το δίκταμο",
      "measurement_unit_id" => 1,
      "category_id" => 1,
      "name" => "δικταμο",
      "ingredient_translation" => [
        %{
          "measurement_unit_id" => 1,
          "category_id" => 1,
          "description" => "some english description",
          "url" => "https://en.wikipedia.org/wiki/Origanum_dictamnus",
          "language_id" => 1,
          "name" => "diktamus"
        }
      ]
    }

    conn = post(conn, Routes.ingredient_path(conn, :create), ingredient: ingredient)
    assert ingredient = json_response(conn, 201)
    [head | _rest] = ingredient["ingredient_translation"]
    assert head["description"] == "some english description"
    assert head["url"] == "https://en.wikipedia.org/wiki/Origanum_dictamnus"
  end
end

defp recipe_fixture_local() do
  mu = TestDataHelpers.measurement_unit_fixture()
  ingredient = TestDataHelpers.ingredient_fixture()
  lang = Languages.get_language_by_name("En")
  Accounts.register_user(%{email: "someemail@domain.com", password: "123456"})

  # TestDataHelpers.user_fixture
  [%User{email: "someemail@domain.com"} = user] = MehungryServer.Accounts.list_users()

  valid_attrs = %{
    "author" => "Nikolaos Galerakis",
    "cousine" => "Without boarders",
    "description" => "a recipe I just invented",
    "servings" => 4,
    "title" => "tst1",
    "user" => user,
    "language_id" => lang.id,
    "title" => "tst1 gluten-free",
    "steps" => [%{"title" => "dsa", "description" => "asdfasdf gluten-free"}],
    "recipe_ingredients" => [
      %{
        "quantity" => 20,
        "measurement_unit_id" => mu.id,
        "ingredient_id" => ingredient.id,
        "ingredient_allias" => "Pork"
      },
      %{"quantity" => 30, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient.id}
    ]
  }

  result = Food.create_recipe(valid_attrs)
  result
end

describe "Recipe test" do
  test "create recipe", %{conn: conn} do
    recipe = recipe_fixture_local()
  end
end
end
"""
