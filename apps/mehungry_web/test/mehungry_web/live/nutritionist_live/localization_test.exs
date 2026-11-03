defmodule MehungryWeb.NutritionistLive.LocalizationTest do
  @moduledoc """
  The nutritionist workspace is localized (WS1-WS5): it runs the :browser
  pipeline (SetLocale) and the live_session lists RestoreLocale first, so the
  connected LiveView renders in the nutritionist's locale — resolved from the
  session (persisted from the profile preference / language switcher), with no
  URL `/:locale` prefix. These assert the chrome + nav render in Greek when the
  session locale is `el`, and in English otherwise.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  alias Mehungry.Subscriptions

  setup %{conn: conn} do
    nutritionist = user_fixture()
    {:ok, _} = Subscriptions.upsert_subscription(nutritionist.id, %{tier: "pro", status: "active"})
    %{conn: conn, nutritionist: nutritionist}
  end

  test "renders the workspace chrome in Greek when the session locale is el", %{
    conn: conn,
    nutritionist: nutritionist
  } do
    {:ok, _view, html} =
      conn
      |> log_in_user(nutritionist)
      |> Plug.Conn.put_session("locale", "el")
      |> live(~p"/nutritionist")

    # Sidebar chrome + nav labels (gettext) resolve to Greek.
    assert html =~ "Πίνακας διατροφολόγου"
    assert html =~ "Πελάτες"
    assert html =~ "Επιστροφή στην εφαρμογή"
    refute html =~ "Nutritionist Panel"
  end

  test "renders in English by default", %{conn: conn, nutritionist: nutritionist} do
    {:ok, _view, html} =
      conn
      |> log_in_user(nutritionist)
      |> live(~p"/nutritionist")

    assert html =~ "Nutritionist Panel"
    assert html =~ "My Clients"
    refute html =~ "Πίνακας διατροφολόγου"
  end
end
