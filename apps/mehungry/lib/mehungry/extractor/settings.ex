defmodule Mehungry.Extractor.Settings do
  @moduledoc """
  UI-managed connection config (singleton) for the batch paper-analysis service
  (`mehungry_extractor`, `POST /analyze`): its `base_url` and an optional
  `auth_token`. Read through `Mehungry.Extractor`, which falls back to the
  `EXTRACTOR_BASE_URL` env/config when no row has been saved yet.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "extractor_settings" do
    field :base_url, :string
    field :auth_token, :string

    timestamps()
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:base_url, :auth_token])
    |> update_change(:base_url, &blank_to_nil/1)
    |> update_change(:auth_token, &blank_to_nil/1)
    |> validate_required([:base_url])
    |> validate_http_url(:base_url)
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp validate_http_url(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case URI.new(value) do
        {:ok, %URI{scheme: scheme, host: host}}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _ ->
          [{field, "must be a valid http(s) URL"}]
      end
    end)
  end
end
