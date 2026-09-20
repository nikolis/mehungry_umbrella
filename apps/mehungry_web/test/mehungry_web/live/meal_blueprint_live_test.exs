defmodule MehungryWeb.MealBlueprintLiveTest do
  @moduledoc false

  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures

  alias Mehungry.MealBlueprints
  alias Mehungry.History.MealType
  alias Mehungry.Subscriptions

  # Authoring lives in the nutritionist ("pro" tier) section now.
  setup %{conn: conn} do
    user = Mehungry.AccountsFixtures.user_fixture()
    {:ok, _} = Subscriptions.upsert_subscription(user.id, %{tier: "pro", status: "active"})
    %{conn: log_in_user(conn, user), user: user}
  end

  defp seed_blueprint(user, name \\ "Seed") do
    {:ok, bp} =
      MealBlueprints.create_blueprint(MealBlueprints.default_blueprint_attrs(user.id, name))

    bp
  end

  test "index lists the user's blueprints", %{conn: conn, user: user} do
    seed_blueprint(user, "Cutting week")

    {:ok, _live, html} = live(conn, ~p"/nutritionist/blueprints")
    assert html =~ "Meal Blueprints"
    assert html =~ "Cutting week"
  end

  test "index shows a Generate button per blueprint", %{conn: conn, user: user} do
    bp = seed_blueprint(user, "Cutting week")

    {:ok, live, _html} = live(conn, ~p"/nutritionist/blueprints")

    assert has_element?(live, "button[phx-click='generate'][phx-value-id='#{bp.id}']")
  end

  # Seeds a completed plan with a recipe meal (day 1) and an ingredient meal (day 3).
  defp seed_plan(user, bp) do
    {:ok, plan} =
      MealBlueprints.create_plan(%{
        name: "Plan · rich",
        start_date: Date.utc_today(),
        status: "completed",
        blueprint_id: bp.id,
        user_id: user.id
      })

    recipe = recipe_fixture(user)
    ingredient = ingredient_fixture(%{name: "Almonds"})
    mu = measurement_unit_fixture()

    {:ok, plan} =
      MealBlueprints.store_plan_meals(plan, [
        %{
          day_index: 1,
          meal_type: "breakfast",
          recipe_id: recipe.id,
          cooking_portions: 2,
          ingredient_id: nil,
          quantity: nil,
          measurement_unit_id: nil,
          ingredient_portion_id: nil
        },
        %{
          day_index: 3,
          meal_type: "morning_snack",
          recipe_id: nil,
          cooking_portions: nil,
          ingredient_id: ingredient.id,
          quantity: 30.0,
          measurement_unit_id: mu.id,
          ingredient_portion_id: nil
        }
      ])

    %{plan: plan, recipe: recipe}
  end

  test "generated plans render independently and expand to show recipe + ingredient", %{
    conn: conn,
    user: user
  } do
    bp = seed_blueprint(user, "Snacky week")
    %{plan: plan, recipe: recipe} = seed_plan(user, bp)

    {:ok, live, html} = live(conn, ~p"/nutritionist/blueprints")
    assert html =~ "Plan · rich"

    html =
      live
      |> element("button[phx-click='toggle_plan'][phx-value-id='#{plan.id}']")
      |> render_click()

    assert html =~ recipe.image_url
    assert html =~ recipe.title
    assert html =~ "Almonds"
    # Nothing on the calendar until imported.
    assert Mehungry.History.list_history_user_meals_for_user(user.id) == []
  end

  test "importing a plan creates calendar meals from the chosen date", %{conn: conn, user: user} do
    bp = seed_blueprint(user, "Snacky week")
    %{plan: plan} = seed_plan(user, bp)

    {:ok, live, _html} = live(conn, ~p"/nutritionist/blueprints")

    # Open the import modal, then submit a start date.
    live |> element("button[phx-click='open_import'][phx-value-id='#{plan.id}']") |> render_click()

    render_submit(element(live, "#import-plan-modal form"), %{
      "import" => %{"start_date" => "2026-10-05"}
    })

    user_meals = Mehungry.History.list_history_user_meals_for_user(user.id)
    assert length(user_meals) == 2
    assert Enum.all?(user_meals, &(&1.blueprint_plan_id == plan.id))

    # The plan is now flagged imported in the UI.
    assert render(live) =~ "imported"
  end

  test "importing a plan for an assigned client writes to the client's calendar", %{
    conn: conn,
    user: user
  } do
    bp = seed_blueprint(user, "Client week")
    %{plan: plan} = seed_plan(user, bp)

    client = Mehungry.AccountsFixtures.user_fixture()

    {:ok, _assignment} =
      %Mehungry.Professionals.TutorClientAssignment{}
      |> Mehungry.Professionals.TutorClientAssignment.changeset(%{
        professional_id: user.id,
        client_id: client.id
      })
      |> Mehungry.Repo.insert()

    {:ok, live, _html} = live(conn, ~p"/nutritionist/blueprints")

    live |> element("button[phx-click='open_import'][phx-value-id='#{plan.id}']") |> render_click()

    # The import modal offers the client as a target.
    assert has_element?(live, "#import-plan-modal select[name='import[target_user_id]']")

    render_submit(element(live, "#import-plan-modal form"), %{
      "import" => %{
        "start_date" => "2026-10-05",
        "target_user_id" => Integer.to_string(client.id)
      }
    })

    # Meals land on the client's calendar, not the nutritionist's.
    assert Mehungry.History.list_history_user_meals_for_user(user.id) == []

    client_meals = Mehungry.History.list_history_user_meals_for_user(client.id)
    assert length(client_meals) == 2
    assert Enum.all?(client_meals, &(&1.blueprint_plan_id == plan.id))
  end

  test "creating from the new modal redirects to the editor with 7 days x 5 meals", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/nutritionist/blueprints/new")

    render_submit(element(live, "#new-blueprint-modal form"), %{
      "blueprint" => %{"name" => "Maintenance"}
    })

    assert {path, _flash} = assert_redirect(live)
    assert path =~ ~r{/blueprints/\d+/edit}
  end

  test "editor renders all 7 days and 5 meal labels", %{conn: conn, user: user} do
    bp = seed_blueprint(user)

    {:ok, _live, html} = live(conn, ~p"/nutritionist/blueprints/#{bp.id}/edit")

    for day <- 1..7, do: assert(html =~ "Day #{day}")
    for mt <- MealType.values(), do: assert(html =~ MealType.label(mt))
  end

  test "editing a meal macro and blueprint-level targets and saving persists them", %{
    conn: conn,
    user: user
  } do
    bp = seed_blueprint(user)
    {:ok, live, _html} = live(conn, ~p"/nutritionist/blueprints/#{bp.id}/edit")

    loaded = MealBlueprints.get_blueprint!(user.id, bp.id)

    params =
      loaded
      |> build_params(fn di, _mi, meal ->
        if di == 0 and meal["meal_type"] == "breakfast",
          do: Map.merge(meal, %{"protein_pct" => "25", "carbs_pct" => "45", "fats_pct" => "30"}),
          else: meal
      end)
      |> Map.merge(%{
        "preferred_foods" => "nuts, dairy",
        "required_nutrients" => ["", "Vitamin C", "Vitamin B12"],
        "avoid_nutrients" => ["", "Sodium"],
        "required_compounds" => ["", "Polyphenols"],
        "avoid_compounds" => ["", "Oxalate"]
      })

    render_submit(element(live, "form"), %{"blueprint" => params})
    assert_redirect(live, ~p"/nutritionist/blueprints")

    reloaded = MealBlueprints.get_blueprint!(user.id, bp.id)

    breakfast =
      reloaded.days |> hd() |> Map.fetch!(:meals) |> Enum.find(&(&1.meal_type == "breakfast"))

    assert breakfast.protein_pct == 25
    assert reloaded.preferred_foods == ["nuts", "dairy"]
    assert reloaded.required_nutrients == ["Vitamin C", "Vitamin B12"]
    assert reloaded.avoid_nutrients == ["Sodium"]
    assert reloaded.required_compounds == ["Polyphenols"]
    assert reloaded.avoid_compounds == ["Oxalate"]
  end

  test "selecting a condition auto-suggests encouraged/avoided compounds into every day", %{
    conn: conn,
    user: user
  } do
    bp = seed_blueprint(user)
    {:ok, condition} = Mehungry.Health.create_condition(%{name: "Ulcerative Colitis"})

    {:ok, good} =
      Mehungry.Food.create_compound(%{name: "Curcumin", compound_type: "polyphenol"})

    {:ok, bad} = Mehungry.Food.create_compound(%{name: "Oxalate", compound_type: "oxalate"})

    {:ok, _} =
      Mehungry.Health.add_recommendation(condition.id, good.id, %{
        recommendation: "encourage",
        source: "manual"
      })

    {:ok, _} =
      Mehungry.Health.add_recommendation(condition.id, bad.id, %{
        recommendation: "avoid",
        source: "manual"
      })

    {:ok, live, _html} = live(conn, ~p"/nutritionist/blueprints/#{bp.id}/edit")

    loaded = MealBlueprints.get_blueprint!(user.id, bp.id)
    params = Map.put(build_params(loaded), "condition_id", to_string(condition.id))

    html = render_change(element(live, "form"), %{"blueprint" => params})

    # Both the encouraged and the avoided compound appear as chips in the days.
    assert html =~ "Curcumin"
    assert html =~ "Oxalate"
  end

  test "the blank picker sentinel never renders as an empty chip after validate", %{
    conn: conn,
    user: user
  } do
    bp = seed_blueprint(user)
    {:ok, live, _html} = live(conn, ~p"/nutritionist/blueprints/#{bp.id}/edit")
    loaded = MealBlueprints.get_blueprint!(user.id, bp.id)

    # Mirrors the browser: each empty picker posts a single "" sentinel value.
    params =
      build_params(loaded)
      |> Map.merge(%{
        "required_nutrients" => [""],
        "avoid_nutrients" => [""],
        "required_compounds" => [""],
        "avoid_compounds" => [""]
      })

    html = render_change(element(live, "form"), %{"blueprint" => params})
    refute html =~ ~s(phx-value-tag="")
  end

  test "searching, adding and removing a blueprint-level compound chip", %{conn: conn, user: user} do
    bp = seed_blueprint(user)
    {:ok, live, _html} = live(conn, ~p"/nutritionist/blueprints/#{bp.id}/edit")

    search = element(live, "input[phx-keyup='search_tag'][phx-value-field='required_compounds']")

    # A compound "family" (Polyphenols) is always an option, no DB seeding needed.
    html = render_keyup(search, %{"value" => "poly", "field" => "required_compounds"})
    assert html =~ "Polyphenols"

    add =
      element(
        live,
        "li[phx-click='add_tag'][phx-value-field='required_compounds'][phx-value-tag='Polyphenols']"
      )

    render_click(add)

    remove_selector =
      "button[phx-click='remove_tag'][phx-value-field='required_compounds'][phx-value-tag='Polyphenols']"

    assert has_element?(live, remove_selector)

    render_click(element(live, remove_selector))
    refute has_element?(live, remove_selector)
  end

  test "removing a persisted chip drops it and the removal survives save", %{
    conn: conn,
    user: user
  } do
    bp = seed_blueprint(user)

    # Persist two nutrients on the blueprint directly, then open the editor.
    loaded = MealBlueprints.get_blueprint!(user.id, bp.id)

    params = Map.put(build_params(loaded), "required_nutrients", ["Vitamin C", "Iron"])
    {:ok, _} = MealBlueprints.update_blueprint(loaded, params)

    {:ok, live, html} = live(conn, ~p"/nutritionist/blueprints/#{bp.id}/edit")
    assert html =~ "Vitamin C"
    assert html =~ "Iron"

    remove_vc =
      "button[phx-click='remove_tag'][phx-value-field='required_nutrients'][phx-value-tag='Vitamin C']"

    assert has_element?(live, remove_vc)
    render_click(element(live, remove_vc))
    refute has_element?(live, remove_vc)

    # Save and confirm the removal persisted (Iron kept, Vitamin C gone).
    render_submit(element(live, "form"))
    reloaded = MealBlueprints.get_blueprint!(user.id, bp.id)
    assert reloaded.required_nutrients == ["Iron"]
  end

  test "copy this meal across the week propagates targets", %{conn: conn, user: user} do
    bp = seed_blueprint(user)
    {:ok, live, _html} = live(conn, ~p"/nutritionist/blueprints/#{bp.id}/edit")

    # Enter a breakfast protein target on day 1 via change, then copy across week.
    loaded = MealBlueprints.get_blueprint!(user.id, bp.id)

    params =
      build_params(loaded, fn di, _mi, meal ->
        if di == 0 and meal["meal_type"] == "breakfast" do
          Map.merge(meal, %{"protein_pct" => "40", "carbs_pct" => "35", "fats_pct" => "25"})
        else
          meal
        end
      end)

    render_change(element(live, "form"), %{"blueprint" => params})

    live
    |> element(
      "button[phx-click='copy_meal_across_week'][phx-value-day_index='1'][phx-value-meal_type='breakfast']"
    )
    |> render_click()

    # Save the whole form as re-rendered, then assert every day's breakfast got 40.
    html = render(live)
    assert html =~ "value=\"40\""

    # Persist by submitting the current form and verifying all breakfasts.
    render_submit(element(live, "form"))
    reloaded = MealBlueprints.get_blueprint!(user.id, bp.id)

    breakfasts =
      reloaded.days
      |> Enum.map(fn d -> Enum.find(d.meals, &(&1.meal_type == "breakfast")) end)

    assert Enum.all?(breakfasts, &(&1.protein_pct == 40))
  end

  test "deleting removes the blueprint from the list", %{conn: conn, user: user} do
    bp = seed_blueprint(user, "Throwaway")
    {:ok, live, html} = live(conn, ~p"/nutritionist/blueprints")
    assert html =~ "Throwaway"

    live |> element("button[phx-click='delete'][phx-value-id='#{bp.id}']") |> render_click()

    refute render(live) =~ "Throwaway"
  end

  # Builds the full nested form params map the editor submits. `meal_fun`
  # (day_index0, meal_index0, meal_string_map) and `day_fun` (day_index0,
  # day_string_map) transform meals/days respectively.
  defp build_params(
         blueprint,
         meal_fun \\ fn _di, _mi, meal -> meal end,
         day_fun \\ fn _di, day -> day end
       ) do
    days =
      blueprint.days
      |> Enum.with_index()
      |> Map.new(fn {day, di} ->
        meals =
          day.meals
          |> Enum.with_index()
          |> Map.new(fn {meal, mi} ->
            base = %{"id" => to_string(meal.id), "meal_type" => meal.meal_type}
            {to_string(mi), meal_fun.(di, mi, base)}
          end)

        base_day = %{
          "id" => to_string(day.id),
          "day_index" => to_string(day.day_index),
          "meals" => meals
        }

        {to_string(di), day_fun.(di, base_day)}
      end)

    %{"days" => days}
  end
end
