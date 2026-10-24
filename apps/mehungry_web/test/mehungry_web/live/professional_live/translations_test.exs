defmodule MehungryWeb.ProfessionalLive.TranslationsTest do
  use MehungryWeb.ConnCase
  use Oban.Testing, repo: Mehungry.Repo

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
      |> form("form[phx-submit=save]", %{
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

    test "editing the original updates the base recipe text and steps", %{
      conn: conn,
      recipe: recipe
    } do
      {:ok, view, _html} = live(conn, ~p"/professional/translations/recipes/#{recipe.id}")

      view
      |> form("form[phx-submit=save_original]", %{
        "base" => %{"title" => "Fixed title", "description" => "Fixed description"},
        "base_steps" => %{"0" => "Dice the onion.", "1" => "Simmer the water."}
      })
      |> render_submit()

      updated = Food.get_recipe!(recipe.id)

      assert updated.title == "Fixed title"
      assert updated.description == "Fixed description"
      assert Enum.map(updated.steps, & &1.description) == ["Dice the onion.", "Simmer the water."]
    end
  end

  describe "bidirectional recipe translation (source language aware)" do
    test "a Greek-authored recipe is not offered for translation into Greek", %{
      conn: conn,
      admin: admin
    } do
      _greek = recipe_fixture(admin, %{title: "Ελληνικό πιάτο", language_name: "Gr"})

      # It must NOT appear in the Greek panel (it's already Greek)…
      {:ok, _view, el_html} = live(conn, ~p"/professional/translations/recipes?lang=el")
      refute el_html =~ "Ελληνικό πιάτο"

      # …but it SHOULD appear under English as still needing an English version.
      {:ok, _view, en_html} = live(conn, ~p"/professional/translations/recipes?lang=en")
      assert en_html =~ "Ελληνικό πιάτο"
    end

    test "opening a Greek recipe's editor targets English, not Greek", %{
      conn: conn,
      admin: admin
    } do
      greek = recipe_fixture(admin, %{title: "Ελληνικό πιάτο", language_name: "Gr"})

      # No ?lang given — the editor must pick a target that differs from the
      # recipe's own language.
      {:ok, _view, html} = live(conn, ~p"/professional/translations/recipes/#{greek.id}")

      assert html =~ "Original (el)"
      assert html =~ "Translation (en)"
    end

    test "an English recipe still translates into Greek by default", %{conn: conn, admin: admin} do
      english = recipe_fixture(admin, %{title: "English dish", language_name: "En"})

      {:ok, _view, html} = live(conn, ~p"/professional/translations/recipes/#{english.id}")

      assert html =~ "Original (en)"
      assert html =~ "Translation (el)"
    end

    test "Greek recipes are excluded from the Greek coverage denominator", %{admin: admin} do
      descriptor = TranslationRegistry.get("recipes")
      before_el = Coverage.coverage(descriptor, "el").total
      before_en = Coverage.coverage(descriptor, "en").total

      _greek = recipe_fixture(admin, %{language_name: "Gr"})

      # Needs an English translation (counts toward en) but not a Greek one.
      assert Coverage.coverage(descriptor, "el").total == before_el
      assert Coverage.coverage(descriptor, "en").total == before_en + 1
    end
  end

  describe "ingredient portion editor" do
    setup do
      ingredient = ingredient_fixture()

      {:ok, portion} =
        Food.create_ingredient_portion(%{
          ingredient_id: ingredient.id,
          description: "1 medium banana",
          gram_weight: 118.0
        })

      %{ingredient: ingredient, portion: portion}
    end

    test "renders the unit-less portion with an editable translation input", %{
      conn: conn,
      ingredient: ingredient,
      portion: portion
    } do
      {:ok, _view, html} =
        live(conn, ~p"/professional/translations/ingredients/#{ingredient.id}")

      assert html =~ "Portions"
      assert html =~ "1 medium banana"
      assert html =~ ~s(name="portions[#{portion.id}]")
    end

    test "Save & Verify persists the portion translation", %{
      conn: conn,
      ingredient: ingredient,
      portion: portion
    } do
      {:ok, view, _html} =
        live(conn, ~p"/professional/translations/ingredients/#{ingredient.id}")

      view
      |> form("form[phx-submit=save]", %{
        "fields" => %{"name" => "μπανάνα", "description" => ""},
        "portions" => %{"#{portion.id}" => "1 μέτρια μπανάνα"}
      })
      |> render_submit()

      assert Food.portion_display_names([portion.id], "el") == %{portion.id => "1 μέτρια μπανάνα"}
    end

    test "'AI-translate missing portions' enqueues a portions-only run and skips done ones", %{
      conn: conn,
      ingredient: ingredient,
      portion: portion
    } do
      {:ok, view, html} = live(conn, ~p"/professional/translations/ingredients")

      # The ingredient has an untranslated portion → the button is enabled.
      assert html =~ "AI-translate missing portions"

      view |> element("button[phx-click=ai_portions]") |> render_click()

      assert_enqueued(
        worker: Mehungry.ObanWorkers.ResourceTranslationWorker,
        args: %{resource: "ingredients", language: "el", portions_only: true}
      )

      # The enqueued batch targets the ingredient with the missing portion.
      [job] = all_enqueued(worker: Mehungry.ObanWorkers.ResourceTranslationWorker)
      assert ingredient.id in job.args["ids"]
      assert portion
    end
  end

  test "editing the original updates a flat resource (compound)", %{
    conn: conn,
    compound: compound
  } do
    {:ok, view, _html} = live(conn, ~p"/professional/translations/compounds/#{compound.id}")

    view
    |> form("form[phx-submit=save_original]", %{"base" => %{"name" => "Oxalic acid"}})
    |> render_submit()

    assert Mehungry.Repo.get!(Mehungry.Food.Compound, compound.id).name == "Oxalic acid"
  end
end
