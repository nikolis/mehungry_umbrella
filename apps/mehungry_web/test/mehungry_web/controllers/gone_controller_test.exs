defmodule MehungryWeb.GoneControllerTest do
  use MehungryWeb.ConnCase, async: true

  describe "retired public condition pages" do
    test "GET /conditions/:id returns 410 Gone", %{conn: conn} do
      conn = get(conn, "/conditions/13")
      assert response(conn, 410) =~ "Gone"
    end

    test "GET /:locale/conditions/:id returns 410 Gone (the stale indexed form)", %{conn: conn} do
      conn = get(conn, "/en/conditions/13")
      assert response(conn, 410) =~ "Gone"
    end

    test "GET /:locale/conditions (index) returns 410 Gone", %{conn: conn} do
      conn = get(conn, "/el/conditions")
      assert response(conn, 410) =~ "Gone"
    end

    test "the food sub-path returns 410 Gone", %{conn: conn} do
      conn = get(conn, "/en/conditions/13/food/7")
      assert response(conn, 410) =~ "Gone"
    end
  end

  describe "does not shadow real locale routes" do
    test "/:locale/foods is unaffected (not a condition path)", %{conn: conn} do
      # /foods is a real public page; must not be swallowed by /:locale/conditions.
      conn = get(conn, "/en/foods")
      assert conn.status == 200
      assert response_content_type(conn, :html)
    end
  end
end
