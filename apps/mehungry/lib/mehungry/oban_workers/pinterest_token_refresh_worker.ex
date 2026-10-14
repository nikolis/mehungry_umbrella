defmodule Mehungry.ObanWorkers.PinterestTokenRefreshWorker do
  @moduledoc """
  Daily cron (01:45 UTC, before the 2am recipe generation run) that refreshes
  Pinterest access tokens before their ~30-day expiry, using the stored refresh
  token.

  A token is refreshed when it is refreshable (carries a refresh token, not
  stale/error) and either has no known expiry (legacy shape) or expires within
  the refresh window — so each token is refreshed roughly biweekly, leaving slack
  for daily retries before it actually dies. Per-user failures are logged but
  never fail the job: one bad account must not re-run refreshes for the healthy
  ones via Oban retries.
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3600]

  require Logger

  alias Mehungry.Social.Pinterest
  alias Mehungry.Social.Pinterest.Token

  @refresh_window_days 10

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()

    Pinterest.list_users_with_pinterest_tokens()
    |> Enum.filter(&needs_refresh?(&1, now))
    |> Enum.each(fn user ->
      case Pinterest.refresh_user_token(user) do
        {:ok, _user} ->
          Logger.info("[Pinterest] refreshed token for user #{user.id}")

        {:error, reason} ->
          Logger.error("[Pinterest] token refresh failed for user #{user.id}: #{inspect(reason)}")
      end
    end)

    :ok
  end

  defp needs_refresh?(user, now) do
    token = user.pinterest_token || %{}
    Token.refreshable?(token, now) and within_refresh_window?(token, now)
  end

  defp within_refresh_window?(token, now) do
    case Token.expires_at(token) do
      nil -> true
      expires_at -> DateTime.diff(expires_at, now, :day) < @refresh_window_days
    end
  end
end
