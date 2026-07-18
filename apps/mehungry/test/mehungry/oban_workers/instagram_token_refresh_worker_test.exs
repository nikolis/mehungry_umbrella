defmodule Mehungry.ObanWorkers.InstagramTokenRefreshWorkerTest do
  use Mehungry.DataCase
  use Oban.Testing, repo: Mehungry.Repo

  import Mehungry.AccountsFixtures

  alias Mehungry.Accounts
  alias Mehungry.Instagram.Token
  alias Mehungry.ObanWorkers.InstagramTokenRefreshWorker

  setup do
    on_exit(fn -> Application.delete_env(:mehungry, :instagram_stub) end)
    %{user: user_fixture()}
  end

  defp set_token(user, token) do
    {:ok, user} = Accounts.update_user_tokens(user, %{"instagram_token" => token})
    user
  end

  defp reload_token(user), do: Accounts.get_user!(user.id).instagram_token

  defp echoing_stub(test_pid) do
    Application.put_env(:mehungry, :instagram_stub,
      refresh_long_lived_token: fn token ->
        send(test_pid, {:refresh_called, token})
        {:ok, %{"access_token" => "refreshed", "token_type" => "bearer", "expires_in" => 5_184_000}}
      end
    )
  end

  test "refreshes legacy tokens into the new shape", %{user: user} do
    user = set_token(user, %{"access_token" => "legacy", "user_id" => "42"})

    assert :ok = perform_job(InstagramTokenRefreshWorker, %{})

    token = reload_token(user)
    assert token["access_token"] == "stub-refreshed"
    assert token["expires_at"]
    assert token["status"] == "active"
  end

  test "skips tokens younger than 24h", %{user: user} do
    echoing_stub(self())

    set_token(
      user,
      Token.build(%{"access_token" => "fresh", "expires_in" => 5_184_000}, "42")
    )

    assert :ok = perform_job(InstagramTokenRefreshWorker, %{})
    refute_received {:refresh_called, _}
  end

  test "skips tokens expiring more than 45 days out", %{user: user} do
    echoing_stub(self())
    now = DateTime.utc_now()

    set_token(user, %{
      "access_token" => "far-out",
      "user_id" => "42",
      "obtained_at" => DateTime.to_iso8601(DateTime.add(now, -3, :day)),
      "last_refreshed_at" => DateTime.to_iso8601(DateTime.add(now, -3, :day)),
      "expires_at" => DateTime.to_iso8601(DateTime.add(now, 57, :day)),
      "status" => "active"
    })

    assert :ok = perform_job(InstagramTokenRefreshWorker, %{})
    refute_received {:refresh_called, _}
  end

  test "refreshes tokens inside the 45-day window", %{user: user} do
    echoing_stub(self())
    now = DateTime.utc_now()

    set_token(user, %{
      "access_token" => "due",
      "user_id" => "42",
      "obtained_at" => DateTime.to_iso8601(DateTime.add(now, -30, :day)),
      "last_refreshed_at" => DateTime.to_iso8601(DateTime.add(now, -30, :day)),
      "expires_at" => DateTime.to_iso8601(DateTime.add(now, 30, :day)),
      "status" => "active"
    })

    assert :ok = perform_job(InstagramTokenRefreshWorker, %{})
    assert_received {:refresh_called, "due"}
  end

  test "returns :ok despite a failing refresh and marks invalid tokens stale", %{user: user} do
    user = set_token(user, %{"access_token" => "dead", "user_id" => "42"})

    Application.put_env(:mehungry, :instagram_stub,
      refresh_long_lived_token: fn _token ->
        {:error,
         {:http_error, 400,
          %{"error" => %{"type" => "OAuthException", "code" => 190, "message" => "expired"}}}}
      end
    )

    assert :ok = perform_job(InstagramTokenRefreshWorker, %{})
    assert Token.status(reload_token(user)) == :stale
  end
end
