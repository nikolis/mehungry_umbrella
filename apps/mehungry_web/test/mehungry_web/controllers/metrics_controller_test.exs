defmodule MehungryWeb.MetricsControllerTest do
  use MehungryWeb.ConnCase, async: false

  defp token, do: Application.get_env(:mehungry, :metrics_api_token)

  test "GET /metrics without a token is rejected", %{conn: conn} do
    conn = get(conn, "/metrics")
    assert conn.status == 401
  end

  test "GET /metrics with a bad token is rejected", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer nope")
      |> get("/metrics")

    assert conn.status == 401
  end

  test "GET /metrics with the token returns Prometheus text exposition", %{conn: conn} do
    # Make a real request through the endpoint so PromEx's Phoenix plugin records
    # at least one HTTP sample from genuine (non-synthetic) telemetry metadata.
    get(conn, "/")

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token()}")
      |> get("/metrics")

    assert conn.status == 200
    assert ["text/plain" <> _] = get_resp_header(conn, "content-type")

    body = response(conn, 200)
    assert body =~ "# TYPE"
    assert body =~ "mehungry_web_prom_ex_phoenix_http_requests_total"
  end

  test "GET /beam_scope/metrics without a token is rejected", %{conn: conn} do
    conn = get(conn, "/beam_scope/metrics")
    assert conn.status == 401
  end

  test "GET /beam_scope/metrics with a bad token is rejected", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer nope")
      |> get("/beam_scope/metrics")

    assert conn.status == 401
  end

  test "GET /beam_scope/metrics with the token returns Prometheus text exposition", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token()}")
      |> get("/beam_scope/metrics")

    assert conn.status == 200
    assert ["text/plain" <> _] = get_resp_header(conn, "content-type")
  end
end
