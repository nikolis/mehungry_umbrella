defmodule MehungryWeb.IngredientsEditTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures

  alias Mehungry.Food
  alias Mehungry.Food.Taxonomies

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    conn = log_in_user(conn, admin)

    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Bio Nutritional", slug: "bio-nutritional"})

    {:ok, meat} = Taxonomies.create_node(%{name: "Meat", slug: "meat", taxonomy_id: taxonomy.id})

    {:ok, beef} =
      Taxonomies.create_node(%{
        name: "Beef",
        slug: "beef",
        taxonomy_id: taxonomy.id,
        parent_id: meat.id
      })

    ingredient = ingredient_fixture(%{name: "brisket"})

    %{conn: conn, taxonomy: taxonomy, beef: beef, ingredient: ingredient}
  end

  test "renders the taxonomy select with a leaf option", %{conn: conn, ingredient: ingredient} do
    {:ok, _view, html} = live(conn, ~p"/professional/ingredients/#{ingredient.id}/edit")

    assert html =~ "Taxonomy (Bio Nutritional)"
    assert html =~ ~s(name="ingredient[taxonomy_node_id]")
    assert html =~ "Meat &gt; Beef"
  end

  test "saving with a chosen node persists a reviewed manual mapping", ctx do
    %{conn: conn, ingredient: ingredient, beef: beef, taxonomy: taxonomy} = ctx
    {:ok, view, _html} = live(conn, ~p"/professional/ingredients/#{ingredient.id}/edit")

    view
    |> form("#ingredient-details-form", %{
      "ingredient" => %{
        "name" => ingredient.name,
        "category_id" => to_string(ingredient.category_id),
        "taxonomy_node_id" => to_string(beef.id)
      }
    })
    |> render_submit()

    assert Food.get_ingredient_node_id(taxonomy.id, ingredient.id) == beef.id
  end
end
