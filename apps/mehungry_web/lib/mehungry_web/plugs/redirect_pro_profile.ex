defmodule MehungryWeb.Plugs.RedirectProProfile do
  @moduledoc """
  301-redirects a public professional's `/profile/:id` (and the localized
  `/:locale/profile/:id`) to their canonical public page
  `/nutritionists/:slug`.

  Nutritionists get a single, keyword-rich, indexable URL (part of the
  `/nutritionists` directory + `LocalBusiness`/`ItemList` cluster) instead of the
  opaque, `robots.txt`-disallowed `/profile/:id`. This consolidates link equity
  onto the slug page and keeps the thin `/profile` space out of the index.

  Non-professional profiles and every other path pass straight through (only a
  `/profile/:id`-shaped path triggers the single indexed lookup).
  """
  import Plug.Conn

  alias MehungryWeb.Locale
  alias Mehungry.Professionals
  alias Mehungry.Professionals.ProfessionalProfile

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: path_info} = conn, _opts) do
    case profile_id(path_info) do
      {locale, id} -> maybe_redirect(conn, locale, id)
      :no -> conn
    end
  end

  # /profile/:id and /:locale/profile/:id
  defp profile_id(["profile", id]), do: {nil, id}

  defp profile_id([locale, "profile", id]) do
    if Locale.supported?(locale), do: {locale, id}, else: :no
  end

  defp profile_id(_), do: :no

  defp maybe_redirect(conn, locale, id) do
    with {int_id, ""} <- Integer.parse(id),
         %ProfessionalProfile{is_public: true, slug: slug} when is_binary(slug) <-
           Professionals.get_professional_profile(int_id) do
      conn
      |> put_status(:moved_permanently)
      |> Phoenix.Controller.redirect(to: target_path(locale, slug))
      |> halt()
    else
      _ -> conn
    end
  end

  defp target_path(nil, slug), do: "/nutritionists/#{slug}"
  defp target_path(locale, slug), do: "/#{locale}/nutritionists/#{slug}"
end
