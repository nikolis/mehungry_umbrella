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

    {:ok, species} =
      Food.create_foundemental_species(%{"name" => "Apple", "family" => "Rosaceae"})

    {:ok, _} = Food.assign_foundemental_ingredient(species.id, ingredient.id, "Apple, raw")

    {:ok, view, _html} = live(conn, ~p"/professional/usda-schema")

    # The corpus parse runs off the mount critical path (async :load), so read
    # the rendered view after it has populated rather than the initial html.
    html = render(view)

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

  test "assigning a streamed row removes it from the open panel", %{conn: conn} do
    # Sorts first (within the 100-row cap) and matches a real schema.
    name = "Aaaatest, raw"
    ingredient = ingredient_fixture(%{name: name, fdc_id: 987_654})
    {:ok, species} = Food.create_foundemental_species(%{"name" => "Aaaa"})

    {:ok, view, _html} = live(conn, ~p"/professional/usda-schema")
    _ = render(view)

    # Open whichever panel (a schema, or Unmatched) the parser placed it in.
    analysis = Mehungry.FoodData.Usda.SchemaMatcher.analyze()

    key =
      if Enum.any?(analysis.unmatched, &(&1.ingredient.id == ingredient.id)) do
        "__unmatched__"
      else
        Enum.find_value(analysis.schemas, fn s ->
          if Enum.any?(s.matched, &(&1.id == ingredient.id)), do: s.key
        end)
      end

    assert key, "seeded fdc ingredient did not appear in any panel"

    view |> element(~s|button[phx-value-key="#{key}"]|) |> render_click()
    # The row is streamed into the panel (asserted via its stream dom id, since
    # the name also shows up in the always-visible schema "e.g. …" header examples).
    row = "#rows-#{ingredient.id}"
    assert has_element?(view, row)
    # The search box is pre-seeded with the first two letters of the row name.
    assert has_element?(view, ~s|#{row} input[value="Aa"]|)

    # Pick the existing species → confirm modal → assign.
    render_change(view, "select_species", %{
      "species_id" => Integer.to_string(species.id),
      "ingredient_id" => Integer.to_string(ingredient.id),
      "usda_name" => name
    })

    view |> element("#assign-modal button", "Assign") |> render_click()

    assert MapSet.member?(Food.assigned_foundemental_ingredient_ids(), ingredient.id)
    # stream_delete removed the row without re-rendering the whole panel
    refute has_element?(view, row)
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
