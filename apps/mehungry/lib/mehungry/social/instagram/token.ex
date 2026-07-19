defmodule Mehungry.Social.Instagram.Token do
  @moduledoc """
  Pure helpers for the `instagram_token` map stored on the user.

  Token map shape (string keys, stored in the `users.instagram_token` jsonb column):

      %{
        "access_token" => "IGQV...",
        "user_id" => "17841400000000000",
        "token_type" => "bearer",
        "expires_in" => 5_184_000,
        "obtained_at" => "2026-07-18T10:00:00Z",
        "expires_at" => "2026-09-16T10:00:00Z",
        "last_refreshed_at" => "2026-07-18T10:00:00Z",
        "status" => "active",
        "last_refresh_error" => nil
      }

  Legacy tokens (stored before the lifecycle rework) only carry
  `access_token/user_id/token_type/expires_in` — they are treated as connected
  with unknown expiry until the first refresh rewrites them into the new shape.
  Maps that contain Instagram error JSON (saved by a historical bug in the
  exchange path) classify as `:error`.
  """

  @expiring_window_days 7
  @min_age_for_refresh_hours 24

  @error_keys ["error", "error_type", "error_message"]

  @doc """
  Builds the stored token map from a successful exchange/refresh API response.
  """
  def build(api_response, instagram_user_id, now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)

    %{
      "access_token" => api_response["access_token"],
      "user_id" => to_string(instagram_user_id),
      "token_type" => api_response["token_type"],
      "expires_in" => api_response["expires_in"],
      "obtained_at" => DateTime.to_iso8601(now),
      "expires_at" => compute_expires_at(api_response["expires_in"], now),
      "last_refreshed_at" => DateTime.to_iso8601(now),
      "status" => "active",
      "last_refresh_error" => nil
    }
  end

  @doc """
  Classifies a stored token map.

  Returns `:connected | :expiring | :stale | :error | :not_connected`.
  """
  def status(token, now \\ DateTime.utc_now())

  def status(token, now) when is_map(token) do
    cond do
      map_size(token) == 0 -> :not_connected
      Enum.any?(@error_keys, &Map.has_key?(token, &1)) -> :error
      token["status"] == "stale" -> :stale
      is_nil(token["access_token"]) -> :not_connected
      true -> status_from_expiry(expires_at(token), now)
    end
  end

  def status(_token, _now), do: :not_connected

  def connected?(token), do: status(token) in [:connected, :expiring]

  @doc """
  Parses the absolute expiry timestamp; nil for legacy tokens without one.
  """
  def expires_at(token) when is_map(token), do: parse_datetime(token["expires_at"])
  def expires_at(_token), do: nil

  @doc """
  Whether the token may be sent to the refresh endpoint: usable status and at
  least 24h old (Instagram rejects refreshing younger tokens). Legacy tokens
  without timestamps are considered refreshable — the API is the arbiter.
  """
  def refreshable?(token, now \\ DateTime.utc_now()) do
    case status(token, now) do
      s when s in [:connected, :expiring] ->
        case parse_datetime(token["last_refreshed_at"] || token["obtained_at"]) do
          nil -> true
          issued -> DateTime.diff(now, issued, :hour) >= @min_age_for_refresh_hours
        end

      _ ->
        false
    end
  end

  defp status_from_expiry(nil, _now), do: :connected

  defp status_from_expiry(expires_at, now) do
    cond do
      DateTime.compare(expires_at, now) != :gt -> :stale
      DateTime.diff(expires_at, now, :day) < @expiring_window_days -> :expiring
      true -> :connected
    end
  end

  defp compute_expires_at(expires_in, now) when is_integer(expires_in) do
    now |> DateTime.add(expires_in, :second) |> DateTime.to_iso8601()
  end

  defp compute_expires_at(_expires_in, _now), do: nil

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil
end
