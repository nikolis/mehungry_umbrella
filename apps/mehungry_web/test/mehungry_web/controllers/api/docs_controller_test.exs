defmodule MehungryWeb.Api.DocsControllerTest do
  use MehungryWeb.ConnCase

  test "serves the OpenAPI spec without auth", %{conn: conn} do
    conn = get(conn, ~p"/api/docs/openapi.json")
    spec = json_response(conn, 200)

    assert spec["openapi"] =~ "3.0"
    assert get_in(spec, ["paths", "/api/foundemental_foods", "get", "operationId"]) ==
             "listFoundementalFoods"

    assert get_in(spec, ["components", "securitySchemes", "bearerAuth", "scheme"]) == "bearer"
  end

  test "serves the Swagger UI page", %{conn: conn} do
    conn = get(conn, ~p"/api/docs")
    html = html_response(conn, 200)

    assert html =~ "swagger-ui"
    assert html =~ "/api/docs/openapi.json"
  end
end
