defmodule MehungryWeb.SocialGraphic.Svg do
  @moduledoc """
  Shared SVG primitives for m3hungry's deterministic social-share cards — the
  brand wordmark lockup, the truthful macronutrient donut (protein/fat/carbs by
  calorie share), and the text helpers.

  Extracted from `MehungryWeb.InsightGraphic` so the recipe insight card and the
  weekly-plan card draw the *same* wordmark and donut (same geometry, same colour
  tokens), and a design tweak lands on both at once. Everything here is pure
  string-building; callers compose these fragments into a full SVG document and
  rasterise with `:image`/`:vix`.

  All colours are the design-system tokens (`tailwind.config.js`).
  """

  # Design-system tokens.
  def ink, do: "#17140F"
  def parchment, do: "#F4EEDD"
  def parchment_dim, do: "#B8AE98"
  def paprika, do: "#E8622C"
  def basil, do: "#45C4AE"
  def amber, do: "#E8B04B"
  def panel, do: "#4A4436"

  def font, do: "'Helvetica Neue', Helvetica, Arial, sans-serif"

  # The m3hungry logo mark (atomic orbits + leaf + bowl), inlined from
  # priv/static/images/m3hungry_logo_mark_light.svg so it rasterises with the
  # overlay — drawn on the mark's native 1024×1024 space and scaled down.
  @logo_mark """
  <rect width="1024" height="1024" rx="180" fill="#F4EEDD"/>
  <g fill="none" stroke="#45C4AE" stroke-width="26" stroke-linecap="round">
    <ellipse cx="512" cy="430" rx="275" ry="108" transform="rotate(18 512 430)"/>
    <ellipse cx="512" cy="430" rx="275" ry="108" transform="rotate(-18 512 430)"/>
  </g>
  <circle cx="307" cy="366" r="31" fill="#45C4AE"/>
  <circle cx="674" cy="532" r="31" fill="#45C4AE"/>
  <path d="M706 267 C741 226 787 218 824 224 C828 266 816 309 783 337 C753 362 719 357 696 346 C700 318 708 291 706 267Z" fill="#45C4AE"/>
  <path d="M714 340 C737 306 760 276 796 244" fill="none" stroke="#F4EEDD" stroke-width="12" stroke-linecap="round"/>
  <path d="M244 584 C315 616 709 616 780 584 L760 752 C746 850 646 922 512 922 C378 922 278 850 264 752 Z" fill="#E8622C"/>
  <path d="M244 584 C299 551 725 551 780 584 C724 623 300 623 244 584Z" fill="#E8622C"/>
  <path d="M275 584 C344 605 680 605 749 584 C678 566 346 566 275 584Z" fill="#F4EEDD"/>
  <path d="M467 913 C481 931 543 931 557 913 C552 902 472 902 467 913Z" fill="#E8622C"/>
  """

  @doc """
  The brand lockup: the logo mark on its cream tile + the "m3hungry" wordmark (the
  "3" accented in paprika), inside a soft frosted pill that keeps it legible on
  any background.

  Pass `dx`/`dy` to shift the whole lockup; `(0, 0)` reproduces the top-left
  placement used by the recipe insight card.
  """
  def wordmark(dx \\ 0, dy \\ 0) do
    tile = 74
    tx = 60
    ty = 55
    scale = tile / 1024

    """
    <g transform="translate(#{dx},#{dy})">
      <rect x="44" y="44" width="362" height="92" rx="46" fill="#{ink()}" fill-opacity="0.44"/>
      <rect x="44" y="44" width="362" height="92" rx="46" fill="none" stroke="#{parchment()}" stroke-opacity="0.18" stroke-width="1.5"/>
      <g transform="translate(#{tx},#{ty}) scale(#{ff_scale(scale)})">#{@logo_mark}</g>
      <text x="#{tx + tile + 20}" y="104" font-family="#{font()}" font-size="46" font-weight="800" letter-spacing="0.4" fill="#{parchment()}">m<tspan fill="#{paprika()}">3</tspan>hungry</text>
    </g>
    """
  end

  @doc """
  The macro donut (protein/fat/carbs by calorie share) with a `kcal` centre label
  and a legend.

  `macros` is `%{protein_g, carbs_g, fat_g, calories}`. `geom` is
  `%{cx, cy, r, inner}` plus optional `legend: :below | :right` (default
  `:below`) and `label_color` for the legend text (default `parchment/0`, which
  reads on a dark photo; pass `ink/0` for a light-background card).
  """
  def macro_donut(macros, geom) do
    cx = geom.cx
    cy = geom.cy
    r = geom.r
    inner = Map.get(geom, :inner, round(r * 0.55))
    legend_pos = Map.get(geom, :legend, :below)
    label_color = Map.get(geom, :label_color, parchment())
    labels = Map.get(geom, :labels, %{})

    arcs =
      macros
      |> macro_slices()
      |> slice_angles()
      |> Enum.map(fn {color, a0, a1} -> arc_path(cx, cy, r, a0, a1, color) end)
      |> Enum.join("\n")

    kcal = round(macros.calories || 0)

    """
    <g>
      #{arcs}
      <circle cx="#{cx}" cy="#{cy}" r="#{r}" fill="none" stroke="#{parchment()}" stroke-opacity="0.22" stroke-width="2"/>
      <circle cx="#{cx}" cy="#{cy}" r="#{inner + 2}" fill="#{ink()}" fill-opacity="0.92"/>
      <circle cx="#{cx}" cy="#{cy}" r="#{inner + 2}" fill="none" stroke="#{parchment()}" stroke-opacity="0.22" stroke-width="2"/>
      <text x="#{cx}" y="#{cy - 2}" text-anchor="middle" font-family="#{font()}" font-size="44" font-weight="800" fill="#{parchment()}">#{kcal}</text>
      <text x="#{cx}" y="#{cy + 34}" text-anchor="middle" font-family="#{font()}" font-size="22" font-weight="600" fill="#{parchment()}" fill-opacity="0.8">kcal</text>
      #{legend(macros, cx, cy, r, legend_pos, label_color, labels)}
    </g>
    """
  end

  # Legend rows. `:below` stacks under the donut (recipe card); `:right` places
  # them to the right (weekly card footer, where vertical room is tight). `labels`
  # overrides the English macro names for localized cards.
  defp legend(macros, cx, cy, r, position, label_color, labels) do
    {x, y0} =
      case position do
        :right -> {cx + r + 36, cy - 46}
        _ -> {cx - r - 16, cy + r + 64}
      end

    [
      {paprika(), labels[:protein] || "Protein", macros.protein_g},
      {basil(), labels[:carbs] || "Carbs", macros.carbs_g},
      {amber(), labels[:fat] || "Fat", macros.fat_g}
    ]
    |> Enum.with_index()
    |> Enum.map(fn {{color, label, grams}, i} ->
      y = y0 + i * 46

      """
      <circle cx="#{x + 12}" cy="#{y - 8}" r="12" fill="#{color}"/>
      <text x="#{x + 38}" y="#{y}" font-family="#{font()}" font-size="30" font-weight="600" fill="#{label_color}">#{label} #{fmt_g(grams)}g</text>
      """
    end)
    |> Enum.join("\n")
  end

  # ── pie geometry ─────────────────────────────────────────────────────────────

  # Calorie share: protein/carbs 4 kcal/g, fat 9 kcal/g. Falls back to a single
  # neutral ring when there is no macro data so the donut is never empty.
  defp macro_slices(%{protein_g: p, carbs_g: c, fat_g: f}) do
    vals = [{paprika(), num(p) * 4}, {basil(), num(c) * 4}, {amber(), num(f) * 9}]
    total = vals |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    if total <= 0 do
      [{panel(), 1.0}]
    else
      Enum.map(vals, fn {color, v} -> {color, v / total} end)
    end
  end

  defp slice_angles(slices) do
    {acc, _} =
      Enum.reduce(slices, {[], -90.0}, fn {color, frac}, {acc, start} ->
        stop = start + frac * 360.0
        {[{color, start, stop} | acc], stop}
      end)

    Enum.reverse(acc)
  end

  # A full-circle slice (fraction ~1.0) can't be drawn as a single SVG arc
  # (start == end), so render it as a plain circle.
  defp arc_path(cx, cy, r, a0, a1, color) when a1 - a0 >= 359.999 do
    ~s(<circle cx="#{cx}" cy="#{cy}" r="#{r}" fill="#{color}"/>)
  end

  defp arc_path(cx, cy, r, a0, a1, color) do
    {x0, y0} = polar(cx, cy, r, a0)
    {x1, y1} = polar(cx, cy, r, a1)
    large = if a1 - a0 > 180.0, do: 1, else: 0

    ~s(<path d="M #{cx} #{cy} L #{ff(x0)} #{ff(y0)} A #{r} #{r} 0 #{large} 1 #{ff(x1)} #{ff(y1)} Z" fill="#{color}" stroke="#{ink()}" stroke-width="3" stroke-opacity="0.35" stroke-linejoin="round"/>)
  end

  defp polar(cx, cy, r, angle_deg) do
    rad = angle_deg * :math.pi() / 180.0
    {cx + r * :math.cos(rad), cy + r * :math.sin(rad)}
  end

  # ── formatting ───────────────────────────────────────────────────────────────

  @doc "Round a gram value to a whole number for a compact label (nil/other → 0)."
  def fmt_g(n) when is_number(n), do: n |> Float.round(0) |> trunc()
  def fmt_g(_), do: 0

  @doc "Format a float with 1 decimal for SVG coordinate output."
  def ff(n), do: :erlang.float_to_binary(n * 1.0, decimals: 1)

  # The logo scale is a sub-1 ratio (tile/1024 ≈ 0.072); 1-decimal rounding would
  # collapse it to 0.1 and render the logo tile ~40% too large. Keep precision.
  def ff_scale(n), do: :erlang.float_to_binary(n * 1.0, decimals: 4)

  @doc "Escape text for safe inclusion in SVG markup."
  def escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  @doc """
  Wrap `text` to at most two lines near `max` chars, breaking on a space.
  Returns `{line1, line2}` (`line2` is `""` when it fits on one line).
  """
  def wrap_two(text, max) do
    if String.length(text) <= max do
      {text, ""}
    else
      words = String.split(text, " ")

      {l1, l2} =
        Enum.reduce(words, {"", ""}, fn w, {a, b} ->
          cond do
            b != "" -> {a, b <> " " <> w}
            String.length(String.trim(a <> " " <> w)) <= max -> {String.trim(a <> " " <> w), b}
            true -> {a, w}
          end
        end)

      {l1, String.trim(l2)}
    end
  end

  @doc "Truncate `text` to `max` chars with an ellipsis."
  def truncate(text, max) do
    text = to_string(text)

    if String.length(text) <= max,
      do: text,
      else: String.slice(text, 0, max - 1) |> String.trim_trailing() |> Kernel.<>("…")
  end

  defp num(n) when is_number(n), do: n * 1.0
  defp num(_), do: 0.0
end
