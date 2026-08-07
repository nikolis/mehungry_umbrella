defmodule MehungryWeb.TestAccountsController do
  @moduledoc """
  URL-driven management of the deterministic third-party/bot test accounts
  (`Mehungry.Accounts.TestAccounts`).

      GET /test-accounts          -> current status (JSON)
      GET /test-accounts/seed     -> create any missing accounts
      GET /test-accounts/reset    -> delete all three + recreate fresh

  ## Access gate

  This endpoint creates pre-confirmed accounts, so it is guarded:

    * always allowed in `:dev` / `:test`
    * in any other environment (e.g. staging/prod) it is 404 unless the
      `TEST_ACCOUNTS_TOKEN` env var is set **and** the request carries a
      matching `?token=` query param.

  Responding 404 (not 403) hides the route's existence when unauthorized.
  """
  use MehungryWeb, :controller

  alias Mehungry.Accounts.TestAccounts

  plug :authorize

  def index(conn, _params), do: json(conn, %{accounts: TestAccounts.status()})

  def seed(conn, _params) do
    TestAccounts.seed()
    json(conn, %{action: "seed", password: TestAccounts.password(), accounts: TestAccounts.status()})
  end

  def reset(conn, _params) do
    TestAccounts.reset()
    json(conn, %{action: "reset", password: TestAccounts.password(), accounts: TestAccounts.status()})
  end

  defp authorize(conn, _opts) do
    if allowed?(conn) do
      conn
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: "not found"})
      |> halt()
    end
  end

  defp allowed?(conn) do
    Application.get_env(:mehungry_web, :test_accounts_env) in [:dev, :test] or
      token_ok?(conn)
  end

  defp token_ok?(conn) do
    case Application.get_env(:mehungry_web, :test_accounts_token) do
      token when is_binary(token) and token != "" ->
        Plug.Crypto.secure_compare(token, conn.params["token"] || "")

      _ ->
        false
    end
  end
end
