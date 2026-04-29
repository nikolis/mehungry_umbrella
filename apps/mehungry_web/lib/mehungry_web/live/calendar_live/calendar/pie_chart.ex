defmodule MehungryWeb.CalendarLive.Calendar.PieChart do
  use Phoenix.LiveComponent

  alias VegaLite, as: Vl

  # ---------- MOUNT ----------
  def mount(socket) do
    {:ok, assign(socket, width: 150)}
  end

  # ---------- UPDATE ----------
  def update(assigns, socket) do
    assigns = Map.put(assigns, :width, 300)

    socket =
      socket
      |> assign(:spec, build_spec(assigns.data, assigns.width))

    {:ok, assign(socket, assigns)}
  end

  # ---------- HANDLE RESIZE ----------
  def handle_event("resize", %{"width" => width}, socket) do
    {:noreply, assign(socket, width: width)}
  end

  # ---------- VIEW ----------
  def render(assigns) do
    ~H"""
    <div
      id={"chart-#{@id}"}
      data-component-target={@myself}
      phx-target={@myself}
      phx-hook="ResponsiveChart"
      data-size={@size}
      data-id={@id}
      class="w-full"
      data-origin_id={@origin_id}
    >
      <div id={"vega-#{@id}"} phx-hook="VegaLite" data-spec={Jason.encode!(@spec)}></div>
    </div>
    """
  end

  # ---------- CHART BUILDER ----------
  def build_spec(data, width) do
    radius = width * 0.35
    inner = width * 0.2

    Vl.new(width: 100, height: 100)
    |> Vl.data_from_values(data)
    |> Vl.mark(:arc, radius: 50)
    |> Vl.encode_field(:theta, "value", type: :quantitative)
    |> Vl.encode_field(:color, "category", type: :nominal)
    |> Vl.encode(:tooltip, [
      [field: "category", type: :nominal],
      [field: "value", type: :quantitative]
    ])
    |> Vl.to_spec()
  end
end
