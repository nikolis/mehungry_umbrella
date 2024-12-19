defmodule MehungryWeb.CalendarLive.FormSettings do
  use MehungryWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h3>The Menu container</h3>
    </div>
    """
  end

  @impl true
  def update(_assigns, socket) do
    {:ok, socket}
  end
end
