defmodule MehungryWeb.WeeklyPlanGraphic do
  @moduledoc """
  Renders a user's calendar week as a shareable 1080×1350 (4:5) card: a parchment
  canvas with the 7-day meal-title grid, the week's truthful daily-average macro
  donut, an optional goal pill, and the m3hungry wordmark.

  Fully SVG-composed — unlike `MehungryWeb.InsightGraphic` there is no base photo
  and no network fetch, so the render is deterministic and always succeeds given
  valid data. The wordmark and donut come from `MehungryWeb.SocialGraphic.Svg`, so
  the card is visually consistent with the recipe insight card.

  The numbers drawn here are produced upstream by `Mehungry.NutrientUtils` from the
  exact meals the calendar shows, so the card can never disagree with the app.

  Uses `:image`/`:vix` (libvips) with `svgload` (rsvg) + font rendering — the same
  prod render risk gate as `InsightGraphic`.
  """

  require Logger

  use Gettext, backend: MehungryWeb.Gettext

  alias MehungryWeb.SocialGraphic.Svg

  @w 1080
  @h 1350

  @grid_top 250
  @grid_bottom 1090
  @rows 7
  @row_h div(@grid_bottom - @grid_top, @rows)

  @doc """
  Renders the card from `week_data`:

    * `:range_label` — e.g. `"6–12 Oct"` (required)
    * `:goal_label`  — optional pill text (e.g. `"Anti-inflammatory"`) or `nil`
    * `:days`        — list of 7 `%{label: "Mon", meals: ["Omelette", ...]}`
    * `:macros`      — `%{protein_g, carbs_g, fat_g, calories}` daily averages
    * `:share_url`   — short URL shown in the footer

  Returns `{:ok, png_binary}` or `{:error, reason}`.
  """
  @spec render(map()) :: {:ok, binary()} | {:error, term()}
  def render(week_data) do
    svg = document(week_data)

    with {:ok, img} <- Image.from_svg(svg),
         {:ok, img} <- Image.flatten(img),
         {:ok, binary} <- Image.write(img, :memory, suffix: ".png") do
      {:ok, binary}
    else
      {:error, reason} = err ->
        Logger.warning("WeeklyPlanGraphic: render failed: #{inspect(reason)}")
        err

      other ->
        Logger.warning("WeeklyPlanGraphic: render failed: #{inspect(other)}")
        {:error, :render_failed}
    end
  end

  defp document(week_data) do
    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@w}" height="#{@h}" viewBox="0 0 #{@w} #{@h}">
      <rect x="0" y="0" width="#{@w}" height="#{@h}" fill="#{Svg.parchment()}"/>
      <rect x="0" y="0" width="#{@w}" height="10" fill="#{Svg.paprika()}"/>

      #{Svg.wordmark(0, 0)}
      #{range_label(week_data)}
      #{goal_pill(week_data[:goal_label])}
      #{grid(week_data[:days] || [])}
      #{footer(week_data)}
    </svg>
    """
  end

  defp range_label(%{range_label: label}) when is_binary(label) do
    ~s(<text x="#{@w - 44}" y="112" text-anchor="end" font-family="#{Svg.font()}" font-size="42" font-weight="800" fill="#{Svg.ink()}">#{Svg.escape(label)}</text>)
  end

  defp range_label(_), do: ""

  defp goal_pill(nil), do: ""
  defp goal_pill(""), do: ""

  defp goal_pill(label) do
    text = Svg.truncate(label, 28)
    width = 44 + String.length(text) * 20

    """
    <g>
      <rect x="44" y="160" width="#{width}" height="60" rx="30" fill="#{Svg.paprika()}"/>
      <text x="#{44 + div(width, 2)}" y="200" text-anchor="middle" font-family="#{Svg.font()}" font-size="30" font-weight="700" fill="#{Svg.parchment()}">#{Svg.escape(text)}</text>
    </g>
    """
  end

  defp grid(days) do
    days
    |> Enum.take(@rows)
    |> Enum.with_index()
    |> Enum.map(fn {day, i} -> grid_row(day, i) end)
    |> Enum.join("\n")
  end

  # Meal titles are laid out in two columns starting at @meals_x; @col_w/@col_gap
  # size them to fill the row out to the right margin (230 + 391 + 24 + 391 =
  # 1036 = @w − 44). Up to @rows_per_col lines per column (@max_lines total), at
  # @title_chars per line for that column width.
  @meals_x 230
  @col_w 391
  @col_gap 24
  @line_height 32
  @rows_per_col 3
  @max_lines @rows_per_col * 2
  # Title chars that fill one column at the title font; tagged lines subtract the
  # (shorter-font) tag's cost so short tags like LUNCH leave more room than
  # BREAKFAST.
  @col_chars 31

  defp grid_row(day, i) do
    top = @grid_top + i * @row_h
    row_center = top + div(@row_h, 2)
    separator = if i == 0, do: "", else: hairline(top)

    label = day |> Map.get(:label, "") |> Svg.escape()
    meals = Map.get(day, :meals, [])
    color = if meals == [], do: Svg.parchment_dim(), else: Svg.panel()

    # Each slot is its own line (independently truncated), laid out in two columns
    # (column-major: chronological down the first column, then the second) so all
    # of a full day's meals fit the fixed row height at a readable size. The stack
    # is vertically centred; anything past @max_lines collapses into "+N more".
    lines = day_lines(meals)
    rows_used = min(length(lines), @rows_per_col)
    first_baseline = row_center - div((rows_used - 1) * @line_height, 2) + 10

    meal_texts =
      lines
      |> Enum.with_index()
      |> Enum.map(fn {line, k} ->
        col = div(k, @rows_per_col)
        r = rem(k, @rows_per_col)
        x = @meals_x + col * (@col_w + @col_gap)
        y = first_baseline + r * @line_height
        meal_line(line, x, y, color)
      end)
      |> Enum.join("\n")

    """
    #{separator}
    <text x="70" y="#{row_center + 12}" font-family="#{Svg.font()}" font-size="34" font-weight="800" fill="#{Svg.ink()}">#{label}</text>
    #{meal_texts}
    """
  end

  defp hairline(y) do
    ~s(<line x1="44" y1="#{y}" x2="#{@w - 44}" y2="#{y}" stroke="#{Svg.ink()}" stroke-opacity="0.12" stroke-width="2"/>)
  end

  # One line at column origin `x`: the meal-type tag ("AM SNACK") as a small
  # paprika prefix, then the title. Overflow/empty lines (no tag) render as plain
  # text.
  defp meal_line(%{tag: tag, title: title}, x, y, color) when is_binary(tag) do
    tag_part =
      ~s(<tspan fill="#{Svg.paprika()}" font-weight="700" font-size="18" letter-spacing="0.5">#{Svg.escape(upcase_label(short_tag(tag)))}</tspan>  )

    ~s(<text x="#{x}" y="#{y}" font-family="#{Svg.font()}" font-size="24" font-weight="500" fill="#{color}">#{tag_part}#{Svg.escape(title)}</text>)
  end

  defp meal_line(%{title: title}, x, y, color) do
    ~s(<text x="#{x}" y="#{y}" font-family="#{Svg.font()}" font-size="24" font-weight="500" fill="#{color}">#{Svg.escape(title)}</text>)
  end

  # Shorter slot tags for the narrow two-column cells (the full labels are from
  # `MealType.label/1`); keeps the paprika prefix from eating the title width.
  defp short_tag("Morning Snack"), do: "AM Snack"
  defp short_tag("Afternoon Snack"), do: "PM Snack"
  defp short_tag(tag), do: tag

  # Uppercase for the card's small-caps labels, dropping the Greek tonos the way
  # monotonic all-caps does (ΠΡΩΙΝΌ → ΠΡΩΙΝΟ) while keeping the dialytika. A no-op
  # for Latin text.
  defp upcase_label(text) do
    text
    |> String.upcase()
    |> String.normalize(:nfd)
    |> String.replace("́", "")
    |> String.normalize(:nfc)
  end

  # One display line per meal (empty day → a single muted dash). When a day has
  # more than @max_lines meals, the last line becomes "+N more" so the row height
  # stays bounded. Accepts `%{tag, title}` maps (from the generator) or bare title
  # strings; strings are normalised to an untagged line.
  defp day_lines([]), do: [%{tag: nil, title: "—"}]

  defp day_lines(meals) do
    meals = Enum.map(meals, &normalize_meal/1)

    if length(meals) <= @max_lines do
      Enum.map(meals, &truncate_title/1)
    else
      kept = @max_lines - 1

      (meals |> Enum.take(kept) |> Enum.map(&truncate_title/1)) ++
        [%{tag: nil, title: "+#{length(meals) - kept} more"}]
    end
  end

  defp normalize_meal(%{title: title} = meal), do: %{tag: Map.get(meal, :tag), title: title}
  defp normalize_meal(title) when is_binary(title), do: %{tag: nil, title: title}

  # A tagged line gets a tighter title budget since the tag prefix eats into the
  # column width — scaled by the *specific* tag's rendered length (it's drawn at a
  # smaller font than the title, hence the 0.8 factor), so "LUNCH" keeps far more
  # of its title than "BREAKFAST".
  defp truncate_title(%{tag: tag, title: title}) when is_binary(tag) do
    tag_cost = round(String.length(short_tag(tag)) * 0.8) + 1
    %{tag: tag, title: Svg.truncate(title, max(@col_chars - tag_cost, 12))}
  end

  defp truncate_title(%{title: title} = line) do
    %{line | title: Svg.truncate(title, @col_chars)}
  end

  defp footer(week_data) do
    macros = Map.get(week_data, :macros, %{})

    macros =
      macros
      |> Map.put_new(:protein_g, 0)
      |> Map.put_new(:carbs_g, 0)
      |> Map.put_new(:fat_g, 0)
      |> Map.put_new(:calories, 0)

    share_url = Map.get(week_data, :share_url, "m3hungry.com")
    locale = Map.get(week_data, :locale, "en")

    # The card renders outside a request (async Task), so the locale is explicit
    # rather than from the process — localize the footer chrome and the donut's
    # macro legend under it.
    Gettext.with_locale(locale, fn ->
      daily_average = upcase_label(gettext("Daily average"))
      plan_free = gettext("Plan your week free")

      donut =
        Svg.macro_donut(macros, %{
          cx: 230,
          cy: 1240,
          r: 90,
          inner: 50,
          legend: :right,
          label_color: Svg.ink(),
          labels: %{protein: gettext("Protein"), carbs: gettext("Carbs"), fat: gettext("Fat")}
        })

      """
      <line x1="44" y1="#{@grid_bottom}" x2="#{@w - 44}" y2="#{@grid_bottom}" stroke="#{Svg.ink()}" stroke-opacity="0.18" stroke-width="3"/>
      <text x="230" y="1150" text-anchor="middle" font-family="#{Svg.font()}" font-size="26" font-weight="700" letter-spacing="1" fill="#{Svg.ink()}" fill-opacity="0.7">#{Svg.escape(daily_average)}</text>
      #{donut}
      <text x="#{@w - 44}" y="1310" text-anchor="end" font-family="#{Svg.font()}" font-size="30" font-weight="700" fill="#{Svg.paprika()}">#{Svg.escape(share_url)}</text>
      <text x="#{@w - 44}" y="1270" text-anchor="end" font-family="#{Svg.font()}" font-size="26" font-weight="500" fill="#{Svg.ink()}" fill-opacity="0.65">#{Svg.escape(plan_free)}</text>
      """
    end)
  end
end
