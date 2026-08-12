defmodule MehungryWeb.UserLanguageController do
  use MehungryWeb, :controller

  alias Mehungry.Accounts
  alias MehungryWeb.Locale

  def set(conn, %{"lang" => lang} = params) do
    if Locale.supported?(lang) do
      # Persist the preference for logged-in users (a secondary signal — the URL
      # locale is authoritative), then send them to the same page under the new
      # locale by swapping the prefix on the page they came from. Works for
      # anonymous visitors too, who have no profile to persist to.
      if user = conn.assigns[:current_user] do
        if profile = Accounts.get_user_profile_by_user_id(user.id) do
          Accounts.update_user_language(profile, lang)
        end
      end

      conn
      |> put_session("locale", lang)
      |> redirect(to: target_path(params["return_to"] || referer_path(conn), lang))
    else
      redirect(conn, to: "/")
    end
  end

  def set(conn, _params), do: redirect(conn, to: "/")

  defp target_path(nil, lang), do: "/#{lang}/home"

  defp target_path(path, lang) do
    case URI.parse(path) do
      %URI{path: nil} -> "/#{lang}/home"
      %URI{path: p, query: q} -> Locale.swap_path(if(q, do: "#{p}?#{q}", else: p), lang)
    end
  end

  defp referer_path(conn) do
    conn |> get_req_header("referer") |> List.first()
  end
end
