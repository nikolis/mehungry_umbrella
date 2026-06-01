defmodule MehungryWeb.UserLanguageController do
  use MehungryWeb, :controller

  alias Mehungry.Accounts

  def set(conn, %{"lang" => lang}) when lang in ["en", "el"] do
    if user = conn.assigns[:current_user] do
      profile = Accounts.get_user_profile_by_user_id(user.id)

      if profile do
        Accounts.update_user_language(profile, lang)
      end
    end

    referer = get_req_header(conn, "referer") |> List.first("/")
    redirect(conn, external: referer)
  end

  def set(conn, _params) do
    redirect(conn, to: "/")
  end
end
