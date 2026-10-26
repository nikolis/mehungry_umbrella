defmodule MehungryWeb.HomePageController do
  use MehungryWeb, :controller

  def home(conn, _params) do
    locale = conn.assigns[:locale] || MehungryWeb.Locale.default()

    case conn.assigns[:current_user] do
      nil ->
        # Not logged in - show the nutritionist-led landing page
        redirect(conn, to: "/#{locale}/welcome")

      user ->
        # The product is nutritionist-led: a pro lands in their practice
        # workspace, everyone else on the consumer home feed. This is the single
        # funnel point for every signed-in redirect (password login, OAuth, and
        # bookmarks all resolve `/` here), so `user_return_to` deep links are
        # already honored upstream in UserAuth.log_in_user before we get here.
        if Mehungry.Subscriptions.nutritionist?(user.id) do
          redirect(conn, to: "/nutritionist")
        else
          redirect(conn, to: "/#{locale}/home")
        end
    end
  end
end
