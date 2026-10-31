defmodule MehungryWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use MehungryWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import MehungryWeb.ConnCase

      alias MehungryWeb.Router.Helpers, as: Routes

      # The default endpoint for testing
      @endpoint MehungryWeb.Endpoint
      use MehungryWeb, :verified_routes
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Mehungry.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Mehungry.Repo, {:shared, self()})
    end

    # The reference cache (measurement units, categories, …) is global, not
    # sandboxed — clear it so one test's cached rows can't leak into the next.
    Mehungry.ReferenceCache.clear()

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection and a registered user in the
  test context.
  """
  def register_and_log_in_user(%{conn: conn}) do
    user = Mehungry.AccountsFixtures.user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user) do
    user = confirm_user_for_test(user)
    token = Mehungry.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  # Authenticated routes now require a confirmed email
  # (MehungryWeb.UserAuth.require_authenticated_user), so a logged-in test user
  # must be confirmed. Password fixtures are created unconfirmed.
  defp confirm_user_for_test(%{confirmed_at: nil} = user) do
    {:ok, %{user: user}} =
      Mehungry.Repo.transaction(Mehungry.Accounts.confirm_user_multi(user))

    user
  end

  defp confirm_user_for_test(user), do: user

  @doc """
  Setup helper that registers a user and authenticates `conn` for the mobile
  `/api/v1` surface with a bearer token.

      setup :register_and_log_in_api_user

  Stores an updated connection (with the `Authorization: Bearer` header + JSON
  accept) and the registered user in the test context.
  """
  def register_and_log_in_api_user(%{conn: conn}) do
    user = Mehungry.AccountsFixtures.user_fixture() |> confirm_user_for_test()
    %{conn: put_api_token(conn, user), user: user}
  end

  @doc """
  Puts a valid mobile bearer token for `user` (and a JSON accept header) on `conn`.
  """
  def put_api_token(conn, user) do
    token = MehungryWeb.Api.Auth.mint(user)

    conn
    |> Plug.Conn.put_req_header("authorization", "Bearer " <> token)
    |> Plug.Conn.put_req_header("accept", "application/json")
  end
end
