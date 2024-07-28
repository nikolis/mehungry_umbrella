defmodule MehungryWeb.AdminLayout do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use VisualizeWeb, :controller` and
  `use VisualizeWeb, :live_view`.
  """
  use MehungryWeb, :html

  embed_templates "layouts/*"

  attr :current_user, :any
  attr :active_tab, :atom

  def sidebar_nav_links(assigns) do
    ~H"""
    <div class="body_side_nav_bar h-full z-14">
      <nav class="nav-list-cont pt-10">
        <ul class="nav-list">
          <li>
            <a href="/">
              <img src={~p"/images/logo.svg"} width="36" />
            </a>
          </li>

          <li class={if @active_tab == :created, do: "active", else: ""}>
            <a href="/created_plots" class="w-full block"> Your plots </a>
          </li>
          <li class={if @active_tab == :shared, do: "active", else: ""}>
            <a href="/shared_plots" class="w-full block"> Shared with you </a>
          </li>
        </ul>
      </nav>
      <%= @inner_content %>
    </div>
    """
  end
end
