defmodule MehungryWeb.TabsLiveComponent do
  use Phoenix.LiveComponent

  @impl true
  def update(assigns, socket) do
    states = assigns.contents.get_states()
    [initial_state | _] = states

    {:ok,
     socket
     |> assign(assigns)
     |> assign(states: states)
     |> assign(state: initial_state)}
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
    <button
      class={"nav_button " <> @extra_class}
      phx-click="content_state_change"
      phx-value-state={@state}
      phx-target={@myself}
    >
      <%= @state %>
    </button>
    """
  end

  def handle_event("content_state_change", %{"state" => state}, socket) do
    {:noreply,
     socket
     |> assign(:state, state)}
  end

  def nav_buttons(assigns) do
    ~H"""
    <div class="w-full flex justify-between nav_buttons text-xl text-greyfriend2 font-semibold	mb-4">
      <%= for state <- @states do %>
        <.nav_button state={state} current_state={@state} myself={@myself} />
      <% end %>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="" id={@id}>
      <div class="nav_buttons">
        <.nav_buttons states={@states} state={@state} myself={@myself} />
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
end
