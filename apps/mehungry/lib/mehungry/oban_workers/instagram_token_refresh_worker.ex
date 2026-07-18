defmodule Mehungry.ObanWorkers.InstagramTokenRefreshWorker do
  @moduledoc """
  Daily cron (01:30 UTC, before the 2am recipe generation run) that refreshes
  Instagram long-lived tokens before their ~60-day expiry.

  A token is refreshed when it is refreshable (usable status, ≥24h old) and
  either has no known expiry (legacy shape) or expires within 45 days — so each
  token is refreshed roughly biweekly, leaving ~45 days of daily-retry slack
  before it actually dies. Per-user failures are logged but never fail the job:
  one bad account must not re-run refreshes for the healthy ones via Oban
  retries.
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3600]

  require Logger

  alias Mehungry.Instagram
  alias Mehungry.Instagram.Token

  @refresh_window_days 45

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()

    Instagram.list_users_with_tokens()
    |> Enum.filter(&needs_refresh?(&1, now))
    |> Enum.each(fn user ->
      case Instagram.refresh_user_token(user) do
        {:ok, _user} ->
          Logger.info("[Instagram] refreshed token for user #{user.id}")

        {:error, reason} ->
          Logger.error(
            "[Instagram] token refresh failed for user #{user.id}: #{inspect(reason)}"
          )
      end
    end)

    :ok
  end

  defp needs_refresh?(user, now) do
    token = user.instagram_token || %{}
    Token.refreshable?(token, now) and within_refresh_window?(token, now)
  end

  defp within_refresh_window?(token, now) do
    case Token.expires_at(token) do
      nil -> true
      expires_at -> DateTime.diff(expires_at, now, :day) < @refresh_window_days
    end
  end
end
