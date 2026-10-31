defmodule MehungryWeb.LegalPagesTest do
  use MehungryWeb.ConnCase, async: true

  # Regression guard: these static legal pages render via controllers whose
  # view module must be set explicitly with `put_view/2` — the legacy
  # `use Phoenix.Controller, namespace:` setup resolves `render(conn, :index)`
  # to a `*View` module that doesn't exist, which 500s. See the `*Controller`
  # modules under controllers/.

  test "GET /terms renders", %{conn: conn} do
    conn = get(conn, "/terms")
    assert html_response(conn, 200) =~ "Terms of Service"
  end

  test "GET /cookies renders", %{conn: conn} do
    conn = get(conn, "/cookies")
    assert html_response(conn, 200)
  end

  test "GET /legal renders", %{conn: conn} do
    conn = get(conn, "/legal")
    assert html_response(conn, 200)
  end
end
