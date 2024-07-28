defmodule MehungryWeb.LayoutView do
  use MehungryWeb, :html

  embed_templates "templates/*"
  embed_templates "templates/menu/*"

  def get_main_content_container_class(_conn) do
    "main-content-container"
  end

  attr :current_user, :any


  def get_menu(assigns) do 

    ~H"""
     <.main_menu current_user={@current_user} query_string={@query_string}  />
     <.mobile_menu current_user={@current_user} />
    """
  # query_string={@changeset.changes.query_string} />

  end
 


  def sidebar_nav_links(assigns) do
    ~H"""
    <div class="body_side_nav_bar">
      <nav class="nav-list-cont 	 w-fit  p-16" id="nav_bar">
        <div class="flex flex-col gap-4 w-fit	">
            <a href="/" class="w-fit m-auto">
              <img src={~p"/images/logo.svg"} width="36" height="45"/>
            </a>
            <a href="/professional/users" class="w-fit block m-auto">Users</a>
            <a href="/professional/ingredients" class="w-fit block m-auto"> Ingredients</a>
          </div>
        </nav>
        <div class="container px-10 py-20">
          <%= @inner_content %>
        </div>
    </div>
    """
  end
end
