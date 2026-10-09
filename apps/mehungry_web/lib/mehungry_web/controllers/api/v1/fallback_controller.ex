defmodule MehungryWeb.Api.V1.FallbackController do
  @moduledoc """
  Translates `{:error, _}` tuples returned by `/api/v1` controller actions into
  the standard error envelope + status code (spec §1.2).
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(errors("Validation failed", changeset_fields(changeset)))
  end

  def call(conn, {:error, :not_found}) do
    conn |> put_status(:not_found) |> json(errors("Not found"))
  end

  def call(conn, {:error, :unauthorized}) do
    conn |> put_status(:unauthorized) |> json(errors("unauthorized"))
  end

  def call(conn, {:error, :forbidden}) do
    conn |> put_status(:forbidden) |> json(errors("forbidden"))
  end

  def call(conn, {:error, :quota_exceeded}) do
    conn
    |> put_status(:forbidden)
    |> json(%{errors: %{detail: "Quota reached for your plan", upgrade: true}})
  end

  def call(conn, {:error, :rate_limited}) do
    conn |> put_status(429) |> json(errors("Too many requests"))
  end

  def call(conn, {:error, :bad_request}) do
    conn |> put_status(:bad_request) |> json(errors("Bad request"))
  end

  def call(conn, {:error, message}) when is_binary(message) do
    conn |> put_status(:bad_request) |> json(errors(message))
  end

  # Any other domain error atom (e.g. :client_not_found, :already_invited) → 422.
  def call(conn, {:error, reason}) when is_atom(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(errors(reason |> to_string() |> String.replace("_", " ")))
  end

  defp changeset_fields(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
