defmodule Mehungry.Social.Pinterest.Token do
  @moduledoc """
  Pure helpers for the `pinterest_token` map stored on the user.

  Token map shape (string keys, stored in the `users.pinterest_token` jsonb column):

      %{
        "access_token" => "pina_...",
        "refresh_token" => "pinr_...",
        "scope" => "boards:read,boards:write,pins:read,pins:write",
        "obtained_at" => "2026-10-14T10:00:00Z",
        "expires_at" => "2026-11-13T10:00:00Z",
        "status" => "active",
        "last_refresh_error" => nil
      }

  Pinterest v5 access tokens are short-lived (~30 days) while the refresh token
  lives much longer (~1 year), so an expired access token can be refreshed as
  long as the refresh token is present.

  Legacy tokens stored before the lifecycle rework carry `expires_at` as the
  OAuth2 library's **unix integer** (or `nil`); `expires_at/1` tolerates both
  that and the normalized ISO8601 form so already-connected accounts keep
  working. Maps that contain Pinterest error JSON classify as `:error`.
  """

  @expiring_window_days 7

  @error_keys ["error", "error_type", "error_message", "error_description"]

  @doc """
  Builds the stored token map from an OAuth2 connect or a refresh-endpoint
  response. Accepts string keys. Prefers `expires_in` (seconds) when present,
  otherwise normalizes an `expires_at` (unix int or ISO8601) to ISO8601.
  """
  def build(attrs, now \\ DateTime.utc_now()) when is_map(attrs) do
    now = DateTime.truncate(now, :second)

    %{
      "access_token" => attrs["access_token"],
      "refresh_token" => attrs["refresh_token"],
      "scope" => attrs["scope"] || "",
      "obtained_at" => DateTime.to_iso8601(now),
      "expires_at" => compute_expires_at(attrs, now),
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
  Parses the absolute expiry timestamp, tolerating both a unix integer (legacy
  OAuth2 shape) and ISO8601. `nil` when absent/unparseable.
  """
  def expires_at(token) when is_map(token), do: parse_datetime(token["expires_at"])
  def expires_at(_token), do: nil

  @doc """
  Whether the token may be sent to the refresh endpoint: it carries a refresh
  token and has not been marked stale / is not an error map. An access token
  that has merely expired by time is still refreshable — the refresh token
  outlives it.
  """
  def refreshable?(token, _now \\ DateTime.utc_now())

  def refreshable?(token, _now) when is_map(token) do
    has_refresh_token?(token) and
      token["status"] != "stale" and
      not Enum.any?(@error_keys, &Map.has_key?(token, &1)) and
      not is_nil(token["access_token"])
  end

  def refreshable?(_token, _now), do: false

  defp has_refresh_token?(token) do
    is_binary(token["refresh_token"]) and token["refresh_token"] != ""
  end

  defp status_from_expiry(nil, _now), do: :connected

  defp status_from_expiry(expires_at, now) do
    cond do
      DateTime.compare(expires_at, now) != :gt -> :stale
      DateTime.diff(expires_at, now, :day) < @expiring_window_days -> :expiring
      true -> :connected
    end
  end

  defp compute_expires_at(attrs, now) do
    cond do
      is_integer(attrs["expires_in"]) ->
        now |> DateTime.add(attrs["expires_in"], :second) |> DateTime.to_iso8601()

      not is_nil(attrs["expires_at"]) ->
        normalize_timestamp(attrs["expires_at"])

      true ->
        nil
    end
  end

  defp normalize_timestamp(value) do
    case parse_datetime(value) do
      nil -> nil
      dt -> dt |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    end
  end

  defp parse_datetime(value) when is_integer(value) do
    case DateTime.from_unix(value) do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil
end
