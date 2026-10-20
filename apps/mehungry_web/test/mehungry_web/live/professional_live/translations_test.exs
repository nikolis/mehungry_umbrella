defmodule MehungryWeb.ProfessionalLive.TranslationsTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  alias Mehungry.Food
  alias Mehungry.Languages.{Coverage, TranslationRegistry, Translations}

  import Mehungry.FoodFixtures

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    conn = log_in_user(conn, admin)
    {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})
    %{conn: conn, compound: oxalate, admin: admin}
  end

  test "hub lists resources with coverage", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/translations")

    assert html =~ "Translation Coverage"
    assert html =~ "Compounds"
    assert html =~ "Ingredients"
  end

  test "panel lists missing items and links to the editor", %{conn: conn, compound: compound} do
    {:ok, view, _html} = live(conn, ~p"/professional/translations/compounds")

    assert has_element?(view, "a[href='/professional/translations/compounds/#{compound.id}']")
    assert render(view) =~ "Oxalate"
  end

  test "verifying a draft moves it out of the missing bucket", %{conn: conn, compound: compound} do
    descriptor = TranslationRegistry.get("compounds")

    {:ok, _} =
      Translations.upsert(descriptor, compound.id, "el", %{name: "Οξαλικό"}, status: "ai_draft")

    assert Coverage.coverage(descriptor, "el").ai_draft == 1

    {:ok, view, _html} = live(conn, ~p"/professional/translations/compounds?filter=ai_draft")

    view
    |> element("button[phx-click=verify][phx-value-id='#{compound.id}']")
    |> render_click()

    assert Coverage.coverage(descriptor, "el").verified == 1
    assert Coverage.coverage(descriptor, "el").ai_draft == 0
  end

  describe "recipe editor steps" do
    setup %{admin: admin} do
      recipe =
        recipe_fixture(admin, %{
          steps: [
            %{index: 0, description: "Chop the onion."},
            %{index: 1, description: "Boil the water."}
          ]
        })

      %{recipe: recipe}
    end

    test "renders the original steps for review", %{conn: conn, recipe: recipe} do
      {:ok, _view, html} = live(conn, ~p"/professional/translations/recipes/#{recipe.id}")

      assert html =~ "Chop the onion."
      assert html =~ "Boil the water."
      # One editable textarea per step in the translation column.
      assert html =~ ~s(name="steps[0]")
      assert html =~ ~s(name="steps[1]")
    end

    test "Save & Verify persists translated steps", %{conn: conn, recipe: recipe} do
      {:ok, view, _html} = live(conn, ~p"/professional/translations/recipes/#{recipe.id}")

      view
      |> form("form", %{
        "fields" => %{"title" => "Τίτλος", "description" => "Περιγραφή"},
        "steps" => %{"0" => "Κόψε το κρεμμύδι.", "1" => "Βράσε το νερό."}
      })
      |> render_submit()

      descriptor = TranslationRegistry.get("recipes")
      %{translation: translation} = Translations.get_pair(descriptor, recipe.id, "el")

      assert translation.title == "Τίτλος"
      assert translation.status == "verified"

      assert translation.steps == [
               %{"index" => 0, "description" => "Κόψε το κρεμμύδι."},
               %{"index" => 1, "description" => "Βράσε το νερό."}
             ]
    end
  end
end
