defmodule MehungryWeb.TabsComponent do
  use Phoenix.LiveComponent

  @impl true
  def update(assigns, socket) do
    states = ["first", "second", "third"]
    
    state = "first"
    {:ok,
     socket
     |> assign(assigns)
     |> assign(states: states)
     |> assign(state: state)
    }
  end

  def nav_button(assigns) do
    extra_class = if assigns.current_state == assigns.state do "active" else "" end
    assigns = Map.put(assigns, :extra_class, extra_class)
    ~H"""
    <button class={"nav_button " <> @extra_class} phx-click="content_state_change" phx-value-state={@state} phx-target={@myself}>
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
    <div class="w-full flex justify-between nav_buttons text-xl text-greyfriend2 font-semibold	">
      <%= for state <- @states do %>
      <.nav_button state={state} current_state ={@state} myself={@myself}/>
    <% end %>
  </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="" id={@id}>
      <div class="nav_buttons">
        <.nav_buttons states={@states} state={@state} myself={@myself}/>
        <%= @contents.tab_content(%{name: "nikos", state: @state}) %>
      </div>
    </div>
    """
  end
end
