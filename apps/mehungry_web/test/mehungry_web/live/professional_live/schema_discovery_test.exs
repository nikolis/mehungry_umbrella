defmodule MehungryWeb.ProfessionalLive.SchemaDiscoveryTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    conn = log_in_user(conn, admin)

    # Names carrying distinct size values (an un-captured dimension) so the page
    # has something to propose and tabulate.
    for name <- [
          "large gala apple",
          "medium fuji apple",
          "small russet apple",
          "jumbo hass avocado",
          "mini navel orange",
          "giant valencia orange"
        ] do
      ingredient_fixture(%{name: name})
    end

    %{conn: conn}
  end

  test "renders the report sections", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/schema-discovery")

    assert html =~ "Schema Discovery"
    assert html =~ "Dimensions"
    assert html =~ "Proposed migrations"
    assert html =~ "Parse fill-rate"
  end

  test "Recompute re-runs without error", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/schema-discovery")

    html = view |> element("button", "Recompute") |> render_click()
    assert html =~ "Schema Discovery"
  end
end
