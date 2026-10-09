defmodule MehungryWeb.Api.V1.JSON.Helpers do
  @moduledoc """
  Shared helpers for building the `/api/v1` response envelope (spec §1.1).

      Success (single): %{data: ...}
      Success (list):   %{data: [...], meta: %{page:, page_size:, has_more:}}
      Error:            %{errors: %{detail:, fields:}}

  JSON view modules (`*JSON`) return plain maps that get passed to
  `Phoenix.Controller.json/2`; Ecto structs are never encoded directly.
  """

  @doc "Wrap a single resource."
  def data(payload), do: %{data: payload}

  @doc "Wrap a list resource with pagination/meta."
  def data(payload, meta) when is_map(meta), do: %{data: payload, meta: meta}

  @doc "Build an error envelope."
  def errors(detail) when is_binary(detail), do: %{errors: %{detail: detail}}

  def errors(detail, fields) when is_binary(detail) and is_map(fields) do
    %{errors: %{detail: detail, fields: fields}}
  end

  @doc """
  Serialize a naive datetime without a zone (spec §1 — `start_dt`/`end_dt` on
  meals/baskets are stored naive and emitted as `2026-08-10T14:30:00`).
  """
  def naive(nil), do: nil
  def naive(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)

  @doc "Serialize a UTC timestamp as an ISO-8601 Z string."
  def utc(nil), do: nil
  def utc(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt) <> "Z"
  def utc(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
