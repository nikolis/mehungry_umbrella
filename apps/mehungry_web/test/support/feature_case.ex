defmodule MehungryWeb.FeatureCase do
  @moduledoc """
  inspiration by https://www.youtube.com/watch?v=XP9ijeDslaU&ab_channel=LiveViewMastery
  """
  use ExUnit.CaseTemplate
  use Wallaby.DSL

  using do
    quote do
      use Wallaby.DSL
      use Wallaby.Feature
      import Wallaby.Query, only: [css: 2, text_field: 1, button: 1]
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Mehungry.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Mehungry.Repo, {:shared, self()})
    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(Mehungry.Repo, self())
    {:ok, session} = Wallaby.start_session(metadata: metadata)
    # {session, user} = log_in(%{session: session})
    {:ok, session: session}
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
    token = Mehungry.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
