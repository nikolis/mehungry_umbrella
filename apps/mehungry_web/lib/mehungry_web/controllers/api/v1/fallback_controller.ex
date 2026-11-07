defmodule MehungryWeb.Api.V1.FallbackController do
  @moduledoc """
  Translates `{:error, _}` tuples returned by `/api/v1` controller actions into
  the standard error envelope + status code (spec §1.2).
  """
  use MehungryWeb, :controller

  require Logger

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

  # Art. 9 consent gate on the clinical endpoints — a machine-readable detail
  # token the client matches on (not a humanized string).
  def call(conn, {:error, :consent_required}) do
    conn |> put_status(:forbidden) |> json(errors("consent_required"))
  end

  # Grant attempt whose version is not the current server version (stale client).
  def call(conn, {:error, :consent_version_mismatch}) do
    conn |> put_status(:unprocessable_entity) |> json(errors("consent_version_mismatch"))
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

  # A failed call to an upstream service (e.g. object storage during an image
  # upload). The specific reason is logged at the call site; the client gets a
  # clean 502 so it can retry rather than a raw crash.
  def call(conn, {:error, :upstream_error}) do
    conn
    |> put_status(:bad_gateway)
    |> json(errors(gettext("Service temporarily unavailable. Please try again.")))
  end

  # Stripe Checkout session creation failed while setting up a paid booking
  # (`Professionals.request_appointment/4` → `maybe_start_payment`). Return a
  # retryable 502 rather than letting the `{:payment_setup_failed, _}` tuple fall
  # through to the catch-all 500.
  def call(conn, {:error, {:payment_setup_failed, _reason}}) do
    conn
    |> put_status(:bad_gateway)
    |> json(errors(gettext("Payment could not be set up. Please try again.")))
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

  # Safety net: an unexpected error term (e.g. a `{:http_error, status, body}`
  # tuple leaked from a lower layer) must never crash the fallback itself and
  # become a raw 500 HTML page. Log it and return a clean JSON 500 envelope.
  def call(conn, {:error, reason}) do
    Logger.error("Unhandled API error term: #{inspect(reason)}")

    conn
    |> put_status(:internal_server_error)
    |> json(errors(gettext("Something went wrong. Please try again.")))
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
