defmodule MehungryWeb.Api.V1.RecipeUpdateImageTest do
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.FoodFixtures

  setup :register_and_log_in_api_user

  test "update own recipe with a new image via image_upload_id (spec §11)", %{conn: conn, user: user} do
    recipe = FoodFixtures.recipe_fixture(user)

    conn =
      put(conn, ~p"/api/v1/recipes/#{recipe.id}", %{
        "title" => recipe.title,
        "image_upload_id" => "recipe_images/tmp/#{Ecto.UUID.generate()}.jpg"
      })

    assert %{"data" => %{"image_url" => image_url}} = json_response(conn, 200)
    # The newly uploaded image must be reflected on the recipe.
    assert image_url =~ "recipe_images/tmp/"
  end

  test "update own recipe with a new image via literal image_url", %{conn: conn, user: user} do
    recipe = FoodFixtures.recipe_fixture(user)
    new_url = "https://fake.supabase.co/storage/v1/object/public/bucket/recipe_images/x.jpg"

    conn =
      put(conn, ~p"/api/v1/recipes/#{recipe.id}", %{
        "title" => recipe.title,
        "image_url" => new_url
      })

    assert %{"data" => %{"image_url" => ^new_url}} = json_response(conn, 200)
  end
end
