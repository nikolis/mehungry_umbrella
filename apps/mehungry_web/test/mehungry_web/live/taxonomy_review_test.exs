defmodule MehungryWeb.TaxonomyReviewTest do
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

    # mount looks up the "bio-nutritional" taxonomy by slug.
    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Bio Nutritional", slug: "bio-nutritional"})

    {:ok, meat} = Taxonomies.create_node(%{name: "Meat", slug: "meat", taxonomy_id: taxonomy.id})

    {:ok, beef} =
      Taxonomies.create_node(%{name: "Beef", slug: "beef", taxonomy_id: taxonomy.id, parent_id: meat.id})

    {:ok, lamb} =
      Taxonomies.create_node(%{name: "Lamb", slug: "lamb", taxonomy_id: taxonomy.id, parent_id: meat.id})

    ingredient = ingredient_fixture(%{name: "beef brisket"})

    {:ok, mapping} =
      Taxonomies.attach_ingredient(ingredient.id, beef.id, %{source: "ai", confidence: 0.42})

    %{
      conn: conn,
      taxonomy: taxonomy,
      beef: beef,
      lamb: lamb,
      ingredient: ingredient,
      mapping: mapping
    }
  end

  test "renders the tree through AccordionComponent and the pending row", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/taxonomy/review")

    # Accordion node names
    assert html =~ "Meat"
    assert html =~ "Beef"
    # Pending assignment row
    assert html =~ "beef brisket"
    assert html =~ "Meat &gt; Beef"
  end

  test "confirm removes the row from the pending list", %{conn: conn, mapping: mapping} do
    {:ok, view, _html} = live(conn, ~p"/professional/taxonomy/review")

    assert render(view) =~ "beef brisket"

    view
    |> element("button[phx-value-id='#{mapping.id}']")
    |> render_click()

    refute render(view) =~ "beef brisket"

    reloaded = Food.get_taxonomy_by_slug("bio-nutritional")
    assert Food.list_pending_review(reloaded.id) == []
  end

  test "override moves the mapping to the chosen leaf and drops the row", ctx do
    %{conn: conn, mapping: mapping, lamb: lamb, ingredient: ingredient} = ctx
    {:ok, view, _html} = live(conn, ~p"/professional/taxonomy/review")

    view
    |> form("form[phx-change='override']", %{"id" => mapping.id, "node_id" => lamb.id})
    |> render_change()

    refute render(view) =~ "beef brisket"

    moved = Mehungry.Repo.get!(Mehungry.Food.IngredientTaxonomyNode, mapping.id)
    assert moved.taxonomy_node_id == lamb.id
    assert moved.source == "manual"
    assert moved.reviewed
    assert is_nil(moved.confidence)

    # ingredient now resolves under lamb, not beef
    lamb_ingredient_ids =
      lamb.id |> Food.list_ingredients_under_node() |> Enum.map(& &1.id)

    assert ingredient.id in lamb_ingredient_ids
  end

  test "non-admin is redirected away", %{taxonomy: _taxonomy} do
    conn = build_conn()
    user = user_fixture(%{email: "notadmin@example.com"})
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: "/home"}}} =
             live(conn, ~p"/professional/taxonomy/review")
  end
end
