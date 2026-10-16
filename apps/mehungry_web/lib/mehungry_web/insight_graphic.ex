defmodule MehungryWeb.InsightGraphic do
  @moduledoc """
  Renders a recipe's shareable insight graphic: the recipe photo normalised to a
  1080×1080 (Instagram) square and composited with a deterministic overlay — a
  bottom scrim + headline, a macronutrient donut (protein / fat / carbs by
  calorie share), and the m3hungry wordmark.

  Hybrid-by-design: the data (donut, gram labels) is drawn deterministically from
  the recipe's computed nutrition so it is always truthful; only the `headline`
  comes from AI (via `Mehungry.AI.InsightCaptioner`). Generative image models are
  never used to draw the numbers.

  Uses `:image`/`:vix` (libvips). SVG rasterisation requires the libvips build to
  support `svgload` (rsvg) + font rendering; verified locally, and the prod
  release render must be smoke-tested (see the feature plan's risk gate).
  """

  require Logger

  @canvas 1080

  # Design-system tokens (tailwind.config.js).
  @ink "#17140F"
  @parchment "#F4EEDD"
  @paprika "#E8622C"
  @basil "#45C4AE"
  @amber "#E8B04B"

  @font "'Helvetica Neue', Helvetica, Arial, sans-serif"

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
  Renders the graphic for `recipe` using the given `insight` map.

  `insight` keys:
    * `:headline` — the text drawn on the card (required)
    * `:macros`   — `%{protein_g, fat_g, carbs_g, calories}` from
      `Mehungry.AI.RecipeInsight.macros/1` (required)

  Returns `{:ok, jpeg_binary}` or `{:error, reason}`.
  """
  @spec render(struct(), map()) :: {:ok, binary()} | {:error, term()}
  def render(recipe, insight) do
    with {:ok, body} <- fetch_image(recipe.image_url),
         {:ok, base} <- Image.open(body),
         {:ok, square} <- Image.thumbnail(base, "#{@canvas}x#{@canvas}", crop: :center),
         {:ok, square} <- Image.flatten(square),
         svg = overlay_svg(insight),
         {:ok, overlay} <- Image.from_svg(svg),
         {:ok, composed} <- Image.compose(square, overlay),
         {:ok, binary} <- Image.write(composed, :memory, suffix: ".jpg", quality: 88) do
      {:ok, binary}
    else
      {:error, reason} = err ->
        Logger.warning("InsightGraphic: render failed: #{inspect(reason)}")
        err

      other ->
        Logger.warning("InsightGraphic: render failed: #{inspect(other)}")
        {:error, :render_failed}
    end
  end

  # ── base image fetch ───────────────────────────────────────────────────────

  defp fetch_image(nil), do: {:error, :no_image}

  defp fetch_image(url) do
    case HTTPoison.get(url, [], recv_timeout: 30_000, follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %HTTPoison.Response{status_code: code}} -> {:error, {:http, code}}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── overlay SVG ──────────────────────────────────────────────────────────────

  defp overlay_svg(insight) do
    macros = Map.fetch!(insight, :macros)
    headline = insight |> Map.fetch!(:headline) |> escape()

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@canvas}" height="#{@canvas}" viewBox="0 0 #{@canvas} #{@canvas}">
      <defs>
        <linearGradient id="scrim" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#{@ink}" stop-opacity="0"/>
          <stop offset="100%" stop-color="#{@ink}" stop-opacity="0.88"/>
        </linearGradient>
        <radialGradient id="tr-glow" cx="80%" cy="20%" r="46%">
          <stop offset="0%" stop-color="#{@ink}" stop-opacity="0.62"/>
          <stop offset="60%" stop-color="#{@ink}" stop-opacity="0.38"/>
          <stop offset="100%" stop-color="#{@ink}" stop-opacity="0"/>
        </radialGradient>
      </defs>

      <rect x="0" y="0" width="#{@canvas}" height="#{@canvas}" fill="url(#tr-glow)"/>
      <rect x="0" y="560" width="#{@canvas}" height="520" fill="url(#scrim)"/>

      #{wordmark()}
      #{donut(macros)}
      #{headline_block(headline)}
    </svg>
    """
  end

  # Brand lockup: the logo mark on its cream tile + the "m3hungry" wordmark (the
  # "3" accented in paprika), inside a soft frosted pill that keeps it legible on
  # any photo.
  defp wordmark do
    tile = 74
    tx = 60
    ty = 55
    scale = tile / 1024

    """
    <g>
      <rect x="44" y="44" width="362" height="92" rx="46" fill="#{@ink}" fill-opacity="0.44"/>
      <rect x="44" y="44" width="362" height="92" rx="46" fill="none" stroke="#{@parchment}" stroke-opacity="0.18" stroke-width="1.5"/>
      <g transform="translate(#{tx},#{ty}) scale(#{ff_scale(scale)})">#{@logo_mark}</g>
      <text x="#{tx + tile + 20}" y="104" font-family="#{@font}" font-size="46" font-weight="800" letter-spacing="0.4" fill="#{@parchment}">m<tspan fill="#{@paprika}">3</tspan>hungry</text>
    </g>
    """
  end

  defp headline_block(headline) do
    {line1, line2} = wrap_two(headline, 18)

    second =
      if line2 == "",
        do: "",
        else:
          ~s(<text x="60" y="1000" font-family="#{@font}" font-size="76" font-weight="800" fill="#{@parchment}">#{line2}</text>)

    base_y = if line2 == "", do: 1000, else: 912

    """
    <text x="60" y="#{base_y}" font-family="#{@font}" font-size="76" font-weight="800" fill="#{@parchment}">#{line1}</text>
    #{second}
    """
  end

  # Macro donut (protein/fat/carbs by calorie share) top-right, with a legend.
  defp donut(macros) do
    cx = 880
    cy = 200
    r = 120
    inner = 66

    slices = macro_slices(macros)

    arcs =
      slices
      |> slice_angles()
      |> Enum.map(fn {color, a0, a1} -> arc_path(cx, cy, r, a0, a1, color) end)
      |> Enum.join("\n")

    kcal = round(macros.calories)

    """
    <g>
      #{arcs}
      <circle cx="#{cx}" cy="#{cy}" r="#{r}" fill="none" stroke="#{@parchment}" stroke-opacity="0.22" stroke-width="2"/>
      <circle cx="#{cx}" cy="#{cy}" r="#{inner + 2}" fill="#{@ink}" fill-opacity="0.92"/>
      <circle cx="#{cx}" cy="#{cy}" r="#{inner + 2}" fill="none" stroke="#{@parchment}" stroke-opacity="0.22" stroke-width="2"/>
      <text x="#{cx}" y="#{cy - 2}" text-anchor="middle" font-family="#{@font}" font-size="44" font-weight="800" fill="#{@parchment}">#{kcal}</text>
      <text x="#{cx}" y="#{cy + 34}" text-anchor="middle" font-family="#{@font}" font-size="22" font-weight="600" fill="#{@parchment}" fill-opacity="0.8">kcal</text>
      #{legend(macros, cx, cy, r)}
    </g>
    """
  end

  defp legend(macros, cx, cy, r) do
    x = cx - r - 16
    y0 = cy + r + 64

    [
      {@paprika, "Protein", macros.protein_g},
      {@basil, "Carbs", macros.carbs_g},
      {@amber, "Fat", macros.fat_g}
    ]
    |> Enum.with_index()
    |> Enum.map(fn {{color, label, grams}, i} ->
      y = y0 + i * 46

      """
      <circle cx="#{x + 12}" cy="#{y - 8}" r="12" fill="#{color}"/>
      <text x="#{x + 38}" y="#{y}" font-family="#{@font}" font-size="30" font-weight="600" fill="#{@parchment}">#{label} #{fmt_g(grams)}g</text>
      """
    end)
    |> Enum.join("\n")
  end

  # ── pie geometry ─────────────────────────────────────────────────────────────

  # Calorie share: protein/carbs 4 kcal/g, fat 9 kcal/g. Falls back to a single
  # neutral ring when there is no macro data so the donut is never empty.
  defp macro_slices(%{protein_g: p, carbs_g: c, fat_g: f}) do
    vals = [{@paprika, p * 4}, {@basil, c * 4}, {@amber, f * 9}]
    total = vals |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    if total <= 0 do
      [{"#4A4436", 1.0}]
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

    # A thin ink stroke outlines each wedge so adjacent slices read as distinct
    # bands (and the shared radial edges become crisp separators).
    ~s(<path d="M #{cx} #{cy} L #{ff(x0)} #{ff(y0)} A #{r} #{r} 0 #{large} 1 #{ff(x1)} #{ff(y1)} Z" fill="#{color}" stroke="#{@ink}" stroke-width="3" stroke-opacity="0.35" stroke-linejoin="round"/>)
  end

  defp polar(cx, cy, r, angle_deg) do
    rad = angle_deg * :math.pi() / 180.0
    {cx + r * :math.cos(rad), cy + r * :math.sin(rad)}
  end

  # ── formatting ───────────────────────────────────────────────────────────────

  defp fmt_g(n) when is_number(n), do: n |> Float.round(0) |> trunc()
  defp fmt_g(_), do: 0

  defp ff(n), do: :erlang.float_to_binary(n * 1.0, decimals: 1)

  # The logo scale is a sub-1 ratio (tile/1024 ≈ 0.072); ff/1's 1-decimal rounding
  # would collapse it to 0.1 and render the logo tile ~40% too large (102px vs
  # 74px), overlapping the wordmark. Format the scale with enough precision.
  defp ff_scale(n), do: :erlang.float_to_binary(n * 1.0, decimals: 4)

  # Wrap a headline to at most two lines near `max` chars, breaking on a space.
  defp wrap_two(text, max) do
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

  defp escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
