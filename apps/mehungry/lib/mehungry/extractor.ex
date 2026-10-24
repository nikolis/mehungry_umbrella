defmodule Mehungry.Extractor do
  @moduledoc """
  Context for the batch paper-analysis service (`mehungry_extractor`, `POST /analyze`).

  Owns the UI-managed connection config (`Extractor.Settings`, a singleton row):
  the service `base_url` and an optional `auth_token`. `Extractor.Client` reads the
  live connection from here via `connection/0`, so an admin can re-point the analyzer
  and set a token at `/professional/health` without a redeploy. When no row has been
  saved, it falls back to the `:extractor_base_url` / `:extractor_auth_token` config
  (`EXTRACTOR_BASE_URL` / `EXTRACTOR_AUTH_TOKEN` env vars).
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Extractor.Settings

  @default_base_url "http://127.0.0.1:8000"

  @doc "The persisted singleton settings row, or `nil` when none has been saved."
  def get_settings, do: Repo.one(from(s in Settings, order_by: [asc: s.id], limit: 1))

  @doc """
  The live `{base_url, auth_token}` for the analyze service. `base_url` has its
  trailing slash trimmed; `auth_token` is `nil` when unset. Prefers the saved row,
  falling back to config/env, then the built-in default.
  """
  def connection do
    settings = get_settings()

    base_url =
      (settings && settings.base_url) ||
        Application.get_env(:mehungry, :extractor_base_url) || @default_base_url

    auth_token =
      case settings do
        %Settings{auth_token: token} when is_binary(token) and token != "" ->
          token

        _ ->
          case Application.get_env(:mehungry, :extractor_auth_token) do
            token when is_binary(token) and token != "" -> token
            _ -> nil
          end
      end

    {String.trim_trailing(base_url, "/"), auth_token}
  end

  @doc "Upsert the singleton connection settings."
  def update_settings(attrs) do
    (get_settings() || %Settings{})
    |> Settings.changeset(attrs)
    |> Repo.insert_or_update()
  end
end
