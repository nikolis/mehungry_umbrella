defmodule MehungryWeb.Api.V1.RecipeUpdateStepsTest do
  @moduledoc """
  Repro: mobile client PUTs the full recipe (including `steps`) on edit. The
  recipe already has persisted steps, so cast_embed(:steps) must replace them.
  With embeds_many defaulting to on_replace: :raise this crashed with a 500.
  """
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.FoodFixtures

  setup :register_and_log_in_api_user

  test "update a recipe that has steps, sending new steps (no ids)", %{conn: conn, user: user} do
    recipe =
      FoodFixtures.recipe_fixture(user, %{
        image_url: nil,
        steps: [%{index: 1, title: "Prep", description: "Chop things"}]
      })

    assert [%{description: "Chop things"}] = recipe.steps

    conn =
      put(conn, ~p"/api/v1/recipes/#{recipe.id}", %{
        "title" => recipe.title,
        "image_url" => "https://fake.supabase.co/storage/v1/object/public/bucket/x.jpg",
        "steps" => [
          %{"index" => 1, "title" => "Prep", "description" => "Chop things"},
          %{"index" => 2, "title" => "Cook", "description" => "Heat it up"}
        ]
      })

    assert %{"data" => %{"image_url" => url}} = json_response(conn, 200)
    assert url =~ "fake.supabase.co"

    reloaded = Mehungry.Food.get_recipe!(recipe.id)
    assert length(reloaded.steps) == 2
  end
end
