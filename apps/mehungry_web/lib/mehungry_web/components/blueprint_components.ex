defmodule MehungryWeb.BlueprintComponents do
  @moduledoc """
  Shared UI for meal blueprints — the browse/profile card and the day-grouped
  plan-meal list — used by the public preview page, the browse toggle, and the
  profile "saved blueprints" tab.
  """
  use Phoenix.VerifiedRoutes,
    endpoint: MehungryWeb.Endpoint,
    router: MehungryWeb.Router

  use Phoenix.Component

  alias Mehungry.History.MealType

  @doc """
  A blueprint summary card linking to its public preview, with an author block
  (avatar + name + role) linking to the creator's profile. Expects a blueprint
  with `:condition` and (optionally) `user: :professional_profile` preloaded and
  `:plans_count` populated.
  """
  attr :blueprint, :map, required: true
  attr :class, :string, default: ""

  def blueprint_card(assigns) do
    assigns = assign(assigns, :author, author(assigns.blueprint))

    ~H"""
    <div class={[
      "group flex flex-col bg-ink-panel border border-ink-panel2 rounded-xl overflow-hidden hover:border-basil/50 transition",
      @class
    ]}>
      <.link navigate={~p"/blueprints/#{@blueprint.slug}"} class="block p-4 flex-1">
        <div class="flex items-start gap-2">
          <.icon_clipboard />
          <div class="min-w-0 flex-1">
            <div class="font-semibold text-parchment truncate group-hover:text-basil transition">
              {@blueprint.name}
            </div>
            <div :if={@blueprint.description} class="text-parchment-dim text-sm truncate mt-0.5">
              {@blueprint.description}
            </div>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-1.5 mt-3">
          <span
            :if={@blueprint.condition}
            class="text-[11px] px-2 py-0.5 rounded-full bg-paprika/15 text-paprika-soft"
          >
            {@blueprint.condition.name}
          </span>
          <span class="text-[11px] px-2 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim">
            7 days · 5 meals/day
          </span>
          <span
            :if={(@blueprint.plans_count || 0) > 0}
            class="text-[11px] px-2 py-0.5 rounded-full bg-basil/15 text-basil"
          >
            {@blueprint.plans_count} sample {plural(@blueprint.plans_count, "plan")}
          </span>
        </div>
      </.link>

      <.link
        :if={@author}
        navigate={author_path(@author)}
        class="flex items-center gap-2.5 px-4 py-3 border-t border-ink-panel2 hover:bg-ink-panel2/60 transition"
      >
        <.author_avatar author={@author} />
        <div class="min-w-0">
          <div class="text-parchment text-xs font-medium truncate">
            {author_display_name(@author)}
          </div>
          <div class="text-parchment-dim text-[11px] truncate">{author_role(@author)}</div>
        </div>
      </.link>
    </div>
    """
  end

  @doc """
  "How your week measures up" panel — a read-only summary of how a user's actual
  calendar week satisfies a followed blueprint's goals, plus a per-day breakdown.
  Fed by `Mehungry.MealBlueprints.calendar_progress/3` (atom-keyed day reports).

  Emits a `stop_following_blueprint` event (handled by the parent calendar
  LiveView) to dismiss the panel.
  """
  attr :blueprint, :map, required: true
  attr :progress, :map, required: true

  def blueprint_progress(assigns) do
    ~H"""
    <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-4 mb-3">
      <div class="flex items-start justify-between gap-3 mb-3">
        <div class="min-w-0">
          <h3 class="font-display font-medium text-parchment text-sm flex items-center gap-2">
            <svg
              class="w-4 h-4 text-basil shrink-0"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            How your week measures up
          </h3>
          <p class="text-parchment-dim text-xs mt-1 truncate">
            Following <span class="text-parchment">{@blueprint.name}</span>
            · {week_range_label(@progress)}
          </p>
        </div>
        <button
          type="button"
          phx-click="stop_following_blueprint"
          class="shrink-0 text-parchment-dim hover:text-parchment text-xs px-2 py-1 rounded-lg hover:bg-ink-panel2 transition"
        >
          Stop following
        </button>
      </div>

      <%!-- Week summary. Goals/Avoid chips live on each day's header now, so the
            week panel keeps only preferred foods + the calorie rollup. --%>
      <div class="space-y-2">
        <div
          :if={(@blueprint.preferred_foods || []) != []}
          class="flex flex-wrap items-center gap-1.5"
        >
          <span class="text-parchment-dim text-xs mr-1">Preferred foods:</span>
          <span
            :for={food <- @blueprint.preferred_foods}
            class="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full normal-case bg-basil/15 text-basil border border-basil/30"
          >
            {food}
          </span>
        </div>

        <div class="flex items-center gap-1.5">
          <span class="text-parchment-dim text-xs mr-1">Calories:</span>
          <span :if={@progress.calorie_days_with_target > 0} class="text-xs text-parchment">
            {@progress.calorie_days_on_target}/{@progress.calorie_days_with_target} days on target
          </span>
          <span :if={@progress.calorie_days_with_target == 0} class="text-xs text-parchment-dim">
            No calorie targets set
          </span>
        </div>
      </div>

      <%!-- Per-day breakdown --%>
      <div class="mt-3 pt-3 border-t border-ink-panel2 grid grid-cols-1 sm:grid-cols-2 gap-1.5">
        <div :for={i <- 1..7} class="flex items-center gap-2 text-xs">
          <span class="text-parchment-dim w-28 shrink-0 normal-case">
            Day {i} · {day_label(@progress, i)}
          </span>
          <.day_calorie_badge report={day_report(@progress, i)} />
          <span
            :if={day_violations(@progress, i) > 0}
            class="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full bg-paprika/20 text-paprika"
            title={"#{day_violations(@progress, i)} avoid-list item(s) among this day's meals"}
          >
            ⚠ {day_violations(@progress, i)}
          </span>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Required-goal chips (compounds + nutrients) with their current measure — a
  caloric percentage or an absolute amount in the nutrient's unit — baked into
  the label. Shared by the week panel and the calendar day header.
  """
  attr :entries, :list, required: true

  def goal_chips(assigns) do
    ~H"""
    <span
      :for={req <- @entries}
      class={[
        "inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full normal-case",
        if(req.met,
          do: "bg-basil/20 text-basil border border-basil/40",
          else: "bg-ink-panel2 text-parchment-dim border border-ink-panel2"
        )
      ]}
      title={required_title(req)}
    >
      {if req.met, do: "✓", else: "○"} {req.name}{pct_suffix(req)}
    </span>
    """
  end

  @doc """
  Avoid chips (compounds + nutrients) with their current measure vs the ceiling.
  Shared by the week panel and the calendar day header.
  """
  attr :entries, :list, required: true

  def avoid_chips(assigns) do
    ~H"""
    <span
      :for={a <- @entries}
      class={[
        "inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full normal-case",
        if(a.flagged,
          do: "bg-paprika/20 text-paprika border border-paprika/40",
          else: "bg-basil/20 text-basil border border-basil/40"
        )
      ]}
      title={avoid_title(a)}
    >
      {if a.flagged, do: "⚠", else: "✓"} {a.name}{avoid_pct_suffix(a)}
    </span>
    """
  end

  attr :report, :any, default: nil

  defp day_calorie_badge(%{report: report} = assigns)
       when is_nil(report) or is_map_key(report, :calorie_status) == false do
    ~H""
  end

  defp day_calorie_badge(%{report: %{calorie_status: :no_target}} = assigns), do: ~H""

  defp day_calorie_badge(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full [font-variant-numeric:tabular-nums]",
        calorie_badge_class(@report.calorie_status)
      ]}
    >
      {@report.calorie_total} / {@report.calorie_target} kcal
      <span :if={@report.calorie_status != :ok}>{calorie_delta_label(@report.calorie_delta)}</span>
    </span>
    """
  end

  defp calorie_badge_class(:over), do: "bg-paprika/20 text-paprika"
  defp calorie_badge_class(:under), do: "bg-amber-500/20 text-amber-400"
  defp calorie_badge_class(:ok), do: "bg-basil/20 text-basil"
  defp calorie_badge_class(_), do: "bg-ink-panel2 text-parchment-dim"

  defp calorie_delta_label(delta) when is_integer(delta) and delta > 0, do: "· +#{delta}"
  defp calorie_delta_label(delta) when is_integer(delta), do: "· #{delta}"
  defp calorie_delta_label(_), do: ""

  # Nutrient coverage/violation entries carry a threshold (`:mode`); compound
  # entries do not. pct mode renders "32% / ≥30%"; amount mode "1800 / ≤2300 mg".
  defp has_threshold?(entry), do: is_map(entry) and Map.has_key?(entry, :mode)

  # The measured value for an entry ("32%" in pct mode; the bare number in amount
  # mode — the unit rides on the target label, e.g. "1800 / ≤2300 mg").
  defp measured_label(%{mode: :amount, amount: amount}), do: fmt_amount(amount)
  defp measured_label(%{mode: :pct, pct: pct}), do: "#{fmt_amount(pct)}%"

  # The threshold with its comparator and unit ("≥30%" or "≤2300 mg").
  defp target_label(%{mode: :amount, target: target, unit: unit}, cmp),
    do: "#{cmp}#{fmt_amount(target)} #{unit || ""}" |> String.trim()

  defp target_label(%{mode: :pct, target: target}, cmp), do: "#{cmp}#{target}%"

  # Each chip shows the complementary current value in parentheses: pct-mode shows
  # the absolute quantity ("(0.4 g)"); amount-mode shows the caloric share ("(6%)"),
  # hidden for non-energy nutrients where it is 0.
  defp current_paren(%{mode: :pct} = entry) do
    amount = fmt_amount(Map.get(entry, :amount, 0))
    unit = Map.get(entry, :unit)

    cond do
      amount == "0" -> ""
      unit in [nil, ""] -> " (#{amount})"
      true -> " (#{amount} #{unit})"
    end
  end

  defp current_paren(%{mode: :amount} = entry) do
    case Map.get(entry, :pct, 0) do
      pct when is_number(pct) and pct > 0 -> " (#{pct}%)"
      _ -> ""
    end
  end

  defp current_paren(_entry), do: ""

  defp pct_suffix(entry) do
    if has_threshold?(entry),
      do: " #{measured_label(entry)} / #{target_label(entry, "≥")}#{current_paren(entry)}",
      else: ""
  end

  defp avoid_pct_suffix(entry) do
    if has_threshold?(entry),
      do: " #{measured_label(entry)} / #{target_label(entry, "≤")}#{current_paren(entry)}",
      else: ""
  end

  # Compact number: drop the decimal for whole values ("1800"), else one place
  # ("0.4").
  defp fmt_amount(n) when is_number(n) do
    rounded = Float.round(n * 1.0, 1)

    if rounded == Float.round(rounded, 0),
      do: Integer.to_string(trunc(rounded)),
      else: :erlang.float_to_binary(rounded, decimals: 1)
  end

  defp fmt_amount(_), do: "0"

  defp required_title(req) do
    cond do
      has_threshold?(req) and req.met ->
        "#{req.name}: #{measured_label(req)} this week (target #{target_label(req, "≥")})"

      has_threshold?(req) ->
        "#{req.name}: #{measured_label(req)} this week, below the #{target_label(req, "≥")} target"

      req.met ->
        "#{req.name} is covered by a meal this week"

      true ->
        "No meal this week includes #{req.name}"
    end
  end

  defp avoid_title(a) do
    cond do
      has_threshold?(a) and a.flagged ->
        "#{a.name}: #{measured_label(a)} this week, over the #{target_label(a, "≤")} limit"

      has_threshold?(a) ->
        "#{a.name}: #{measured_label(a)} this week, within the #{target_label(a, "≤")} limit"

      a.flagged ->
        "This week's meals include #{a.name}, which the blueprint says to avoid"

      true ->
        "No meal this week includes #{a.name}"
    end
  end

  defp day_report(progress, day_index), do: Map.get(progress.days, day_index)

  defp day_violations(progress, day_index) do
    case day_report(progress, day_index) do
      %{violation_count: count} -> count
      _ -> 0
    end
  end

  defp day_label(progress, day_index) do
    progress.week_start
    |> Date.add(day_index - 1)
    |> Calendar.strftime("%a %-d")
  end

  defp week_range_label(progress) do
    "#{Calendar.strftime(progress.week_start, "%b %-d")} – #{Calendar.strftime(progress.week_end, "%b %-d")}"
  end

  @doc """
  Renders a generated plan's meals grouped by relative day (1..7). Expects each
  meal to have `:recipe` and `:ingredient` preloaded.
  """
  attr :meals, :list, required: true

  def plan_meals(assigns) do
    ~H"""
    <div :if={@meals == []} class="text-parchment-dim text-xs py-2">
      No meals in this plan.
    </div>
    <div class="space-y-3">
      <div :for={{day_index, meals} <- group_by_day_index(@meals)}>
        <div class="text-parchment-dim text-xs font-semibold uppercase tracking-wide mb-1.5">
          Day {day_index}
        </div>
        <div class="space-y-1.5">
          <div :for={m <- meals} class="flex items-center gap-2">
            <span class="text-parchment-dim text-[11px] w-24 shrink-0">
              {MealType.label(m.meal_type)}
            </span>
            <div class="min-w-0 flex-1">
              <.recipe_line m={m} />
              <.ingredient_line m={m} />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── internal components / helpers ─────────────────────────────────────────────

  defp icon_clipboard(assigns) do
    ~H"""
    <span class="w-9 h-9 rounded-lg bg-basil/15 text-basil flex items-center justify-center shrink-0">
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
        />
      </svg>
    </span>
    """
  end

  attr :m, :map, required: true

  def recipe_line(%{m: %{recipe: recipe}} = assigns) when not is_nil(recipe) do
    ~H"""
    <div class="flex items-center gap-2 py-0.5">
      <div class="w-9 h-9 rounded-md overflow-hidden bg-ink-panel2 shrink-0">
        <img
          :if={@m.recipe.image_url}
          src={@m.recipe.image_url}
          alt={@m.recipe.title}
          class="w-full h-full object-cover"
        />
        <div
          :if={!@m.recipe.image_url}
          class="w-full h-full flex items-center justify-center text-parchment-dim text-xs"
        >
          🍽
        </div>
      </div>
      <div class="min-w-0">
        <div class="text-sm text-parchment truncate">{@m.recipe.title}</div>
        <div class="text-parchment-dim text-[11px] truncate">{recipe_info(@m.recipe)}</div>
      </div>
    </div>
    """
  end

  def recipe_line(assigns), do: ~H""

  attr :m, :map, required: true

  def ingredient_line(%{m: %{ingredient: ingredient}} = assigns) when not is_nil(ingredient) do
    ~H"""
    <div class="flex items-center justify-between gap-2 py-0.5 pl-1">
      <div class="flex items-center gap-2 min-w-0">
        <span class="w-9 h-9 rounded-md bg-basil/15 text-basil flex items-center justify-center text-xs shrink-0">
          🥗
        </span>
        <span class="text-sm text-parchment truncate">{@m.ingredient.name}</span>
      </div>
      <span class="text-parchment-dim text-xs shrink-0 [font-variant-numeric:tabular-nums]">
        {format_quantity(@m.quantity)} {Mehungry.Food.RecipeIngredient.unit_label(@m)}
      </span>
    </div>
    """
  end

  def ingredient_line(assigns), do: ~H""

  defp group_by_day_index(meals) do
    meals
    |> Enum.group_by(& &1.day_index)
    |> Enum.sort_by(fn {day_index, _} -> day_index end)
  end

  defp recipe_info(recipe) do
    [
      recipe.servings && "#{recipe.servings} servings",
      difficulty_label(recipe.difficulty),
      cooking_time(recipe)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp difficulty_label(1), do: "Easy"
  defp difficulty_label(2), do: "Medium"
  defp difficulty_label(3), do: "Difficult"
  defp difficulty_label(_), do: nil

  defp cooking_time(%{cooking_time_lower_limit: t}) when is_integer(t) and t > 0, do: "#{t} min"
  defp cooking_time(_), do: nil

  defp format_quantity(q) when is_float(q) do
    if q == Float.round(q), do: q |> trunc() |> Integer.to_string(), else: Float.to_string(q)
  end

  defp format_quantity(nil), do: ""
  defp format_quantity(q), do: to_string(q)

  # Author avatar: the creator's photo (professional photo first, then their
  # account picture), falling back to a monogram tile when neither is set.
  attr :author, :map, required: true

  defp author_avatar(assigns) do
    assigns = assign(assigns, :avatar_url, author_avatar_url(assigns.author))

    ~H"""
    <span class="w-8 h-8 rounded-full overflow-hidden bg-basil/15 text-basil flex items-center justify-center shrink-0 ring-1 ring-ink-panel2">
      <img
        :if={@avatar_url}
        src={@avatar_url}
        alt={author_display_name(@author)}
        class="w-full h-full object-cover"
      />
      <span :if={!@avatar_url} class="text-xs font-semibold uppercase">
        {author_initial(@author)}
      </span>
    </span>
    """
  end

  # The creator user, whenever the `:user` association is actually loaded — a
  # blueprint may be rendered without it preloaded. We show the author even when
  # the account has no `name` (email signups), falling back on the display name.
  defp author(%{user: %Mehungry.Accounts.User{} = user}), do: user
  defp author(_), do: nil

  # A public professional profile makes the author link resolve to the public
  # nutritionist page; otherwise it points at their regular user profile.
  defp author_path(user) do
    case public_professional_profile(user) do
      %{slug: slug} when is_binary(slug) and slug != "" -> ~p"/nutritionists/#{slug}"
      _ -> ~p"/profile/#{user.id}"
    end
  end

  # Prefer the public professional display name, then the account name, then the
  # local part of the email — the same `name || email` fallback used elsewhere —
  # so an author is always named even for a nameless email account.
  defp author_display_name(user) do
    case public_professional_profile(user) do
      %{display_name: name} when is_binary(name) and name != "" -> name
      _ -> presence(user.name) || email_handle(user)
    end
  end

  defp email_handle(%{email: email}) when is_binary(email) do
    email |> String.split("@") |> List.first()
  end

  defp email_handle(_), do: "Community member"

  # The role line under the name: the nutritionist's specialization for a public
  # professional, else a plain "Meal blueprint author" attribution.
  defp author_role(user) do
    case public_professional_profile(user) do
      %{specialization: spec} when is_binary(spec) and spec != "" -> spec
      %{} -> "Nutritionist"
      _ -> "Meal blueprint author"
    end
  end

  defp author_avatar_url(user) do
    professional_photo =
      case public_professional_profile(user) do
        %{photo_url: url} when is_binary(url) and url != "" -> url
        _ -> nil
      end

    professional_photo || presence(user.profile_pic)
  end

  defp author_initial(user) do
    user |> author_display_name() |> String.first() |> Kernel.||("?")
  end

  # The author's professional profile only when it is loaded *and* public;
  # a private or unloaded profile is treated as absent.
  defp public_professional_profile(%{professional_profile: %{is_public: true} = profile}),
    do: profile

  defp public_professional_profile(_), do: nil

  defp presence(value) when is_binary(value) and value != "", do: value
  defp presence(_), do: nil

  defp plural(1, word), do: word
  defp plural(_, word), do: word <> "s"
end
