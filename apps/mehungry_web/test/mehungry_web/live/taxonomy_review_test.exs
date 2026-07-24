defmodule MehungryWeb.TaxonomyReviewTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures

  alias Mehungry.Food.Taxonomies

  setup %{conn: conn} do
    admin =
      Mehungry.AccountsFixtures.user_fixture(%{
        email: Application.get_env(:mehungry, :admin_email)
      })

    conn = log_in_user(conn, admin)

    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Biological / Nutritional", slug: "bio-nutritional"})

    {:ok, meat} = Taxonomies.create_node(%{name: "Meat", slug: "meat", taxonomy_id: taxonomy.id})

    {:ok, red_meat} =
      Taxonomies.create_node(%{
        name: "Red Meat",
        slug: "red-meat",
        taxonomy_id: taxonomy.id,
        parent_id: meat.id
      })

    {:ok, beef} =
      Taxonomies.create_node(%{
        name: "Beef",
        slug: "beef",
        taxonomy_id: taxonomy.id,
        parent_id: red_meat.id
      })

    {:ok, lamb} =
      Taxonomies.create_node(%{
        name: "Lamb",
        slug: "lamb",
        taxonomy_id: taxonomy.id,
        parent_id: red_meat.id
      })

    %{conn: conn, taxonomy: taxonomy, beef: beef, lamb: lamb}
  end

  test "renders the taxonomy tree through the accordion", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/taxonomy/review")

    assert html =~ "Ingredient Taxonomy Review"
    assert html =~ "Meat"
    assert html =~ "Red Meat"
    assert html =~ "Beef"
    assert html =~ "Nothing pending review."
  end

  test "confirming a pending mapping marks it reviewed", %{
    conn: conn,
    taxonomy: taxonomy,
    beef: beef
  } do
    ingredient = ingredient_fixture(%{name: "Beef, ground, raw"})

    {:ok, mapping} =
      Taxonomies.attach_ingredient(ingredient.id, beef.id, %{source: "ai", confidence: 0.9})

    {:ok, view, html} = live(conn, ~p"/professional/taxonomy/review")
    assert html =~ "Beef, ground, raw"
    assert html =~ "90%"

    html =
      view
      |> element("#mapping-#{mapping.id} button", "Confirm")
      |> render_click()

    assert html =~ "Nothing pending review."
    assert Taxonomies.count_pending_review(taxonomy.id) == 0

    reloaded = Mehungry.Repo.get!(Mehungry.Food.IngredientTaxonomyNode, mapping.id)
    assert reloaded.reviewed
    assert reloaded.source == "ai"
  end

  test "overriding a pending mapping moves it to the chosen leaf", %{
    conn: conn,
    taxonomy: taxonomy,
    beef: beef,
    lamb: lamb
  } do
    ingredient = ingredient_fixture(%{name: "Lamb, shoulder, raw"})

    {:ok, mapping} =
      Taxonomies.attach_ingredient(ingredient.id, beef.id, %{source: "ai", confidence: 0.4})

    {:ok, view, _html} = live(conn, ~p"/professional/taxonomy/review")

    html =
      view
      |> element("#mapping-#{mapping.id} form")
      |> render_submit(%{"id" => to_string(mapping.id), "node_id" => to_string(lamb.id)})

    assert html =~ "Nothing pending review."
    assert Taxonomies.count_pending_review(taxonomy.id) == 0

    reloaded = Mehungry.Repo.get!(Mehungry.Food.IngredientTaxonomyNode, mapping.id)
    assert reloaded.taxonomy_node_id == lamb.id
    assert reloaded.source == "manual"
    assert reloaded.reviewed
    assert is_nil(reloaded.confidence)
  end

  test "a non-admin user is redirected away", %{taxonomy: _taxonomy} do
    conn = Phoenix.ConnTest.build_conn()
    user = Mehungry.AccountsFixtures.user_fixture()
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: "/home"}}} =
             live(conn, ~p"/professional/taxonomy/review")
  end
end
