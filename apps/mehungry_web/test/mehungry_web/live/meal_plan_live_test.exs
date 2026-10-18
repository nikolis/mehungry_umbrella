defmodule MehungryWeb.MealPlanLiveTest do
  @moduledoc """
  The public, crawlable meal-plan surface (`/meal-plans/:slug`): the dead
  (crawler) render must already carry the plan content, internal recipe links,
  SEO meta and JSON-LD — and must NOT be `noindex`.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.PublishedPlans

  @week_start ~D[2026-10-05]

  defp publish_plan(opts) do
    user =
      Mehungry.AccountsFixtures.user_fixture()
      |> Ecto.Changeset.change(name: "Chef Nikos")
      |> Mehungry.Repo.update!()

    recipe = Mehungry.FoodFixtures.recipe_fixture(user, %{name: "Lentil Soup"})

    Mehungry.HistoryFixtures.user_meal_fixture(%{
      user_id: user.id,
      title: "Lunch",
      meal_type: "lunch",
      start_dt: ~N[2026-10-06 12:00:00],
      end_dt: ~N[2026-10-06 13:00:00],
      recipe_user_meals: [%{recipe_id: recipe.id, consume_portions: 1, cooking_portions: 1}]
    })

    {:ok, plan} =
      PublishedPlans.publish_week(
        user,
        @week_start,
        Keyword.merge([goal_label: "Anti-inflammatory"], opts)
      )

    %{plan: plan, recipe: recipe, user: user}
  end

  describe "public page /meal-plans/:slug" do
    test "dead render carries content, author, recipe link, SEO meta and JSON-LD", %{conn: conn} do
      %{plan: plan, recipe: recipe, user: user} =
        publish_plan(og_image_url: "https://cdn.example.com/card.png")

      conn = get(conn, ~p"/meal-plans/#{plan.slug}")
      html = html_response(conn, 200)

      # Substantive content is in the crawler-visible HTML.
      assert html =~ plan.title
      assert html =~ plan.summary_text
      # Author attribution links to the poster's profile.
      assert html =~ "Shared by"
      assert html =~ "Chef Nikos"
      assert html =~ "/profile/#{user.id}"
      # Internal link to the recipe's own indexable page.
      assert html =~ "/browse/#{recipe.id}"

      # The weekly grocery list renders grouped into shopping aisles (the fixture
      # recipe's ingredient has no USDA category, so it falls into "Other").
      assert html =~ "Weekly grocery list"
      assert html =~ "items"
      assert html =~ "Other"

      # SEO meta + custom OG image (the share card) + indexable (not noindex).
      assert html =~ ~s(property="og:title")
      assert html =~ "https://cdn.example.com/card.png"
      assert html =~ ~s(<meta name="robots" content="index, follow")
      assert html =~ ~s(rel="canonical")

      # JSON-LD describes the plan's recipes.
      assert html =~ ~s("@type":"BreadcrumbList")
      assert html =~ ~s("@type":"ItemList")
    end

    test "offers copy-ready image caption + text post share controls", %{conn: conn} do
      %{plan: plan} = publish_plan(og_image_url: "https://cdn.example.com/card.png")
      html = conn |> get(~p"/meal-plans/#{plan.slug}") |> html_response(200)

      # Both copyable captions are rendered (in textareas the Copy hook reads).
      assert html =~ ~s(id="plan-image-caption")
      assert html =~ ~s(id="plan-text-post")
      # Copy + native-share controls are wired to the JS hooks.
      assert html =~ ~s(phx-hook="Copy")
      assert html =~ ~s(phx-hook="WebShare")
      # The image-caption column's download link points at the PNG card.
      assert html =~ ~s(href="https://cdn.example.com/card.png")
      # The caption carries the plan link + a hashtag (external-platform payload).
      assert html =~ "#mealprep"
    end

    test "hides the image share column when the plan has no card image", %{conn: conn} do
      %{plan: plan} = publish_plan(og_image_url: nil)
      html = conn |> get(~p"/meal-plans/#{plan.slug}") |> html_response(200)

      # No image → no image-caption textarea, but the text post is still offered.
      refute html =~ ~s(id="plan-image-caption")
      assert html =~ ~s(id="plan-text-post")
    end

    test "shows the card image and a login CTA for anonymous visitors", %{conn: conn} do
      %{plan: plan} = publish_plan(og_image_url: "https://cdn.example.com/card.png")
      html = conn |> get(~p"/meal-plans/#{plan.slug}") |> html_response(200)

      # The PNG card is shown on the page (not only as OG meta).
      assert html =~ ~s(<img src="https://cdn.example.com/card.png")
      # Anonymous visitors are prompted to log in to use the plan.
      assert html =~ "Log in to use this plan"
    end

    test "logged-in visitors get an Add to my calendar button", %{conn: conn} do
      %{plan: plan} = publish_plan([])
      user = Mehungry.AccountsFixtures.user_fixture()
      html = conn |> log_in_user(user) |> get(~p"/meal-plans/#{plan.slug}") |> html_response(200)

      assert html =~ "Add to my calendar"
      assert html =~ ~s(phx-click="use_plan")
    end

    test "an unknown slug 404s (NoResultsError)", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn -> get(conn, ~p"/meal-plans/nope-nope") end
    end

    test "the /el/ page localizes chrome and ingredient names where translations exist",
         %{conn: conn} do
      # Self-provision the legacy "Gr" language the translation row FKs to, rather
      # than assuming ambient seed data (idempotent — no-op if already present).
      Mehungry.Languages.ensure_language("Gr")

      # The category may already exist in the DB — get-or-create.
      veg =
        case Mehungry.Food.create_category(%{name: "Vegetables and Vegetable Products"}) do
          {:ok, c} -> c
          {:error, _} -> Mehungry.Repo.get_by!(Mehungry.Food.Category, name: "Vegetables and Vegetable Products")
        end

      # The translation is stored under the legacy "Gr" code (seeded in the test
      # DB); the /el/ page must still find it because it reads all of the locale's
      # data_codes (["el", "Gr"]) — not just the raw ISO locale.
      {:ok, spinach} =
        Mehungry.Food.create_ingredient(%{
          name: "Spinach",
          category_id: veg.id,
          ingredient_translation: [%{name: "Σπανάκι", language_name: "Gr"}]
        })

      user = Mehungry.AccountsFixtures.user_fixture()
      mu = Mehungry.FoodFixtures.measurement_unit_fixture()

      recipe =
        Mehungry.FoodFixtures.recipe_fixture(user, %{
          recipe_ingredients: [
            %{ingredient_id: spinach.id, measurement_unit_id: mu.id, quantity: 1}
          ]
        })

      Mehungry.HistoryFixtures.user_meal_fixture(%{
        user_id: user.id,
        meal_type: "lunch",
        start_dt: ~N[2026-10-06 12:00:00],
        end_dt: ~N[2026-10-06 13:00:00],
        recipe_user_meals: [%{recipe_id: recipe.id, consume_portions: 1, cooking_portions: 1}]
      })

      {:ok, plan} = Mehungry.PublishedPlans.publish_week(user, @week_start)

      html = conn |> get("/el/meal-plans/#{plan.slug}") |> html_response(200)

      # Localized UI chrome (from the el gettext catalog).
      assert html =~ "Εβδομαδιαία λίστα για ψώνια"
      # The ingredient name is shown in Greek where a translation exists.
      assert html =~ "Σπανάκι"
      refute html =~ "Spinach"
    end
  end

  describe "likes + comments (feed-post social thread)" do
    # A plan + its WEEKLY_PLAN feed post (the post is what carries likes/comments;
    # it's created when the week is shared to the feed from the calendar).
    defp publish_plan_with_post(opts \\ []) do
      %{plan: plan, user: user} = publish_plan(opts)

      {:ok, graphic} =
        Mehungry.Food.create_weekly_plan_graphic(%{
          user_id: user.id,
          week_start: @week_start,
          image_url: "https://cdn.example.com/card.png"
        })

      {:ok, post} =
        Mehungry.Posts.create_weekly_plan_post(graphic, plan.title,
          published_meal_plan_id: plan.id
        )

      %{plan: plan, user: user, post: post}
    end

    test "the dead render shows the like control and comments section", %{conn: conn} do
      %{plan: plan} = publish_plan_with_post()

      html = conn |> get(~p"/meal-plans/#{plan.slug}") |> html_response(200)

      assert html =~ ~s(phx-click="toggle_like")
      assert html =~ "comment"
      # Anonymous visitors are prompted to log in rather than shown a composer.
      assert html =~ "to join the conversation"
    end

    test "a logged-in user can like the plan and post a comment", %{conn: conn} do
      %{plan: plan} = publish_plan_with_post()
      user = Mehungry.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/meal-plans/#{plan.slug}")

      view |> element(~s(button[phx-click="toggle_like"])) |> render_click()
      assert render(view) =~ ~s(fill="currentColor")

      view
      |> form(~s(form[phx-submit="add_comment"]), comment: %{text: "Great week of meals!"})
      |> render_submit()

      assert render(view) =~ "Great week of meals!"
    end
  end
end
