defmodule MehungryWeb.LayoutView do
  use MehungryWeb, :html
  alias Phoenix.LiveView.JS

  embed_templates "templates/*"
  embed_templates "templates/menu/*"

  def get_main_content_container_class(_conn) do
    "main-content-container"
  end

  attr :current_user, :any
  attr :query_string, :string

  def get_menu(assigns) do
    ~H"""
    <.main_menu current_user={@current_user} query_string={@query_string} />
    <.mobile_menu current_user={@current_user} query_string={@query_string} />
    """

    # query_string={@changeset.changes.query_string} />
  end

  def sidebar_nav_links(assigns) do
    ~H"""
    <div class="">
      <button
        id="admin_menu_button"
        class="fixed border-complementary text-white rounded-full  w-10 h-10 bg-white z-50"
        phx-click={
          JS.toggle_class("open", to: "#nav_bar_admin")
          |> JS.toggle_class("open_button", to: "#admin_menu_button")
        }
      >
        <.icon name="hero-arrow-down-circle" class=" h-10 w-10 text-complementary" />
      </button>

      <nav class="nav-list-cont w-fit  pl-6 pt-16 min-w-60 text-left" id="nav_bar_admin">
        <div class="flex flex-col gap-4 w-fit	">
          <a href="/" class="w-fit ">
            <img src={~p"/images/logo_written.png"} width="100" height="45" />
          </a>
          <a href="/professional/users" class="w-fit block ">Users</a>
          <a href="/professional/activeusers" class="w-fit block">Active users</a>
          <a href="/professional/ingredients" class="w-fit block ">Ingredients</a>

          <a href="/professional/visits" class="w-fit block">Visits</a>
        </div>
      </nav>
      <div class="container px-2 py-4 m-auto">
        <%= @inner_content %>
      </div>
    </div>
    """
  end
end
