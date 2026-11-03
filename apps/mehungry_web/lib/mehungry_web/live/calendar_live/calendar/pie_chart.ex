defmodule MehungryWeb.CalendarLive.Calendar.PieChart do
  @moduledoc """
  The nutrient macro/micro **donut** on the calendar day/recipe nutrition panel.

  Receives slices as `[%{category:, value:, display:}]` (grams in `value`, a
  human string like `"24.3 g"` in `display`) and renders a **hand-built inline
  SVG donut** in the app's warm-charcoal palette — replacing the previous
  VegaLite arc, whose default categorical colour scheme sat off-brand against the
  `ink-panel` surface. SVG server-renders instantly (no connect round-trip, no JS
  charting dependency) and themes to the design tokens exactly.
  """
  use Phoenix.LiveComponent

  import Phoenix.HTML, only: [raw: 1]
  use Gettext, backend: MehungryWeb.Gettext

  # Categorical ramp derived from the brand: paprika + basil lead, then warm/earthy
  # hues that stay distinguishable against the dark `#211D16` panel. Cycled by slice.
  @palette ~w(#E8622C #45C4AE #E7B54A #C77DAD #8FB46B #6FA1C9 #D98299 #7FB8A0)

  # donut geometry (viewBox units)
  @size 220
  @cx 110
  @cy 110
  @r_out 92
  @r_in 56

  def update(assigns, socket) do
    # Tolerate a bare `resize:` update (legacy ResponsiveChart path) with no data —
    # the SVG is intrinsically responsive, so there's nothing to recompute.
    {:ok, assign(socket, assigns)}
  end

  # Fired by the legacy ResponsiveChart JS hook; the SVG scales via viewBox, so
  # there is nothing to recompute.
  def handle_event("resize", _params, socket), do: {:noreply, socket}

  def render(assigns) do
    assigns = assign(assigns, :slices, slices(assigns[:data] || []))

    ~H"""
    <div id={"chart-#{@id}"} class="w-full flex flex-col items-center gap-3" style={"max-width: #{@size || "20rem"}"}>
      <div class="w-full" style="max-width: 200px">
        {donut_svg(@slices)}
      </div>
      <ul class="w-full flex flex-col gap-1.5 text-xs">
        <li :for={s <- @slices} class="flex items-center gap-2">
          <span class="inline-block w-2.5 h-2.5 rounded-sm shrink-0" style={"background:#{s.color}"}></span>
          <span class="text-parchment-dim truncate flex-1">{s.category}</span>
          <span class="text-parchment tabular-nums font-medium">{s.display}</span>
        </li>
      </ul>
    </div>
    """
  end

  # ── slice model ─────────────────────────────────────────────────────────────
  # Each slice gets a colour and its start/end angle (radians, 0 at top, clockwise).
  defp slices(data) do
    total = data |> Enum.map(&(&1.value * 1.0)) |> Enum.sum()

    if total <= 0 do
      []
    else
      {slices, _} =
        data
        |> Enum.with_index()
        |> Enum.map_reduce(0.0, fn {d, i}, acc ->
          frac = d.value * 1.0 / total
          a0 = acc * 2 * :math.pi()
          a1 = (acc + frac) * 2 * :math.pi()
          slice = %{category: d.category, display: d.display, color: color(i), a0: a0, a1: a1}
          {slice, acc + frac}
        end)

      slices
    end
  end

  defp color(i), do: Enum.at(@palette, rem(i, length(@palette)))

  # ── donut SVG ───────────────────────────────────────────────────────────────
  defp donut_svg([]) do
    aria = gettext("No data")

    raw(
      ~s(<svg viewBox="0 0 #{@size} #{@size}" class="w-full h-auto block" role="img" aria-label="#{aria}">) <>
        ~s(<circle cx="#{@cx}" cy="#{@cy}" r="#{(@r_out + @r_in) / 2}" fill="none" stroke="#2B2619" stroke-width="#{@r_out - @r_in}"/>) <>
        "</svg>"
    )
  end

  # One slice = a full ring (arc paths degenerate at 360°).
  defp donut_svg([only]) do
    r_mid = (@r_out + @r_in) / 2

    body =
      ~s(<circle cx="#{@cx}" cy="#{@cy}" r="#{f(r_mid)}" fill="none" stroke="#{only.color}" stroke-width="#{@r_out - @r_in}"><title>#{esc(only.category)}: #{esc(only.display)}</title></circle>)

    raw(svg_wrap(body, [only]))
  end

  defp donut_svg(slices) do
    body = Enum.map_join(slices, fn s -> arc_segment(s) end)
    raw(svg_wrap(body, slices))
  end

  defp svg_wrap(body, slices) do
    label = slices |> Enum.map_join(", ", & &1.category)
    aria = gettext("Nutrient breakdown: %{items}", items: esc(label))

    ~s(<svg viewBox="0 0 #{@size} #{@size}" class="w-full h-auto block" role="img" aria-label="#{aria}">) <>
      body <>
      "</svg>"
  end

  defp arc_segment(s) do
    large = if s.a1 - s.a0 > :math.pi(), do: 1, else: 0
    {x0o, y0o} = polar(@r_out, s.a0)
    {x1o, y1o} = polar(@r_out, s.a1)
    {x1i, y1i} = polar(@r_in, s.a1)
    {x0i, y0i} = polar(@r_in, s.a0)

    d =
      "M#{f(x0o)} #{f(y0o)} " <>
        "A#{@r_out} #{@r_out} 0 #{large} 1 #{f(x1o)} #{f(y1o)} " <>
        "L#{f(x1i)} #{f(y1i)} " <>
        "A#{@r_in} #{@r_in} 0 #{large} 0 #{f(x0i)} #{f(y0i)} Z"

    ~s|<path d="#{d}" fill="#{s.color}" stroke="#211D16" stroke-width="1.5"><title>#{esc(s.category)}: #{esc(s.display)}</title></path>|
  end

  # angle 0 at top, increasing clockwise
  defp polar(r, a), do: {@cx + r * :math.sin(a), @cy - r * :math.cos(a)}

  defp f(n), do: :erlang.float_to_binary(n * 1.0, decimals: 2)

  defp esc(str), do: str |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
