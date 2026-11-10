defmodule MehungryWeb.ProfileLive.ProgressTest do
  @moduledoc "The owner-only period-based progress journal on /profile?tab=progress."

  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.Accounts
  alias Mehungry.AccountsFixtures
  alias Mehungry.Professionals
  alias Mehungry.Progress

  setup [:register_and_log_in_user]

  setup %{user: user} do
    # Past the onboarding wizard so the profile renders its tabs.
    user.id
    |> Accounts.get_user_profile_by_user_id()
    |> Accounts.update_user_profile(%{onboarding_level: 1})

    :ok
  end

  test "first visit bootstraps a self period with the journal UI", %{conn: conn, user: user} do
    {:ok, _view, html} = live(conn, ~p"/profile?tab=progress")

    assert html =~ "self-tracked"
    assert html =~ "Diary"
    assert html =~ "Goals &amp; tracked metrics"
    assert html =~ "Start over"

    active = Progress.active_period(user.id)
    assert active.kind == "self"
  end

  test "logging an entry updates the diary and (with 2+ points) the chart", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/profile?tab=progress")

    view
    |> form("form[phx-submit=log_entry]", %{
      "entry" => %{"entry_date" => "2026-11-01", "weight_kg" => "80", "note" => "day one"}
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Entry saved."
    assert html =~ "day one"

    # A second dated point makes weight chartable → overlay chart + legend with
    # the latest value.
    view
    |> form("form[phx-submit=log_entry]", %{
      "entry" => %{"entry_date" => "2026-11-05", "weight_kg" => "79"}
    })
    |> render_submit()

    html = render(view)
    assert html =~ "<path"
    assert html =~ "79 kg"
    assert has_element?(view, ~s(button[phx-value-series="weight_kg"][aria-pressed="true"]))
    assert length(Progress.list_entries(user.id, Progress.active_period(user.id).id)) == 2
  end

  test "nutrition series from logged meals can be toggled onto the chart", %{
    conn: conn,
    user: user
  } do
    # The nutrition window is the period's own range, so the period must
    # already span the fixture meals (logged 1 and 3 days ago).
    {:ok, _} =
      Progress.ensure_active_period(user.id, %{"started_on" => Date.add(Date.utc_today(), -10)})

    seed_meals_with_nutrients(user)

    {:ok, view, html} = live(conn, ~p"/profile?tab=progress")

    # The nutrition chips render from the logged meals.
    assert html =~ "From your logged meals"
    assert has_element?(view, ~s(button[phx-value-series="nutrition_energy_kcal"]))

    # Toggle Energy on: it joins the chart + legend.
    view
    |> element(~s(button[phx-value-series="nutrition_energy_kcal"]))
    |> render_click()

    html = render(view)

    assert has_element?(
             view,
             ~s(button[phx-value-series="nutrition_energy_kcal"][aria-pressed="true"])
           )

    assert html =~ "kcal"
    assert html =~ "<path"

    # Toggle it back off.
    view
    |> element(~s(button[phx-value-series="nutrition_energy_kcal"]))
    |> render_click()

    assert has_element?(
             view,
             ~s(button[phx-value-series="nutrition_energy_kcal"][aria-pressed="false"])
           )

    # An unknown series key is ignored.
    assert render_click(view, "toggle_series", %{"series" => "bogus"}) =~ "From your logged meals"
  end

  test "typed entry values survive the re-renders a photo upload triggers", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/profile?tab=progress")

    # Picking a photo fires phx-change and re-renders the form (auto_upload
    # external). The draft round-trip must keep the typed values on screen —
    # regression: they reset to blank and the entry saved empty beside its photo.
    view
    |> form("form[phx-submit=log_entry]", %{
      "entry" => %{"entry_date" => "2026-11-05", "weight_kg" => "79.6", "note" => "with photo"}
    })
    |> render_change()

    html = render(view)
    assert html =~ ~s(value="2026-11-05")
    assert html =~ ~s(value="79.6")
    assert html =~ "with photo"
  end

  test "meals logged before the period start stay off its diagram", %{conn: conn, user: user} do
    # Period starts today; the fixture meals (1 and 3 days ago) predate it, so
    # no nutrition series reaches the 2 points it needs to chart. Two diary
    # entries keep the toggles section rendered (weight is chartable).
    {:ok, period} = Progress.ensure_active_period(user.id)
    seed_meals_with_nutrients(user)
    today = Date.utc_today()
    {:ok, _} = Progress.upsert_entry_by_date(user.id, period.id, today, %{"weight_kg" => 80.0})

    {:ok, _} =
      Progress.upsert_entry_by_date(user.id, period.id, Date.add(today, -1), %{
        "weight_kg" => 80.5
      })

    {:ok, view, html} = live(conn, ~p"/profile?tab=progress")

    assert html =~ "From your logged meals"
    assert has_element?(view, ~s(button[phx-value-series="weight_kg"]))
    refute has_element?(view, ~s(button[phx-value-series="nutrition_energy_kcal"]))
  end

  # Two days of logged meals carrying a known nutrient tree (1 and 3 days ago),
  # so every nutrition series has the 2 points it needs once the period spans
  # them.
  defp seed_meals_with_nutrients(user) do
    recipe = Mehungry.FoodFixtures.recipe_fixture(user)

    recipe
    |> Ecto.Changeset.change(
      nutrients: %{
        "Energy" => %{"name" => "Energy", "amount" => 800.0, "measurement_unit" => "kcal"},
        "Protein" => %{"name" => "Protein", "amount" => 40.0, "measurement_unit" => "g"},
        "Total Fat" => %{"name" => "Total Fat", "amount" => 30.0, "measurement_unit" => "g"}
      }
    )
    |> Mehungry.Repo.update!()

    rums = [
      %{
        recipe_id: recipe.id,
        consume_portions: recipe.servings,
        cooking_portions: recipe.servings
      }
    ]

    for days_ago <- [1, 3] do
      dt = NaiveDateTime.new!(Date.add(Date.utc_today(), -days_ago), ~T[12:00:00])

      Mehungry.HistoryFixtures.user_meal_fixture(%{
        user_id: user.id,
        start_dt: dt,
        recipe_user_meals: rums
      })
    end
  end

  test "reset closes the period and starts a new one", %{conn: conn, user: user} do
    {:ok, view, _} = live(conn, ~p"/profile?tab=progress")
    first = Progress.active_period(user.id)

    view |> element("button[phx-click=reset_period]") |> render_click()

    html = render(view)
    assert html =~ "Fresh start!"
    active = Progress.active_period(user.id)
    assert active.id != first.id
    # The closed period shows in the history list.
    assert html =~ "Progress history"
  end

  test "share toggle without a nutritionist flashes an error", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/profile?tab=progress")

    view |> element("button[phx-click=toggle_share]") |> render_click()
    assert render(view) =~ "You don&#39;t have a nutritionist to share with yet."
  end

  test "a nutritionist-aligned period pauses self-logging and shows the notice", %{
    conn: conn,
    user: user
  } do
    pro = AccountsFixtures.user_fixture()
    {:ok, inv} = Professionals.invite_client(pro.id, user.email)
    {:ok, _} = Professionals.accept_invitation(inv.id, user.id)

    {:ok, view, html} = live(conn, ~p"/profile?tab=progress")

    assert html =~ "Your nutritionist now tracks your progress"
    assert html =~ "with nutritionist"
    # No self-logging form on an aligned period.
    refute has_element?(view, "form[phx-submit=log_entry]")
    refute has_element?(view, "button[phx-click=reset_period]")
  end
end
