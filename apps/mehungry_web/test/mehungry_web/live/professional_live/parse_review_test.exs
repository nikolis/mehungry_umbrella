defmodule MehungryWeb.ProfessionalLive.ParseReviewTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures

  alias Mehungry.Food
  alias Mehungry.Food.{CanonicalFood, IngredientParsedFood, ParsedFoods, ParserVocabularySeeder}
  alias Mehungry.Repo

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    ParserVocabularySeeder.seed()
    admin = user_fixture(%{email: @admin_email})
    conn = log_in_user(conn, admin)
    %{conn: conn}
  end

  # The shared test DB may contain committed ingredients with real USDA names;
  # reuse them (updating fdc_id inside the sandbox) instead of colliding.
  defp usda_ingredient(name, fdc_id) do
    case Food.get_ingredient_by_name(name) do
      nil -> ingredient_fixture(%{name: name, fdc_id: fdc_id})
      existing -> existing |> Ecto.Changeset.change(fdc_id: fdc_id) |> Repo.update!()
    end
  end

  defp parsed_fixture(name, fdc_id) do
    ingredient = usda_ingredient(name, fdc_id)
    {:ok, parsed, _} = ParsedFoods.parse_ingredient(ingredient)
    {ingredient, parsed}
  end

  test "renders pending parses with their structured fields", %{conn: conn} do
    {ingredient, _parsed} = parsed_fixture("Carrots, baby, raw", 300_001)

    {:ok, _view, html} = live(conn, ~p"/professional/science/parse-review")

    assert html =~ "Parsed foods"
    assert html =~ ingredient.name
    assert html =~ "carrot"
    assert html =~ "baby"
    assert html =~ "raw"
  end

  test "Edit then Save updates the candidate in place", %{conn: conn} do
    {_ingredient, parsed} = parsed_fixture("Frobnitz, canned", 300_002)

    {:ok, view, _html} = live(conn, ~p"/professional/science/parse-review")

    view
    |> element("button[phx-click='edit'][phx-value-id='#{parsed.id}']")
    |> render_click()

    html =
      view
      |> form("form[phx-submit='save']", %{
        "parsed_food" => %{
          "canonical_food_text" => "dragon fruit",
          "harvest_stage" => "mature",
          "processing" => "dried, sliced",
          "processing_modifiers" => "",
          "packaging" => "canned",
          "notes" => "manually corrected"
        }
      })
      |> render_submit()

    assert html =~ "dragon fruit"

    reloaded = Repo.get!(IngredientParsedFood, parsed.id)
    assert reloaded.canonical_food_text == "dragon fruit"
    assert reloaded.processing == ["dried", "sliced"]
    assert reloaded.notes == "manually corrected"
    assert reloaded.status == "candidate"
  end

  test "Verify marks the parse verified, links the lexicon and drops the row", %{conn: conn} do
    {_ingredient, parsed} = parsed_fixture("Pickles, cucumber, dill or kosher dill", 300_003)

    {:ok, view, _html} = live(conn, ~p"/professional/science/parse-review")

    view
    |> element("button[phx-click='verify'][phx-value-id='#{parsed.id}']")
    |> render_click()

    refute has_element?(view, "button[phx-click='verify'][phx-value-id='#{parsed.id}']")

    reloaded = Repo.get!(IngredientParsedFood, parsed.id)
    assert reloaded.status == "verified"
    assert reloaded.verified_by_user_id != nil
    assert reloaded.canonical_food_id == Repo.get_by!(CanonicalFood, name: "cucumber").id
  end

  test "Reject drops the row and keeps it for history", %{conn: conn} do
    {_ingredient, parsed} = parsed_fixture("Oil, corn", 300_004)

    {:ok, view, _html} = live(conn, ~p"/professional/science/parse-review")

    view
    |> element("button[phx-click='reject'][phx-value-id='#{parsed.id}']")
    |> render_click()

    refute has_element?(view, "button[phx-click='reject'][phx-value-id='#{parsed.id}']")
    assert Repo.get!(IngredientParsedFood, parsed.id).status == "rejected"
  end

  test "skipped descriptions appear read-only in their own section", %{conn: conn} do
    {ingredient, _parsed} = parsed_fixture("Alcoholic beverage, daiquiri, canned", 300_005)

    {:ok, _view, html} = live(conn, ~p"/professional/science/parse-review")

    assert html =~ "Skipped (not a food)"
    assert html =~ ingredient.name
    assert html =~ "not_food"
  end

  test "non-admin is redirected away" do
    conn = build_conn()
    user = user_fixture(%{email: "notadmin2@example.com"})
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: "/home"}}} =
             live(conn, ~p"/professional/science/parse-review")
  end
end
