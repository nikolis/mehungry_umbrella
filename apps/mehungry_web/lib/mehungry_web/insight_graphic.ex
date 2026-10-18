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

  The wordmark lockup and macro donut are the shared `MehungryWeb.SocialGraphic.Svg`
  primitives (also used by the weekly-plan card), so both cards stay visually
  identical.

  Uses `:image`/`:vix` (libvips). SVG rasterisation requires the libvips build to
  support `svgload` (rsvg) + font rendering; verified locally, and the prod
  release render must be smoke-tested (see the feature plan's risk gate).
  """

  require Logger

  alias MehungryWeb.SocialGraphic.Svg

  @canvas 1080

  @ink "#17140F"

  @font "'Helvetica Neue', Helvetica, Arial, sans-serif"

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
    headline = insight |> Map.fetch!(:headline) |> Svg.escape()

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

      #{Svg.wordmark()}
      #{Svg.macro_donut(macros, %{cx: 880, cy: 200, r: 120, inner: 66, legend: :below})}
      #{headline_block(headline)}
    </svg>
    """
  end

  defp headline_block(headline) do
    {line1, line2} = Svg.wrap_two(headline, 18)

    second =
      if line2 == "",
        do: "",
        else:
          ~s(<text x="60" y="1000" font-family="#{@font}" font-size="76" font-weight="800" fill="#F4EEDD">#{line2}</text>)

    base_y = if line2 == "", do: 1000, else: 912

    """
    <text x="60" y="#{base_y}" font-family="#{@font}" font-size="76" font-weight="800" fill="#F4EEDD">#{line1}</text>
    #{second}
    """
  end
end
