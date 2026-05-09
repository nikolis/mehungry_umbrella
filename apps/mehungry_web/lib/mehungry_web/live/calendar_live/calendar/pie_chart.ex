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
      class="w-full bg-red"
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
      [field: "category", type: :nominal, title: "Category"],
      [field: "value", type: :quantitative, title: "Value", format: ".2f"]
    ])
    |> Vl.config(
      background: "#1E293B",
      # Override all text elements
      style: [
        "guide-label": [fill: "#FFFFFF", font: "Inter"],
        "guide-title": [fill: "#FFFFFF", font: "Inter"],
        "group-title": [fill: "#FFFFFF", font: "Inter"],
        "group-subtitle": [fill: "#FFFFFF", font: "Inter"],
        "legend-label": [fill: "#FFFFFF", font: "Inter"],
        "legend-title": [fill: "#FFFFFF", font: "Inter"]
      ],
      axis: [
        labelColor: "#FFFFFF",
        titleColor: "#FFFFFF",
        domainColor: "#64748B",
        tickColor: "#64748B"
      ],
      legend: [
        labelColor: "#FFFFFF",
        titleColor: "#FFFFFF",
        labelFont: "Inter",
        titleFont: "Inter"
      ]
    )
    |> Vl.to_spec()
  end
end
