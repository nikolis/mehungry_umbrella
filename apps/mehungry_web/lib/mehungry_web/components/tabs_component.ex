defmodule MehungryWeb.TabsComponent do
  @moduledoc """
  Module to Facilitate Generalized Tabs widget functionality
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  def nav_buttons(assigns) do
    ~H"""
    <div class="flex gap-2 m-auto nav_buttons">
      <%= for state <- @states do %>
        <.nav_button
          state={state}
          current_state={Enum.at(@states, 0)}
          contents={@contents}
          recipe={@recipe}
          id={@recipe.id}
          nutrients={@nutrients}
          primary_size={@primary_size}
          ingredient_display_names={Map.get(assigns, :ingredient_display_names, %{})}
        />
      <% end %>
    </div>
    """
  end

  def nav_button(assigns) do
    {extra_class, extra_content} =
      if assigns.current_state == assigns.state do
        {"selected", ""}
      else
        {"", "hidden"}
      end

    assigns = Map.put(assigns, :extra_class, extra_class)
    assigns = Map.put(assigns, :extra_content, extra_content)

    IO.inspect(extra_class)

    ~H"""
    <button
      id={@state}
      class={[
        "px-6 py-3 text-sm font-medium transition-all rounded-t-lg nav_button w-full h-full " <>
          extra_class
      ]}
      phx-click={
        JS.remove_class("selected", to: ".nav_button")
        |> JS.add_class("selected", to: "##{@state}")
        |> JS.add_class("hidden", to: ".content_container")
        |> JS.remove_class("hidden", to: "##{@state}content")
      }
      phx-value-state={@state}
    >
      {@state}
    </button>

    <div
      id={@state <> "content"}
      class={"content_container absolute top-0 right-0 left-0 mt-10 mb-10 " <> @extra_class <> " " <> @extra_content }
    >
      {@contents.tab_content(%{
        state: @state,
        recipe: @recipe,
        id: Integer.to_string(@recipe.id),
        nutrients: @recipe.nutrients,
        primary_size: @primary_size,
        ingredient_display_names: Map.get(assigns, :ingredient_display_names, %{})
      })}
    </div>
    """
  end

  def render_tabs(assigns) do
    ~H"""
    <div class="border-b border-slate-700 mb-6" id={@id}>
      <div class="nav_buttons relative flex gap-2">
        <.nav_buttons
          states={@contents.get_states()}
          contents={@contents}
          recipe={@recipe}
          id={@recipe.id}
          nutrients={@nutrients}
          primary_size={@primary_size}
          ingredient_display_names={Map.get(assigns, :ingredient_display_names, %{})}
        />
      </div>
    </div>
    """
  end
end
