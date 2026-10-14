defmodule Mehungry.ObanWorkers.PinterestTokenRefreshWorkerTest do
  use Mehungry.DataCase
  use Oban.Testing, repo: Mehungry.Repo

  import Mehungry.AccountsFixtures

  alias Mehungry.Accounts
  alias Mehungry.ObanWorkers.PinterestTokenRefreshWorker

  setup do
    on_exit(fn -> Application.delete_env(:mehungry, :pinterest_http_stub) end)
    %{user: user_fixture()}
  end

  defp set_token(user, token) do
    {:ok, user} = Accounts.update_user_tokens(user, %{"pinterest_token" => token})
    user
  end

  defp reload_token(user), do: Accounts.get_user!(user.id).pinterest_token

  defp echoing_stub(test_pid) do
    Application.put_env(:mehungry, :pinterest_http_stub,
      post: fn _url, body, _headers ->
        send(test_pid, {:refresh_called, body})
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{"access_token" => "refreshed", "expires_in" => 2_592_000})}}
      end
    )
  end

  test "refreshes a token with unknown expiry", %{user: user} do
    echoing_stub(self())
    user = set_token(user, %{"access_token" => "old", "refresh_token" => "r"})

    assert :ok = perform_job(PinterestTokenRefreshWorker, %{})

    assert_received {:refresh_called, _}
    assert reload_token(user)["access_token"] == "refreshed"
  end

  test "skips a token expiring far beyond the window", %{user: user} do
    echoing_stub(self())
    now = DateTime.utc_now()

    set_token(user, %{
      "access_token" => "far-out",
      "refresh_token" => "r",
      "expires_at" => DateTime.to_iso8601(DateTime.add(now, 25, :day)),
      "status" => "active"
    })

    assert :ok = perform_job(PinterestTokenRefreshWorker, %{})
    refute_received {:refresh_called, _}
  end

  test "refreshes a token inside the window", %{user: user} do
    echoing_stub(self())
    now = DateTime.utc_now()

    set_token(user, %{
      "access_token" => "due",
      "refresh_token" => "r",
      "expires_at" => DateTime.to_iso8601(DateTime.add(now, 5, :day)),
      "status" => "active"
    })

    assert :ok = perform_job(PinterestTokenRefreshWorker, %{})
    assert_received {:refresh_called, _}
  end

  test "skips tokens without a refresh token", %{user: user} do
    echoing_stub(self())
    set_token(user, %{"access_token" => "no-refresh"})

    assert :ok = perform_job(PinterestTokenRefreshWorker, %{})
    refute_received {:refresh_called, _}
  end
end
