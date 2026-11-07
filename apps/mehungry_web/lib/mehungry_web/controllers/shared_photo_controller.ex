defmodule MehungryWeb.SharedPhotoController do
  @moduledoc """
  Public resolver for progress-photo share links (`GET /shared/photos/:token`).

  Progress photos live in the **private** storage bucket; the only public way
  in is this explicitly-created, revocable token (`Progress.share_photo/2`).
  Each hit 302s to a *fresh, short-lived* signed URL — nothing permanent is
  ever handed out, so unsharing revokes access immediately (modulo the few
  minutes an already-issued signed URL stays valid).
  """
  use MehungryWeb, :controller

  alias Mehungry.Progress

  def show(conn, %{"token" => token}) do
    case Progress.shared_photo_url(token) do
      {:ok, url} ->
        conn
        # Never let the redirect target (a capability URL) be cached or indexed.
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_header("x-robots-tag", "noindex, nofollow")
        |> redirect(external: url)

      _ ->
        send_resp(conn, :not_found, "Not found")
    end
  end
end
