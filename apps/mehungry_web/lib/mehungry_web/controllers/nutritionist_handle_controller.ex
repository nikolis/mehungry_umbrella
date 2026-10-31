defmodule MehungryWeb.NutritionistHandleController do
  @moduledoc """
  Serves the nutritionist personal short link `/@<handle>`.

  This is a **vanity entry point**, not a page: it 301-redirects to the
  canonical, SEO-indexed public profile `/:locale/nutritionists/:slug`, so the
  handle URL never competes with the slug for search signal. See
  `docs/features/professionals/personal_handle.md`.

  The route is a lowest-priority single-segment catch-all (`/:handle`), so we
  only honour segments that actually start with `@`; anything else 404s exactly
  as an unknown path would, and never shadows a real route (those are declared
  earlier and match first).
  """
  use MehungryWeb, :controller

  alias Mehungry.Professionals

  def show(conn, %{"handle" => "@" <> handle}) when handle != "" do
    case Professionals.get_public_professional_by_handle(handle) do
      %{slug: slug} when is_binary(slug) ->
        locale = MehungryWeb.Locale.detect(conn)

        conn
        |> put_status(:moved_permanently)
        |> redirect(to: "/#{locale}/nutritionists/#{slug}")
        |> halt()

      _ ->
        not_found(conn)
    end
  end

  def show(conn, _params), do: not_found(conn)

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(MehungryWeb.ErrorView)
    |> render("404.html")
    |> halt()
  end
end
