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
    |> json(errors(gettext("Validation failed"), changeset_fields(changeset)))
  end

  def call(conn, {:error, :not_found}) do
    conn |> put_status(:not_found) |> json(errors(gettext("Not found")))
  end

  def call(conn, {:error, :unauthorized}) do
    conn |> put_status(:unauthorized) |> json(errors(gettext("unauthorized")))
  end

  def call(conn, {:error, :forbidden}) do
    conn |> put_status(:forbidden) |> json(errors(gettext("forbidden")))
  end

  def call(conn, {:error, :quota_exceeded}) do
    conn
    |> put_status(:forbidden)
    |> json(%{errors: %{detail: gettext("Quota reached for your plan"), upgrade: true}})
  end

  def call(conn, {:error, :rate_limited}) do
    conn |> put_status(429) |> json(errors(gettext("Too many requests")))
  end

  def call(conn, {:error, :bad_request}) do
    conn |> put_status(:bad_request) |> json(errors(gettext("Bad request")))
  end

  def call(conn, {:error, message}) when is_binary(message) do
    conn |> put_status(:bad_request) |> json(errors(message))
  end

  # Any other domain error atom (e.g. :client_not_found, :already_invited) → 422.
  # The humanized reason is translated when a matching msgid exists, otherwise
  # gettext returns the English fallback unchanged.
  def call(conn, {:error, reason}) when is_atom(reason) do
    detail = reason |> to_string() |> String.replace("_", " ")

    conn
    |> put_status(:unprocessable_entity)
    |> json(errors(Gettext.gettext(MehungryWeb.Gettext, detail)))
  end

  # Changeset field errors are interpolated and then translated through the
  # "errors" gettext domain — the same path as the web's
  # `CoreComponents.translate_error/1`, so Ecto validation messages ("can't be
  # blank", …) come back in the request locale.
  defp changeset_fields(changeset) do
    Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
  end

  defp translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(MehungryWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(MehungryWeb.Gettext, "errors", msg, opts)
    end
  end
end
