defmodule MehungryWeb.TabsComponent do
  @moduledoc """
  Module to Facilitate Generalized Tabs widget functionality
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  def nav_buttons(assigns) do
    ~H"""
    <div class="w-full flex justify-between nav_buttons text-xl text-greyfriend2 font-semibold	mb-4">
      <%= for state <- @states do %>
        <.nav_button
          state={state}
          current_state={Enum.at(@states, 0)}
          contents={@contents}
          recipe={@recipe}
          ,
          nutrients={@nutrients}
          primary_size={@primary_size}
        />
      <% end %>
    </div>
    """
  end

  def nav_button(assigns) do
    extra_class =
      if assigns.current_state == assigns.state do
        "active"
      else
        ""
      end

    assigns = Map.put(assigns, :extra_class, extra_class)

    ~H"""
    <div>
      <button
        id={@state}
        class={"nav_button " <> @extra_class}
        phx-click={
          JS.remove_class("active", to: ".nav_button")
          |> JS.add_class("active", to: "##{@state}")
          |> JS.add_class("hidden", to: ".content_container")
          |> JS.remove_class("hidden", to: "##{@state}content")
        }
        phx-value-state={@state}
      >
        <%= @state %>
      </button>

      <div
        id={@state <> "content"}
        class={"content_container absolute top-0 right-0 left-0 mt-6 hidden" <> @extra_class}
      >
        <%= @contents.tab_content(%{
          state: @state,
          recipe: @recipe,
          nutrients: @nutrients,
          primary_size: @primary_size
        }) %>
      </div>
    </div>
    """
  end

  def render_tabs(assigns) do
    ~H"""
    <div class="" id={@id}>
      <div class="nav_buttons relative">
        <.nav_buttons
          states={@contents.get_states()}
          contents={@contents}
          recipe={@recipe}
          nutrients={@nutrients}
          primary_size={@primary_size}
        />
      </div>
    </div>
    """
  end
end
