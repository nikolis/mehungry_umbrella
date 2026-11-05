defmodule MehungryWeb.Api.V1.RecipeUpdateRoundtripTest do
  @moduledoc """
  Repro: the mobile client re-sends the full recipe (as it received it from
  GET detail) on an image-only update. The detail serializer emits ingredients
  with a nested `ingredient: %{id}` and no top-level `ingredient_id`, but
  cast_assoc -> RecipeIngredient requires :ingredient_id. Result: 422 with a
  list of nested errors (the app shows "[object Object, …]").
  """
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.FoodFixtures
  alias MehungryWeb.Api.V1.RecipeJSON

  setup :register_and_log_in_api_user

  test "re-sending detail-shaped ingredients on update (image-only change)", %{conn: conn, user: user} do
    recipe = FoodFixtures.recipe_fixture(user)
    recipe = Mehungry.Food.get_recipe!(recipe.id)

    # Exactly what GET /recipes/:id handed the client.
    detail = RecipeJSON.detail(recipe, Mehungry.Posts.get_recipe_engagement(recipe.id, user.id), %{saved_recipe_ids: [], follow_ids: []})
    serialized_ingredients = detail.data.ingredients

    # Client changes only the image, re-sends the recipe body incl. ingredients
    # in the shape it was given.
    conn =
      put(conn, ~p"/api/v1/recipes/#{recipe.id}", %{
        "title" => recipe.title,
        "image_url" => "https://fake.supabase.co/storage/v1/object/public/bucket/new.jpg",
        "recipe_ingredients" => Enum.map(serialized_ingredients, &stringify/1)
      })

    body = json_response(conn, conn.status)
    IO.inspect(conn.status, label: "STATUS")
    IO.inspect(body, label: "BODY")

    assert conn.status == 200
  end

  defp stringify(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_v(v)} end)
  end

  defp stringify_v(%{} = m) when not is_struct(m), do: stringify(m)
  defp stringify_v(v), do: v
end
