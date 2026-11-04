defmodule MehungryWeb.Api.V1.RecipeUpdateAddImageTest do
  @moduledoc """
  Repro for: a recipe created WITHOUT an image, then an image added on edit.
  User reported HTTP 500 on save.
  """
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.FoodFixtures

  setup :register_and_log_in_api_user

  test "add image via image_upload_id to a recipe that had none", %{conn: conn, user: user} do
    recipe = FoodFixtures.recipe_fixture(user, %{image_url: nil})
    assert is_nil(recipe.image_url)

    conn =
      put(conn, ~p"/api/v1/recipes/#{recipe.id}", %{
        "title" => recipe.title,
        "image_upload_id" => "recipe_images/tmp/#{Ecto.UUID.generate()}.jpg"
      })

    assert %{"data" => %{"image_url" => image_url}} = json_response(conn, 200)
    assert image_url =~ "recipe_images/tmp/"
  end

  test "add image via literal image_url to a recipe that had none", %{conn: conn, user: user} do
    recipe = FoodFixtures.recipe_fixture(user, %{image_url: nil})
    new_url = "https://fake.supabase.co/storage/v1/object/public/bucket/recipe_images/x.jpg"

    conn =
      put(conn, ~p"/api/v1/recipes/#{recipe.id}", %{
        "title" => recipe.title,
        "image_url" => new_url
      })

    assert %{"data" => %{"image_url" => ^new_url}} = json_response(conn, 200)
  end
end
