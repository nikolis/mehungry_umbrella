defmodule MehungryWeb.HomePageController do
  use MehungryWeb, :controller

  def home(conn, _params) do
    if conn.assigns[:current_user] do
      # User is logged in - redirect to dashboard
      redirect(conn, to: "/home")
    else
      # User is not logged in - show landing page
      redirect(conn, to: "/welcome")
    end
  end
end
