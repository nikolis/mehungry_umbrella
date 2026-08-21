defmodule MehungryWeb.ProfileRestrictionTest do
  @moduledoc """
  The diet selector on the profile is the single control for dietary-restriction
  category rules: it persists a `diet` on the profile, regenerates the underlying
  category rules on save, and drives the Home/Browse feed filter via `diet_mode`.
  """
  use MehungryWeb.ConnCase

  import Mehungry.FoodFixtures
  import Phoenix.LiveViewTest
  alias Mehungry.Accounts
  alias Mehungry.Food

  setup [:register_and_log_in_user]

  defp setup_diet_world(user) do
    # Categories whose names match the vegetarian/vegan diet keywords, so
    # regenerating rules from a diet actually produces exclusion rows.
    for name <- ~w(fish Poultry Pork Sausages Lamb Beef Dairy) do
      {:ok, _} = Food.create_category(%{name: name})
    end

    {:ok, _} = Mehungry.Repo.insert(%Mehungry.Food.FoodRestrictionType{title: "Absolutely not"})

    up = Accounts.get_user_profile_by_user_id(user.id)
    Accounts.update_user_profile(up, %{alias: "orig", intro: "hi", onboarding_level: 1})
  end

  defp edit_profile(conn) do
    live(conn, Routes.profile_index_path(conn, :index) <> "?tab=edit_profile")
  end

  test "selecting a diet persists it, regenerates rules, and sets diet_mode", %{
    conn: conn,
    user: user
  } do
    setup_diet_world(user)
    assert Accounts.diet_mode(user) == nil

    {:ok, view, _} = edit_profile(conn)

    view |> element("button[phx-value-diet=vegetarian]") |> render_click()
    view |> element("#user_profile-form") |> render_submit(%{"user_profile" => %{}})

    reloaded = Accounts.get_user_profile_by_user_id(user.id)
    assert reloaded.diet == "vegetarian"
    assert length(reloaded.user_category_rules) > 0
    assert Accounts.diet_mode(user) == :vegetarian
  end

  test "the saved diet is reflected as selected when the form is reopened", %{
    conn: conn,
    user: user
  } do
    setup_diet_world(user)
    {:ok, view, _} = edit_profile(conn)
    view |> element("button[phx-value-diet=vegan]") |> render_click()
    view |> element("#user_profile-form") |> render_submit(%{"user_profile" => %{}})

    # Reopen the form: the persisted diet drives the initial selection.
    {:ok, _view2, html} = edit_profile(conn)
    assert html =~ "✓ Vegan"
    assert Accounts.diet_mode(user) == :vegan
  end

  test "switching to omnivore clears the generated rules", %{conn: conn, user: user} do
    setup_diet_world(user)

    {:ok, view, _} = edit_profile(conn)
    view |> element("button[phx-value-diet=vegan]") |> render_click()
    view |> element("#user_profile-form") |> render_submit(%{"user_profile" => %{}})
    assert length(Accounts.get_user_profile_by_user_id(user.id).user_category_rules) > 0

    {:ok, view2, _} = edit_profile(conn)
    view2 |> element("button[phx-value-diet=omnivore]") |> render_click()
    view2 |> element("#user_profile-form") |> render_submit(%{"user_profile" => %{}})

    reloaded = Accounts.get_user_profile_by_user_id(user.id)
    assert reloaded.diet == "omnivore"
    assert reloaded.user_category_rules == []
    assert Accounts.diet_mode(user) == nil
  end

  test "diet_mode maps profile diet values", %{user: _user} do
    assert Accounts.diet_mode_for_diet("vegan") == :vegan
    assert Accounts.diet_mode_for_diet("vegetarian") == :vegetarian
    assert Accounts.diet_mode_for_diet("pescatarian") == nil
    assert Accounts.diet_mode_for_diet("omnivore") == nil
    assert Accounts.diet_mode_for_diet(nil) == nil
  end
end
