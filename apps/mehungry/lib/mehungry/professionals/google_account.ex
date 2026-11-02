defmodule Mehungry.Professionals.GoogleAccount do
  @moduledoc """
  A nutritionist's connected Google Calendar (OAuth tokens + target calendar).

  One row per professional. Holds the long-lived `refresh_token` (obtained via a
  separate `access_type=offline` consent, distinct from the login OAuth flow) and
  the short-lived `access_token`/`token_expires_at` that the calendar client
  refreshes on demand.

  Tokens are stored in plaintext columns to match the app's existing
  provider-token practice (`users.instagram_token` etc.); encrypting them is a
  tracked follow-up.
  """
  use Ecto.Schema
  import Ecto.Changeset

  # Treat a token as expired a minute early so an in-flight call never races the
  # boundary.
  @expiry_skew_seconds 60

  schema "professional_google_accounts" do
    field :access_token, :string
    field :refresh_token, :string
    field :token_expires_at, :utc_datetime
    field :scope, :string
    field :calendar_id, :string, default: "primary"
    field :connected_at, :utc_datetime
    field :busy_synced_at, :utc_datetime
    field :sync_token, :string

    belongs_to :professional, Mehungry.Accounts.User

    timestamps()
  end

  @doc "Changeset for connecting/updating a Google Calendar account."
  def changeset(account, attrs) do
    account
    |> cast(attrs, [
      :professional_id,
      :access_token,
      :refresh_token,
      :token_expires_at,
      :scope,
      :calendar_id,
      :connected_at,
      :busy_synced_at,
      :sync_token
    ])
    |> validate_required([:professional_id])
    |> foreign_key_constraint(:professional_id)
    |> unique_constraint(:professional_id)
  end

  @doc """
  Whether the stored access token is missing or past its expiry (with skew).
  A `nil` expiry is treated as expired so we refresh before first use.
  """
  def access_token_expired?(%__MODULE__{} = account, now \\ DateTime.utc_now()) do
    cond do
      is_nil(account.access_token) -> true
      is_nil(account.token_expires_at) -> true
      true -> DateTime.diff(account.token_expires_at, now) <= @expiry_skew_seconds
    end
  end

  @doc """
  Builds the token-column attrs from a Google OAuth token response map
  (`"access_token"`, `"expires_in"`, optional `"refresh_token"`, `"scope"`).
  Omits `refresh_token` when absent so a refresh response (which Google sends
  without one) never clobbers the stored long-lived token.
  """
  def token_attrs(response, now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)

    expires_at =
      case response["expires_in"] do
        secs when is_integer(secs) -> DateTime.add(now, secs, :second)
        _ -> nil
      end

    %{
      "access_token" => response["access_token"],
      "token_expires_at" => expires_at,
      "scope" => response["scope"]
    }
    |> maybe_put("refresh_token", response["refresh_token"])
  end

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, _key, ""), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)
end
