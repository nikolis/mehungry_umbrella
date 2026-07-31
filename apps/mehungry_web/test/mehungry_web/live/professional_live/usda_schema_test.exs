defmodule MehungryWeb.ProfessionalLive.UsdaSchemaTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures

  alias Mehungry.Food

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    %{conn: log_in_user(conn, admin)}
  end

  test "renders the schema page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/usda-schema")

    assert html =~ "USDA Schema"
    assert html =~ "Schemas"
    assert html =~ "Unmatched" or html =~ "Ingredients"
  end

  test "Recompute re-runs without error", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/usda-schema")

    html = view |> element("button", "Recompute") |> render_click()
    assert html =~ "USDA Schema"
  end

  test "renders the Foundemental Foods accordion", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/usda-schema")
    assert html =~ "Foundemental Foods"
  end

  test "a curated ingredient appears under its species", %{conn: conn} do
    ingredient = ingredient_fixture(%{name: "Apple, raw"})
    {:ok, species} = Food.create_foundemental_species(%{"name" => "Apple", "family" => "Rosaceae"})
    {:ok, _} = Food.assign_foundemental_ingredient(species.id, ingredient.id, "Apple, raw")

    {:ok, view, html} = live(conn, ~p"/professional/usda-schema")

    # species header renders in the second accordion
    assert html =~ "Apple"
    assert html =~ "Rosaceae"

    # expanding the species reveals the curated usda_name
    expanded =
      view
      |> element(~s|button[phx-value-key="species:#{species.id}"]|)
      |> render_click()

    assert expanded =~ "Apple, raw"
  end

  test "choosing '+ New species…' opens the create-species modal", %{conn: conn} do
    ingredient = ingredient_fixture(%{name: "Pear, raw"})

    {:ok, view, _html} = live(conn, ~p"/professional/usda-schema")

    html =
      render_change(view, "select_species", %{
        "species_id" => "__new__",
        "ingredient_id" => Integer.to_string(ingredient.id),
        "usda_name" => "Pear, raw"
      })

    assert html =~ "New food species"
    assert html =~ "Pear, raw"
  end

  test "creating a species from the modal curates the pending ingredient", %{conn: conn} do
    ingredient = ingredient_fixture(%{name: "Cherry, raw"})

    {:ok, view, _html} = live(conn, ~p"/professional/usda-schema")

    render_change(view, "select_species", %{
      "species_id" => "__new__",
      "ingredient_id" => Integer.to_string(ingredient.id),
      "usda_name" => "Cherry, raw"
    })

    view
    |> form("#species-form",
      foundemental_food_species: %{
        name: "Cherry",
        variety: "",
        scientific_name: "",
        family: ""
      }
    )
    |> render_submit()

    assert MapSet.member?(Food.assigned_foundemental_ingredient_ids(), ingredient.id)

    species = Enum.find(Food.list_foundemental_species_with_foods(), &(&1.name == "Cherry"))
    assert [%{usda_name: "Cherry, raw"}] = species.foundemental_foods
  end
end
