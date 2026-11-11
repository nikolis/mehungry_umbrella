defmodule MehungryWeb.NutritionistLive.ClientDetailComponents do
  @moduledoc """
  Presentational function components for the nutritionist **client file**
  (`MehungryWeb.NutritionistLive.ClientDetail`).

  The LiveView owns all data, events and computation; this module owns the
  markup. It follows the warm `ink`/`parchment`/`basil`/`paprika` design system
  (`docs/implementation/infrastructure/design_system.md`): every surface is a
  `<.panel_card>`, every control an `<.action>`, every glyph an `<.icon>`, and
  there is exactly **one** `:primary` action on the screen (View Plan, in the
  header). `basil` is reserved for data, never a button.

  Layout zones, top to bottom: header → summary strip → progress → a two-column
  workspace (clinical record / communication + planning) → collapsed history.
  """
  use MehungryWeb, :html

  alias Phoenix.LiveView.JS
  alias Mehungry.Professionals.DietaryHistory.Fields
  alias MehungryWeb.AnthropometricLabels
  alias MehungryWeb.DietaryHistory.Labels
  alias MehungryWeb.MeasurementChart

  # ── Zone 0: header ──────────────────────────────────────────────────────────────

  attr(:client, :any, required: true)
  attr(:client_id, :any, required: true)
  attr(:unread_count, :integer, default: 0)

  def client_header(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-4 mb-6">
      <.link
        navigate={~p"/nutritionist/clients"}
        aria-label={gettext("Back to clients")}
        class="text-parchment-dim hover:text-parchment"
      >
        <.icon name="hero-arrow-left" class="w-5 h-5" />
      </.link>

      <%= if @client.profile_pic do %>
        <img src={@client.profile_pic} alt="" class="w-12 h-12 rounded-full object-cover shrink-0" />
      <% else %>
        <div
          aria-hidden="true"
          class="w-12 h-12 rounded-full bg-basil flex items-center justify-center text-ink font-bold shrink-0"
        >
          {String.first(@client.name || "?")}
        </div>
      <% end %>

      <div class="min-w-0">
        <h1 class="text-2xl font-display font-bold text-parchment truncate">
          {@client.name || @client.email}
        </h1>
        <p class="text-parchment-dim text-sm truncate">{@client.email}</p>
      </div>

      <div class="ml-auto flex flex-wrap items-center gap-2">
        <.link
          :if={@unread_count > 0}
          patch={~p"/nutritionist/clients/#{@client_id}?#{[tab: "messages"]}"}
          class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-paprika/15 text-paprika-soft text-xs font-semibold hover:bg-paprika/25"
        >
          <.icon name="hero-chat-bubble-left-right" class="w-3.5 h-3.5" />
          {ngettext("%{count} unread message", "%{count} unread messages", @unread_count,
            count: @unread_count
          )}
        </.link>
        <.action variant={:primary} size={:sm} href={"/nutritionist/clients/#{@client_id}/calendar"}>
          <.icon name="hero-calendar-days" class="w-4 h-4" /> {gettext("View Plan")}
        </.action>
        <.action
          variant={:secondary}
          size={:sm}
          href={"/nutritionist/appointments?client_id=#{@client_id}"}
        >
          {gettext("Schedule Appointment")}
        </.action>
        <.action variant={:secondary} size={:sm} phx-click="edit_client_details">
          {gettext("Edit details")}
        </.action>
      </div>
    </div>
    """
  end

  # ── Tab bar ───────────────────────────────────────────────────────────────────────

  attr(:tab, :string, required: true)
  attr(:client_id, :any, required: true)
  attr(:unread_count, :integer, default: 0)

  @tabs [
    {"overview", "hero-squares-2x2"},
    {"record", "hero-clipboard-document-list"},
    {"messages", "hero-chat-bubble-left-right"},
    {"planning", "hero-clipboard-document-check"}
  ]

  # Each tab is one of the nutritionist's jobs. `patch` keeps it a URL so back /
  # forward / deep-links work; the Messages tab carries the unread badge.
  def client_tabs(assigns) do
    assigns = assign(assigns, :tabs, @tabs)

    ~H"""
    <div class="border-b border-ink-panel2 mb-6">
      <nav class="flex gap-1 overflow-x-auto" aria-label={gettext("Client sections")}>
        <.link
          :for={{key, icon} <- @tabs}
          patch={~p"/nutritionist/clients/#{@client_id}?#{[tab: key]}"}
          aria-current={@tab == key && "page"}
          class={[
            "flex-shrink-0 inline-flex items-center gap-2 rounded-t-lg px-4 py-2.5 text-sm font-medium border-b-2 -mb-px transition-colors motion-reduce:transition-none focus-visible:outline focus-visible:outline-2 focus-visible:outline-paprika",
            if(@tab == key,
              do: "border-basil text-parchment",
              else: "border-transparent text-parchment-dim hover:text-parchment"
            )
          ]}
        >
          <.icon name={icon} class="w-4 h-4 flex-shrink-0" />
          <span>{tab_label(key)}</span>
          <span
            :if={key == "messages" and @unread_count > 0}
            class="inline-flex items-center justify-center min-w-[1.25rem] h-5 px-1.5 rounded-full bg-paprika text-ink text-[11px] font-bold tabular-nums"
          >
            {@unread_count}
          </span>
        </.link>
      </nav>
    </div>
    """
  end

  defp tab_label("overview"), do: gettext("Overview")
  defp tab_label("record"), do: gettext("Record")
  defp tab_label("messages"), do: gettext("Messages")
  defp tab_label("planning"), do: gettext("Planning")

  # ── Session ribbon — the "you have X shortly" prep strip ────────────────────────────

  attr(:next_session, :any, default: nil)
  attr(:summary, :map, required: true)
  attr(:client_id, :any, required: true)

  # Opens the Overview when there's an appointment within the window: the whole
  # prep job compressed to one glance — when, what kind, what was agreed last
  # time, and the button to log the visit. No appointment → nothing renders.
  def session_ribbon(assigns) do
    ~H"""
    <div
      :if={@next_session}
      class="mb-6 rounded-xl border border-paprika/40 bg-paprika/10 border-l-4 border-l-paprika p-4 flex flex-wrap items-center gap-x-6 gap-y-2"
    >
      <div class="min-w-0">
        <p class="text-[11px] uppercase tracking-wide font-semibold text-paprika-soft inline-flex items-center gap-1.5">
          <.icon name="hero-clock" class="w-3.5 h-3.5" /> {session_when(@next_session.scheduled_at)}
        </p>
        <p class="text-parchment font-medium truncate">
          {@next_session.title}
          <span class="text-parchment-dim font-normal">· {appointment_modality(@next_session)}</span>
        </p>
      </div>

      <div :if={@summary.last_visit} class="min-w-0 text-sm">
        <span class="text-parchment-dim">{gettext("Last time")}:</span>
        <span class="text-parchment">
          {if @summary.last_visit.visit_date,
            do: Calendar.strftime(@summary.last_visit.visit_date, "%b %d"),
            else: "—"}
        </span>
        <span :if={present?(@summary.next_steps)} class="text-parchment-dim">
          — "<span class="text-parchment italic">{@summary.next_steps}</span>"
        </span>
      </div>

      <.action variant={:primary} size={:sm} phx-click="new_visit" class="ml-auto whitespace-nowrap">
        <.icon name="hero-plus" class="w-4 h-4" /> {gettext("Log visit")}
      </.action>
    </div>
    """
  end

  # "Today 14:00" / "Tomorrow 09:30" / "Thu, Mar 12 · 10:00" from a naive UTC stamp.
  defp session_when(%NaiveDateTime{} = at) do
    date = NaiveDateTime.to_date(at)
    time = Calendar.strftime(at, "%H:%M")

    cond do
      date == Date.utc_today() -> gettext("Today %{time}", time: time)
      date == Date.add(Date.utc_today(), 1) -> gettext("Tomorrow %{time}", time: time)
      true -> "#{Calendar.strftime(at, "%a, %b %d")} · #{time}"
    end
  end

  defp session_when(_), do: nil

  # Appointments carry no modality column — one with a meeting link is online.
  defp appointment_modality(%{meeting_url: url}) when is_binary(url) and url != "",
    do: gettext("Online")

  defp appointment_modality(_), do: gettext("In person")

  # ── Zone 1: at-a-glance summary strip ─────────────────────────────────────────────

  attr(:summary, :map, required: true)
  attr(:goal_editing?, :boolean, default: false)

  def client_summary(assigns) do
    assigns =
      assigns
      |> assign(:bmi_dot, band_tone(assigns.summary.bmi, assigns.summary.bmi_band))
      |> assign(:reference_items, reference_items(assigns.summary.intake))

    ~H"""
    <div class="mb-6">
    <div class="grid grid-cols-2 sm:grid-cols-3 xl:grid-cols-6 gap-2.5">
      <!-- Goal — edits inline; one sentence shouldn't open the whole intake form -->
      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-3 flex flex-col gap-0.5">
        <span class="text-[11px] uppercase tracking-wide font-semibold text-parchment-dim inline-flex items-center gap-1">
          <.icon name="hero-flag" class="w-3 h-3 text-paprika" /> {gettext("Goal")}
        </span>
        <%= cond do %>
          <% @goal_editing? -> %>
            <form phx-submit="save_goal" class="flex items-center gap-1 mt-0.5">
              <input
                type="text"
                name="goal"
                value={@summary.goal}
                autofocus
                aria-label={gettext("Goal")}
                class="w-full min-w-0 bg-ink border border-ink-panel2 rounded-lg px-2 py-1 text-parchment text-xs focus:outline-none focus:border-paprika"
              />
              <button
                type="submit"
                aria-label={gettext("Save goal")}
                class="text-basil hover:text-parchment shrink-0"
              >
                <.icon name="hero-check" class="w-4 h-4" />
              </button>
              <button
                type="button"
                phx-click="cancel_goal"
                aria-label={gettext("Cancel")}
                class="text-parchment-dim hover:text-parchment shrink-0"
              >
                <.icon name="hero-x-mark" class="w-4 h-4" />
              </button>
            </form>
          <% present?(@summary.goal) -> %>
            <button
              type="button"
              phx-click="edit_goal"
              title={gettext("Edit goal")}
              class="text-left group/goal"
            >
              <span class="text-parchment text-sm font-medium leading-snug line-clamp-2">
                {@summary.goal}
                <.icon
                  name="hero-pencil"
                  class="w-3 h-3 inline text-parchment-dim opacity-0 group-hover/goal:opacity-100"
                />
              </span>
            </button>
          <% true -> %>
            <.action variant={:ghost} size={:sm} phx-click="edit_goal" class="self-start px-0 mt-0.5">
              {gettext("Set a goal")}
            </.action>
        <% end %>
      </div>

      <!-- Weight → target -->
      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-3 flex flex-col gap-0.5">
        <span class="text-[11px] uppercase tracking-wide font-semibold text-parchment-dim">
          {gettext("Weight")}
        </span>
        <%= if @summary.weight_card do %>
          <span class="font-display text-xl text-parchment leading-tight tabular-nums">
            {@summary.weight_card.current_display}
          </span>
          <span class={["text-xs font-semibold tabular-nums", tone_text(@summary.weight_card.tone)]}>
            {@summary.weight_card.arrow} {@summary.weight_card.delta_abs}
            <span :if={@summary.ideal_weight_kg} class="text-parchment-dim font-normal">
              {gettext("/ goal %{w} kg", w: MeasurementChart.fmt_num(@summary.ideal_weight_kg))}
            </span>
          </span>
        <% else %>
          <span class="text-parchment-dim text-sm">{gettext("No readings yet")}</span>
        <% end %>
      </div>

      <!-- BMI with healthy-band dot -->
      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-3 flex flex-col gap-0.5">
        <span class="text-[11px] uppercase tracking-wide font-semibold text-parchment-dim">
          {gettext("BMI")}
        </span>
        <%= if @summary.bmi do %>
          <span class="font-display text-xl text-parchment leading-tight tabular-nums inline-flex items-center gap-1.5">
            {@summary.bmi}
            <span
              :if={@bmi_dot}
              class={[
                "w-2 h-2 rounded-full",
                @bmi_dot == :good && "bg-basil",
                @bmi_dot == :warn && "bg-warning-500"
              ]}
              title={band_label(@bmi_dot)}
            ></span>
          </span>
        <% else %>
          <span class="text-parchment-dim text-sm">—</span>
        <% end %>
      </div>

      <!-- Energy needs from the latest intake: TDEE leads, BMR rides along -->
      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-3 flex flex-col gap-0.5">
        <span class="text-[11px] uppercase tracking-wide font-semibold text-parchment-dim">
          {gettext("Energy")}
        </span>
        <%= if @summary.intake && (@summary.intake.tdee_kcal || @summary.intake.bmr_kcal) do %>
          <span :if={@summary.intake.tdee_kcal} class="font-display text-xl text-parchment leading-tight tabular-nums">
            {@summary.intake.tdee_kcal}<span class="text-xs text-parchment-dim ml-0.5 font-sans">
              {gettext("kcal TDEE")}
            </span>
          </span>
          <span :if={@summary.intake.bmr_kcal} class="text-parchment-dim text-xs tabular-nums">
            {gettext("BMR %{kcal} kcal", kcal: @summary.intake.bmr_kcal)}
          </span>
        <% else %>
          <span class="text-parchment-dim text-sm">—</span>
        <% end %>
      </div>

      <!-- Last visit -->
      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-3 flex flex-col gap-0.5">
        <span class="text-[11px] uppercase tracking-wide font-semibold text-parchment-dim">
          {gettext("Last visit")}
        </span>
        <%= if @summary.last_visit do %>
          <span class="text-parchment text-sm font-medium">
            {if @summary.last_visit.visit_date,
              do: Calendar.strftime(@summary.last_visit.visit_date, "%b %d, %Y"),
              else: "—"}
          </span>
          <span class="text-parchment-dim text-xs">{modality_label(@summary.last_visit.modality)}</span>
        <% else %>
          <span class="text-parchment-dim text-sm">{gettext("No visits yet")}</span>
        <% end %>
      </div>

      <!-- Next steps — the to-do agreed at the last visit, surfaced for prep -->
      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-3 flex flex-col gap-0.5">
        <span class="text-[11px] uppercase tracking-wide font-semibold text-parchment-dim inline-flex items-center gap-1">
          <.icon name="hero-arrow-right-circle" class="w-3 h-3 text-paprika" /> {gettext("Next steps")}
        </span>
        <%= if present?(@summary.next_steps) do %>
          <span
            class="text-parchment text-sm font-medium leading-snug line-clamp-2"
            title={@summary.next_steps}
          >
            {@summary.next_steps}
          </span>
        <% else %>
          <span class="text-parchment-dim text-sm">
            {if @summary.last_visit, do: gettext("Nothing recorded"), else: "—"}
          </span>
        <% end %>
      </div>
    </div>

    <!-- Reference values from the latest intake -->
    <div
      :if={@reference_items != []}
      class="flex flex-wrap gap-x-4 gap-y-1 mt-2.5 px-1 text-xs text-parchment-dim"
    >
      <span :for={{label, value} <- @reference_items} class="whitespace-nowrap">
        {label} <span class="text-parchment font-medium tabular-nums">{value}</span>
      </span>
    </div>
    </div>
    """
  end

  # The compact reference line under the KPI strip — only the intake fields that
  # are actually filled in, as `{label, formatted value}` pairs.
  defp reference_items(nil), do: []

  defp reference_items(intake) do
    [
      {gettext("Sex"), intake.sex && AnthropometricLabels.sex_label(intake.sex)},
      {gettext("Age"), intake.age && "#{intake.age} #{gettext("yrs")}"},
      {gettext("Activity"),
       intake.activity_level && AnthropometricLabels.activity_label(intake.activity_level)},
      {gettext("Height"), intake.height_m && "#{intake.height_m} m"},
      {gettext("Weight at intake"), intake.weight_kg && "#{intake.weight_kg} kg"},
      {gettext("Ideal wt"), intake.ideal_weight_kg && "#{intake.ideal_weight_kg} kg"},
      {gettext("Usual wt"), intake.usual_weight_kg && "#{intake.usual_weight_kg} kg"},
      {gettext("Adjusted wt"), intake.adjusted_weight_kg && "#{intake.adjusted_weight_kg} kg"}
    ]
    |> Enum.filter(fn {_label, value} -> value end)
  end

  # ── Zone 2: progress ──────────────────────────────────────────────────────────────

  attr(:progress_cards, :list, required: true)
  attr(:selected_metric, :string, default: nil)
  attr(:progress_chart_svg, :any, default: nil)
  attr(:progress_legend, :list, default: [])

  def progress_panel(assigns) do
    ~H"""
    <.panel_card class="mb-6">
      <div class="flex items-center justify-between mb-4 gap-4">
        <h2 class="font-display text-base font-semibold text-parchment inline-flex items-center gap-2">
          <.icon name="hero-chart-bar" class="w-4 h-4 text-basil" /> {gettext("Progress trend")}
        </h2>
        <span :if={@progress_cards != []} class="text-parchment-dim text-xs">
          {gettext("tap a metric to chart it")}
        </span>
      </div>
      <%= if @progress_cards != [] do %>
        <MeasurementChart.progress_dashboard
          cards={@progress_cards}
          selected={@selected_metric}
          chart={@progress_chart_svg}
          legend={@progress_legend}
        />
      <% else %>
        <p class="text-parchment-dim text-sm">
          {gettext(
            "Not enough data yet — recorded measurements (weight, body fat, waist, muscle mass, hands, glutes, feet) will chart here once there are at least two readings."
          )}
        </p>
      <% end %>
    </.panel_card>
    """
  end

  # ── Zone 2b: the client's own shared self-tracking journal (read-only) ──────────────

  attr(:shared_journal, :any, default: nil)
  attr(:shared_cards, :list, default: [])
  attr(:shared_selected, :string, default: nil)
  attr(:shared_chart_svg, :any, default: nil)
  attr(:shared_legend, :list, default: [])

  def shared_journal_panel(assigns) do
    ~H"""
    <.panel_card :if={@shared_journal} class="mb-6">
      <div class="flex items-center justify-between mb-1 gap-4 flex-wrap">
        <h2 class="font-display text-base font-semibold text-parchment inline-flex items-center gap-2">
          <.icon name="hero-eye" class="w-4 h-4 text-basil" />
          {gettext("Client's own journal (shared with you)")}
        </h2>
        <span class="text-parchment-dim text-xs tabular-nums">
          {shared_period_range(@shared_journal.period)}
        </span>
      </div>
      <p class="text-parchment-dim text-xs mb-4">
        {gettext("Self-logged by the client — read-only. They can stop sharing at any time.")}
      </p>
      <%= if @shared_cards != [] do %>
        <MeasurementChart.progress_dashboard
          cards={@shared_cards}
          selected={@shared_selected}
          chart={@shared_chart_svg}
          legend={@shared_legend}
        />
      <% else %>
        <p class="text-parchment-dim text-sm">
          {gettext("The shared period doesn't have enough logged measurements to chart yet.")}
        </p>
      <% end %>
    </.panel_card>
    """
  end

  defp shared_period_range(%{started_on: s, ended_on: nil}),
    do: gettext("%{start} – ongoing", start: Calendar.strftime(s, "%b %d, %Y"))

  defp shared_period_range(%{started_on: s, ended_on: e}),
    do: "#{Calendar.strftime(s, "%b %d, %Y")} – #{Calendar.strftime(e, "%b %d, %Y")}"

  # ── Zone 3 (left): dietary history / intake ─────────────────────────────────────────

  attr(:record, :any, default: nil)
  attr(:intake, :any, default: nil)
  attr(:intakes, :list, default: [])
  attr(:selected_intake_id, :any, default: nil)
  attr(:intake_editing?, :boolean, default: false)
  attr(:intake_form, :any, default: nil)
  attr(:conditions, :list, default: [])
  attr(:all_conditions, :list, default: [])
  attr(:onboarding_answers, :list, default: [])
  attr(:onboarding_locale, :string, default: "en")

  def intake_panel(assigns) do
    latest_id =
      case assigns.intakes do
        [latest | _] -> latest.id
        _ -> nil
      end

    assigns =
      assign(assigns, :viewing_latest?, assigns.selected_intake_id == latest_id and latest_id != nil)

    ~H"""
    <.panel_card class="mb-6">
      <div class="flex items-center justify-between mb-4 gap-3">
        <div>
          <h2 class="font-display text-base font-semibold text-parchment inline-flex items-center gap-2">
            <.icon name="hero-clipboard-document-list" class="w-4 h-4 text-basil" />
            {gettext("Dietary History")}
          </h2>
          <.link
            :if={@record}
            navigate={~p"/nutritionist/records/#{@record.id}"}
            class="text-parchment-dim hover:text-parchment text-xs"
          >
            {gettext("Printable record →")}
          </.link>
        </div>
        <div :if={not @intake_editing?} class="flex items-center gap-2 shrink-0">
          <.action
            :if={@intake && @viewing_latest?}
            variant={:secondary}
            size={:sm}
            phx-click="edit_intake"
          >
            {gettext("Edit")}
          </.action>
          <.action
            :if={@intakes != []}
            variant={:ghost}
            size={:sm}
            phx-click="new_assessment"
          >
            {gettext("New assessment")}
          </.action>
          <.action
            :if={@intakes == []}
            variant={:secondary}
            size={:sm}
            phx-click="edit_intake"
          >
            {gettext("Add dietary history")}
          </.action>
        </div>
      </div>

      <!-- Assessment history: switch between dated assessments (latest editable,
           older ones read-only). -->
      <div :if={not @intake_editing? and length(@intakes) > 1} class="flex flex-wrap gap-1.5 mb-4">
        <button
          :for={a <- @intakes}
          type="button"
          phx-click="select_assessment"
          phx-value-id={a.id}
          class={[
            "px-2.5 py-1 rounded-full text-xs border transition-colors",
            if(a.id == @selected_intake_id,
              do: "bg-basil/15 text-basil border-basil/40",
              else: "border-ink-panel2 text-parchment-dim hover:text-parchment"
            )
          ]}
        >
          {assessment_date_label(a)}
        </button>
      </div>

      <p
        :if={not @intake_editing? and @intake && not @viewing_latest?}
        class="text-xs text-parchment-dim italic mb-3"
      >
        {gettext("Viewing a past assessment (read-only). Open the latest to edit.")}
      </p>

      <%= cond do %>
        <% @intake_editing? and @onboarding_answers != [] -> %>
          <!-- During intake, the client's own onboarding answers sit beside the
               form (copy into a field instead of re-typing their words). -->
          <div class="grid grid-cols-1 lg:grid-cols-[1fr_18rem] gap-6">
            <div class="min-w-0">
              <.intake_form intake={@intake} intake_form={@intake_form} />
            </div>
            <.onboarding_copy_aside
              onboarding_answers={@onboarding_answers}
              onboarding_locale={@onboarding_locale}
            />
          </div>
        <% @intake_editing? -> %>
          <.intake_form intake={@intake} intake_form={@intake_form} />
        <% @intake -> %>
          <.intake_display
            intake={@intake}
            conditions={@conditions}
            all_conditions={@all_conditions}
          />
        <% true -> %>
          <p class="text-parchment-dim text-sm mb-2">{gettext("No dietary history recorded yet.")}</p>
          <.conditions_panel conditions={@conditions} all_conditions={@all_conditions} />
      <% end %>
    </.panel_card>
    """
  end

  attr(:onboarding_answers, :list, default: [])
  attr(:onboarding_locale, :string, default: "en")

  # The client's own onboarding answers, each with a one-click copy (the Copy
  # hook reads the hidden input's value) so the nutritionist lifts the client's
  # exact words into the matching intake field instead of re-typing them.
  defp onboarding_copy_aside(assigns) do
    ~H"""
    <aside class="bg-ink border border-ink-panel2 rounded-lg p-3 self-start lg:sticky lg:top-4">
      <h3 class="text-[11px] uppercase tracking-wide font-semibold text-parchment-dim mb-3">
        {gettext("Client's onboarding answers")}
      </h3>
      <dl class="space-y-3 max-h-[32rem] overflow-y-auto overscroll-contain pr-1">
        <div :for={{{q, a}, idx} <- Enum.with_index(@onboarding_answers)}>
          <dt class="text-xs text-parchment-dim">{onboarding_prompt(q, a, @onboarding_locale)}</dt>
          <dd class="flex items-start gap-2 mt-0.5">
            <span class="text-parchment text-sm flex-1 min-w-0 whitespace-pre-line break-words">
              {onboarding_answer_text(q, a, @onboarding_locale)}
            </span>
            <input
              type="hidden"
              id={"onb-ans-#{idx}"}
              value={onboarding_answer_text(q, a, @onboarding_locale)}
            />
            <button
              type="button"
              id={"onb-copy-#{idx}"}
              phx-hook="Copy"
              data-to={"#onb-ans-#{idx}"}
              class="shrink-0 text-xs text-basil hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-paprika"
              title={gettext("Copy answer")}
            >
              <span>{gettext("Copy")}</span>
            </button>
          </dd>
        </div>
      </dl>
    </aside>
    """
  end

  attr(:intake, :any, required: true)
  attr(:conditions, :list, default: [])
  attr(:all_conditions, :list, default: [])

  # Chip label for an assessment — its assessed date, falling back to when it was
  # recorded.
  defp assessment_date_label(%{assessed_on: %Date{} = d}), do: Calendar.strftime(d, "%b %d, %Y")
  defp assessment_date_label(%{inserted_at: %_{} = at}), do: Calendar.strftime(at, "%b %d, %Y")
  defp assessment_date_label(_), do: gettext("Assessment")

  # Measurements and reference values live in the summary strip at the top of
  # the page (`client_summary`) — this panel is only the qualitative history,
  # grouped by lifecycle: conditions + clinical-flag chips stay always visible
  # (the every-visit safety layer), everything else folds into sections with
  # filled-field counts (lifestyle / medical / story & goals / 24h recall).
  defp intake_display(assigns) do
    {flags, sections} = grouped_details(assigns.intake)

    assigns =
      assigns
      |> assign(:flag_items, flags)
      |> assign(:sections, sections)
      |> assign(:recall_items, recall_items(assigns.intake))

    ~H"""
    <div>
      <p :if={@intake.assessed_on} class="text-parchment-dim text-xs mb-3">
        {gettext("Assessed %{date}", date: Calendar.strftime(@intake.assessed_on, "%b %d, %Y"))}
      </p>

      <.conditions_panel conditions={@conditions} all_conditions={@all_conditions} />

      <div :if={@flag_items != []} class="flex flex-wrap gap-2 mb-4">
        <span
          :for={{label, val} <- @flag_items}
          class="inline-flex items-baseline gap-1.5 max-w-full px-2.5 py-1 rounded-lg bg-ink border border-ink-panel2 text-xs"
          title={"#{label}: #{val}"}
        >
          <span class="text-parchment-dim shrink-0">{label}</span>
          <span class="text-parchment truncate">{val}</span>
        </span>
      </div>

      <div class="space-y-2">
        <.intake_section
          :for={{group, items} <- @sections}
          title={section_title(group)}
          items={items}
        />
        <.intake_section title={gettext("24-hour recall")} items={@recall_items} />
      </div>
    </div>
    """
  end

  attr(:title, :string, required: true)
  attr(:items, :list, required: true)

  # One collapsible lifecycle section — native <details>, same visual language
  # as the visit rows; the count tells what's inside before opening.
  defp intake_section(assigns) do
    ~H"""
    <details :if={@items != []} class="group border border-ink-panel2 rounded-lg overflow-hidden">
      <summary class="flex items-center gap-2 px-3 py-2.5 cursor-pointer select-none hover:bg-black/20 list-none">
        <h3 class="text-sm font-semibold text-parchment">{@title}</h3>
        <span class="text-parchment-dim text-xs tabular-nums">({length(@items)})</span>
        <.icon
          name="hero-chevron-down"
          class="w-4 h-4 text-parchment-dim ml-auto shrink-0 transition-transform group-open:rotate-180"
        />
      </summary>
      <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2 text-sm px-3 pb-3 pt-2 border-t border-ink-panel2">
        <div :for={{label, val} <- @items}>
          <dt class="text-parchment-dim text-xs">{label}</dt>
          <dd class="text-parchment whitespace-pre-line">{val}</dd>
        </div>
      </dl>
    </details>
    """
  end

  attr(:title, :string, required: true)
  attr(:filled, :integer, required: true)
  attr(:total, :integer, required: true)
  slot(:inner_block, required: true)

  # Collapsible group inside the intake edit form — same visual language as the
  # display sections. Inputs inside a closed <details> still submit with the
  # form, so folding is purely visual; the filled/total badge shows where data
  # already lives before opening.
  defp form_section(assigns) do
    ~H"""
    <details class="group border border-ink-panel2 rounded-lg overflow-hidden">
      <summary class="flex items-center gap-2 px-3 py-2.5 cursor-pointer select-none hover:bg-black/20 list-none">
        <h3 class="text-sm font-semibold text-parchment">{@title}</h3>
        <span class="text-parchment-dim text-xs tabular-nums">{@filled}/{@total}</span>
        <.icon
          name="hero-chevron-down"
          class="w-4 h-4 text-parchment-dim ml-auto shrink-0 transition-transform group-open:rotate-180"
        />
      </summary>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3 px-3 pb-3 pt-2 border-t border-ink-panel2">
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  defp filled_count(intake, fields),
    do: Enum.count(fields, fn {key, _label} -> present?(detail_value(intake, key)) end)

  defp recall_filled_count(intake),
    do: Enum.count(Fields.recall_labels(), fn {key, _} -> present?(recall_value(intake, key)) end)

  # Group the filled questionnaire fields by lifecycle (`Fields.detail_groups/0`):
  # returns `{flag_items, [{group, items}]}` with labels already translated.
  # Keys not assigned to a group fall back to :story so nothing ever vanishes;
  # the structured goal opens the :story section.
  defp grouped_details(intake) do
    details = if is_map(intake.details), do: intake.details, else: %{}

    key_group =
      for {group, keys} <- Fields.detail_groups(), key <- keys, into: %{}, do: {key, group}

    by_group =
      Fields.detail_labels()
      |> Enum.filter(fn {key, _label} -> present?(details[key]) end)
      |> Enum.group_by(
        fn {key, _label} -> Map.get(key_group, key, :story) end,
        fn {key, label} -> {Labels.translate(label), details[key]} end
      )

    goal = if present?(intake.goal), do: [{gettext("Goal"), intake.goal}], else: []

    sections =
      for group <- [:lifestyle, :medical, :story],
          items = section_items(group, by_group, goal),
          items != [],
          do: {group, items}

    {Map.get(by_group, :flags, []), sections}
  end

  defp section_items(:story, by_group, goal), do: goal ++ Map.get(by_group, :story, [])
  defp section_items(group, by_group, _goal), do: Map.get(by_group, group, [])

  defp recall_items(%{details: details}) when is_map(details) do
    case details["recall_24h"] do
      recall when is_map(recall) ->
        for {key, label} <- Fields.recall_labels(),
            val = recall[key],
            present?(val),
            do: {Labels.translate(label), val}

      _ ->
        []
    end
  end

  defp recall_items(_), do: []

  @doc false
  # Shared with the read-only record view (`ClientRecord`).
  def section_title(:flags), do: gettext("Clinical flags")
  def section_title(:lifestyle), do: gettext("Lifestyle & eating habits")
  def section_title(:medical), do: gettext("Medical background")
  def section_title(:story), do: gettext("Story & goals")

  @doc false
  # The edit form and the read-only record view mirror the display grouping —
  # `{group, [{key, label}]}` in group order; keys missing from the grouping
  # land in :story (same fallback as the display, so every questionnaire field
  # is always editable and rendered).
  def detail_field_groups do
    labels = Map.new(Fields.detail_labels())

    grouped_keys =
      Fields.detail_groups() |> Keyword.values() |> List.flatten() |> MapSet.new()

    leftover = for {key, _label} <- Fields.detail_labels(), key not in grouped_keys, do: key

    for {group, keys} <- Fields.detail_groups() do
      keys = if group == :story, do: keys ++ leftover, else: keys
      {group, for(key <- keys, Map.has_key?(labels, key), do: {key, labels[key]})}
    end
  end

  attr(:intake, :any, default: nil)
  attr(:intake_form, :any, required: true)

  defp intake_form(assigns) do
    ~H"""
    <.form
      :let={f}
      for={@intake_form}
      as={:intake}
      id="intake-form"
      phx-change="validate_intake"
      phx-submit="save_intake"
    >
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
        <.labeled label={gettext("Assessed on")}>
          <.input field={f[:assessed_on]} type="date" />
        </.labeled>
        <.labeled label={gettext("Sex")}>
          <.input
            field={f[:sex]}
            type="select"
            prompt="—"
            options={AnthropometricLabels.sex_options()}
          />
        </.labeled>
        <.labeled label={gettext("Age")}>
          <.input field={f[:age]} type="number" />
        </.labeled>
        <.labeled label={gettext("Activity level")}>
          <.input
            field={f[:activity_level]}
            type="select"
            prompt="—"
            options={AnthropometricLabels.activity_options()}
          />
        </.labeled>
        <.labeled label={gettext("Height (m)")}>
          <.input field={f[:height_m]} type="number" step="0.01" />
        </.labeled>
        <.labeled label={gettext("Weight (kg)")}>
          <.input field={f[:weight_kg]} type="number" step="0.1" />
        </.labeled>
        <.labeled label={gettext("BMI (auto)")}>
          <.input field={f[:bmi]} type="number" step="0.1" />
        </.labeled>
        <.labeled label={gettext("Usual wt (kg)")}>
          <.input field={f[:usual_weight_kg]} type="number" step="0.1" />
        </.labeled>
        <.labeled label={gettext("Ideal wt (kg)")}>
          <.input field={f[:ideal_weight_kg]} type="number" step="0.1" />
        </.labeled>
        <.labeled label={gettext("Adjusted wt (kg)")}>
          <.input field={f[:adjusted_weight_kg]} type="number" step="0.1" />
        </.labeled>
        <.labeled label={gettext("BMR (auto, kcal)")}>
          <.input field={f[:bmr_kcal]} type="number" />
        </.labeled>
        <.labeled label={gettext("TDEE (auto, kcal)")}>
          <.input field={f[:tdee_kcal]} type="number" />
        </.labeled>
      </div>
      <p class="text-parchment-dim text-xs -mt-2 mb-4">
        {gettext(
          "BMI, BMR and TDEE recompute from height, weight, sex, age and activity — type to override."
        )}
      </p>

      <.labeled label={gettext("Goal")}>
        <.input field={f[:goal]} type="text" />
      </.labeled>

      <div class="space-y-2 mt-5">
        <.form_section
          :for={{group, fields} <- detail_field_groups()}
          title={section_title(group)}
          filled={filled_count(@intake, fields)}
          total={length(fields)}
        >
          <%= for {key, label} <- fields do %>
            <.labeled label={Labels.translate(label)}>
              <textarea
                name={"intake[details][#{key}]"}
                rows="2"
                class="w-full bg-ink border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm"
              >{detail_value(@intake, key)}</textarea>
            </.labeled>
          <% end %>
        </.form_section>

        <.form_section
          title={gettext("24-hour recall")}
          filled={recall_filled_count(@intake)}
          total={length(Fields.recall_labels())}
        >
          <%= for {key, label} <- Fields.recall_labels() do %>
            <.labeled label={Labels.translate(label)}>
              <textarea
                name={"intake[details][recall_24h][#{key}]"}
                rows="2"
                class="w-full bg-ink border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm"
              >{recall_value(@intake, key)}</textarea>
            </.labeled>
          <% end %>
        </.form_section>
      </div>

      <div class="flex gap-2 mt-5">
        <.action variant={:primary} size={:sm} type="submit" phx-disable-with={gettext("Saving…")}>
          {gettext("Save dietary history")}
        </.action>
        <.action variant={:ghost} size={:sm} type="button" phx-click="cancel_intake">
          {gettext("Cancel")}
        </.action>
      </div>
    </.form>
    """
  end

  # Health conditions render as one more field in the Dietary History card: a
  # small label, the linked conditions as pills, and a minimal picker.
  attr(:conditions, :list, default: [])
  attr(:all_conditions, :list, default: [])

  defp conditions_panel(assigns) do
    linked_ids = Enum.map(assigns.conditions, & &1.id)

    assigns =
      assign(
        assigns,
        :available_conditions,
        Enum.reject(assigns.all_conditions, &(&1.id in linked_ids))
      )

    ~H"""
    <div class="mb-4">
      <h3 class="text-xs font-semibold uppercase tracking-wide text-parchment-dim mb-3">
        {gettext("Health conditions")}
      </h3>

      <div class="flex flex-wrap items-center gap-2">
        <%= if Enum.empty?(@conditions) do %>
          <span class="text-parchment-dim text-sm italic">{gettext("None recorded yet")}</span>
        <% else %>
          <%= for condition <- @conditions do %>
            <span class="inline-flex items-center gap-2 pl-3 pr-2 py-1 rounded-full bg-basil/15 text-basil text-xs">
              {condition.name}
              <.link
                navigate={~p"/nutritionist/research/notes?condition_id=#{condition.id}"}
                class="inline-flex items-center gap-0.5 text-basil hover:underline"
                title={gettext("Open my notes for %{name}", name: condition.name)}
              >
                <.icon name="hero-document-text" class="w-3 h-3" /> {gettext("Notes")}
              </.link>
              <button
                type="button"
                phx-click="remove_condition"
                phx-value-id={condition.id}
                aria-label={gettext("Remove %{name}", name: condition.name)}
                class="hover:text-parchment"
              >
                <.icon name="hero-x-mark" class="w-3 h-3" />
              </button>
            </span>
          <% end %>
        <% end %>

        <form
          :if={not Enum.empty?(@available_conditions)}
          phx-submit="add_condition"
          class="inline-flex items-center gap-2"
        >
          <select
            name="condition_id"
            class="bg-ink border border-ink-panel2 rounded-lg px-2.5 py-1.5 text-parchment text-xs"
          >
            <option value="">{gettext("+ Add condition")}</option>
            <%= for condition <- @available_conditions do %>
              <option value={condition.id}>{condition.name}</option>
            <% end %>
          </select>
          <.action variant={:secondary} size={:sm} type="submit">{gettext("Add")}</.action>
        </form>
      </div>
    </div>
    """
  end

  # ── Zone 3 (left): visits ───────────────────────────────────────────────────────────

  attr(:visits, :list, required: true)
  attr(:record, :any, default: nil)

  def visits_panel(assigns) do
    assigns = assign(assigns, :newest_id, newest_visit_id(assigns.visits))

    ~H"""
    <.panel_card class="mb-6">
      <div class="flex items-center justify-between mb-4">
        <div>
          <h2 class="font-display text-base font-semibold text-parchment inline-flex items-center gap-2">
            <.icon name="hero-document-text" class="w-4 h-4 text-basil" />
            {gettext("Client Record — Visits")}
          </h2>
          <.link
            :if={@record}
            navigate={~p"/nutritionist/records/#{@record.id}"}
            class="text-parchment-dim hover:text-parchment text-xs"
          >
            {gettext("Printable record →")}
          </.link>
          <p :if={is_nil(@record)} class="text-parchment-dim text-xs">
            {gettext("No dietary-history record yet.")}
          </p>
        </div>
        <.action variant={:secondary} size={:sm} phx-click="new_visit">
          {gettext("+ New visit")}
        </.action>
      </div>

      <%= if Enum.empty?(@visits) do %>
        <p class="text-parchment-dim text-sm">{gettext("No visits recorded yet.")}</p>
      <% else %>
        <div class="space-y-2 max-h-96 overflow-y-auto overscroll-contain pr-1">
          <.visit_row :for={visit <- @visits} visit={visit} open={visit.id == @newest_id} />
        </div>
      <% end %>
    </.panel_card>
    """
  end

  attr(:visit, :any, required: true)
  attr(:open, :boolean, default: false)

  # Native <details>/<summary> disclosure — keyboard- and screen-reader-accessible
  # for free (replaces the old JS.toggle-on-a-div).
  defp visit_row(assigns) do
    ~H"""
    <details class="group border border-ink-panel2 rounded-lg overflow-hidden" open={@open}>
      <summary class="flex flex-wrap items-center gap-3 px-3 py-2.5 cursor-pointer select-none hover:bg-black/20 list-none">
        <span
          :if={@visit.visit_number}
          class="px-2 py-0.5 rounded-full bg-paprika/20 text-paprika text-xs shrink-0"
        >
          {gettext("Visit %{number}", number: @visit.visit_number)}
        </span>
        <span class="text-parchment text-sm">
          {if @visit.visit_date, do: Calendar.strftime(@visit.visit_date, "%b %d, %Y"), else: "—"}
        </span>
        <span class="px-2 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim text-xs">
          {modality_label(@visit.modality)}
        </span>
        <span :if={@visit.weight_kg} class="text-parchment-dim text-xs">{@visit.weight_kg} kg</span>
        <span
          :if={@visit.appointment_id}
          class="inline-flex items-center gap-1 text-basil text-xs"
          title={gettext("Linked to an appointment")}
        >
          <.icon name="hero-link" class="w-3.5 h-3.5" /> {gettext("Appointment")}
        </span>
        <span
          :if={present?(@visit.body)}
          class="text-parchment-dim text-xs truncate hidden sm:block max-w-[12rem]"
        >
          {@visit.body}
        </span>
        <.icon
          name="hero-chevron-down"
          class="w-4 h-4 text-parchment-dim ml-auto shrink-0 transition-transform group-open:rotate-180"
        />
      </summary>

      <div class="px-3 pb-3 pt-1 border-t border-ink-panel2">
        <%= if present?(@visit.body) do %>
          <p class="text-parchment text-sm whitespace-pre-line mt-2">{@visit.body}</p>
        <% else %>
          <p class="text-parchment-dim text-sm mt-2 italic">{gettext("No notes recorded.")}</p>
        <% end %>
        <div :if={present?(@visit.todo)} class="mt-3 pt-3 border-t border-ink-panel2">
          <p class="text-xs text-parchment-dim mb-1">{gettext("To do")}</p>
          <p class="text-parchment text-sm whitespace-pre-line">{@visit.todo}</p>
        </div>
        <div :if={@visit.appointment} class="mt-3 pt-3 border-t border-ink-panel2">
          <p class="text-xs text-parchment-dim mb-1">{gettext("Linked appointment")}</p>
          <p class="text-parchment text-sm">
            {@visit.appointment.title} — {Calendar.strftime(
              @visit.appointment.scheduled_at,
              "%b %d, %Y"
            )}
          </p>
        </div>
        <div class="flex gap-2 mt-3 pt-3 border-t border-ink-panel2">
          <.action variant={:ghost} size={:sm} phx-click="edit_visit" phx-value-id={@visit.id}>
            <.icon name="hero-pencil-square" class="w-3.5 h-3.5" /> {gettext("Edit")}
          </.action>
          <.action
            variant={:ghost}
            size={:sm}
            phx-click="delete_visit"
            phx-value-id={@visit.id}
            data-confirm={gettext("Delete this visit?")}
            class="text-error-500 hover:text-error-500"
          >
            <.icon name="hero-trash" class="w-3.5 h-3.5" /> {gettext("Delete")}
          </.action>
        </div>
      </div>
    </details>
    """
  end

  # ── Zone 3 (left): new-visit modal ──────────────────────────────────────────────────

  attr(:visit_form, :any, required: true)
  attr(:appointments, :list, default: [])
  attr(:editing, :boolean, default: false)
  attr(:reference_visit, :any, default: nil)

  # The form never covers its own context: the previous visit rides along in a
  # reference pane, and each measurement input carries a "last: X" hint — the
  # delta is the whole point of measuring.
  def visit_form_modal(assigns) do
    ~H"""
    <.modal id="new-visit-modal" show on_cancel={JS.push("cancel_visit")}>
      <h2 class="text-lg font-display font-bold text-parchment mb-4">
        {if @editing, do: gettext("Edit visit"), else: gettext("New visit")}
      </h2>
      <div class={["grid grid-cols-1 gap-5", @reference_visit && "md:grid-cols-[1fr_14rem]"]}>
        <.form
          for={@visit_form}
          id="new-visit-form"
          phx-change="validate_visit"
          phx-submit="save_visit"
          class="space-y-4 min-w-0"
        >
          <div class="grid grid-cols-2 gap-4">
            <.labeled label={gettext("Visit date")}>
              <.input field={@visit_form[:visit_date]} type="date" />
            </.labeled>
            <.labeled label={gettext("Visit #")}>
              <.input field={@visit_form[:visit_number]} type="number" />
            </.labeled>
            <.labeled label={gettext("Modality")}>
              <.input
                field={@visit_form[:modality]}
                type="select"
                options={[
                  {gettext("In person"), "in_person"},
                  {gettext("Phone"), "phone"},
                  {gettext("Online"), "online"}
                ]}
              />
            </.labeled>
            <.labeled label={gettext("Weight (kg)")}>
              <.input field={@visit_form[:weight_kg]} type="number" step="any" />
              <.ref_hint value={@reference_visit && @reference_visit.weight_kg} unit="kg" />
            </.labeled>
            <.labeled label={gettext("Body fat (%)")}>
              <.input field={@visit_form[:body_fat_percentage]} type="number" step="any" />
              <.ref_hint value={@reference_visit && @reference_visit.body_fat_percentage} unit="%" />
            </.labeled>
            <.labeled label={gettext("Waist (cm)")}>
              <.input field={@visit_form[:waist_cm]} type="number" step="any" />
              <.ref_hint value={@reference_visit && @reference_visit.waist_cm} unit="cm" />
            </.labeled>
            <.labeled label={gettext("Muscle mass (kg)")}>
              <.input field={@visit_form[:muscle_mass_kg]} type="number" step="any" />
              <.ref_hint value={@reference_visit && @reference_visit.muscle_mass_kg} unit="kg" />
            </.labeled>
            <.labeled label={gettext("Hands (cm)")}>
              <.input field={@visit_form[:hands_cm]} type="number" step="any" />
              <.ref_hint value={@reference_visit && @reference_visit.hands_cm} unit="cm" />
            </.labeled>
            <.labeled label={gettext("Glutes (cm)")}>
              <.input field={@visit_form[:glutes_cm]} type="number" step="any" />
              <.ref_hint value={@reference_visit && @reference_visit.glutes_cm} unit="cm" />
            </.labeled>
            <.labeled label={gettext("Feet (cm)")}>
              <.input field={@visit_form[:feet_cm]} type="number" step="any" />
              <.ref_hint value={@reference_visit && @reference_visit.feet_cm} unit="cm" />
            </.labeled>
          </div>
          <.labeled :if={@appointments != []} label={gettext("Linked appointment")}>
            <.input
              field={@visit_form[:appointment_id]}
              type="select"
              prompt={gettext("— none —")}
              options={appointment_options(@appointments)}
            />
          </.labeled>
          <.labeled label={gettext("Notes")}>
            <.input field={@visit_form[:body]} type="textarea" />
          </.labeled>
          <.labeled label={gettext("To do")}>
            <.input field={@visit_form[:todo]} type="textarea" />
          </.labeled>
          <div class="flex gap-2 pt-1">
            <.action variant={:primary} size={:sm} type="submit" phx-disable-with={gettext("Saving…")}>
              {if @editing, do: gettext("Save changes"), else: gettext("Save visit")}
            </.action>
            <.action variant={:ghost} size={:sm} type="button" phx-click="cancel_visit">
              {gettext("Cancel")}
            </.action>
          </div>
        </.form>

        <.visit_reference :if={@reference_visit} visit={@reference_visit} />
      </div>
    </.modal>
    """
  end

  attr(:value, :any, default: nil)
  attr(:unit, :string, default: "")

  # "last: 82.4 kg" under a measurement input — the previous reading, so a new
  # value is typed against a reference, not into a void.
  defp ref_hint(assigns) do
    ~H"""
    <span :if={@value} class="block text-[11px] text-parchment-dim mt-0.5 tabular-nums">
      {gettext("last: %{value} %{unit}", value: @value, unit: @unit)}
    </span>
    """
  end

  attr(:visit, :any, required: true)

  # Read-only pane beside the visit form: the previous visit's measurements,
  # note excerpt and agreed to-dos — what the session is checking in on.
  defp visit_reference(assigns) do
    assigns = assign(assigns, :measurements, reference_measurements(assigns.visit))

    ~H"""
    <aside class="bg-ink border border-ink-panel2 rounded-lg p-3 self-start text-sm">
      <p class="text-[11px] uppercase tracking-wide font-semibold text-parchment-dim mb-2">
        {gettext("Last visit")}
        <span :if={@visit.visit_date} class="normal-case font-normal">
          · {Calendar.strftime(@visit.visit_date, "%b %d, %Y")}
        </span>
      </p>

      <dl :if={@measurements != []} class="space-y-1 mb-3">
        <div :for={{label, value, unit} <- @measurements} class="flex justify-between gap-2">
          <dt class="text-parchment-dim text-xs">{label}</dt>
          <dd class="text-parchment text-xs tabular-nums">{value} {unit}</dd>
        </div>
      </dl>

      <p :if={present?(@visit.body)} class="text-parchment-dim text-xs whitespace-pre-line line-clamp-6">
        {@visit.body}
      </p>

      <div :if={present?(@visit.todo)} class="mt-2 pt-2 border-t border-ink-panel2">
        <p class="text-[11px] uppercase tracking-wide font-semibold text-parchment-dim mb-1">
          {gettext("To do")}
        </p>
        <p class="text-parchment text-xs whitespace-pre-line line-clamp-4">{@visit.todo}</p>
      </div>
    </aside>
    """
  end

  defp reference_measurements(visit) do
    [
      {gettext("Weight"), visit.weight_kg, "kg"},
      {gettext("Body fat"), visit.body_fat_percentage, "%"},
      {gettext("Waist"), visit.waist_cm, "cm"},
      {gettext("Muscle mass"), visit.muscle_mass_kg, "kg"},
      {gettext("Hands"), visit.hands_cm, "cm"},
      {gettext("Glutes"), visit.glutes_cm, "cm"},
      {gettext("Feet"), visit.feet_cm, "cm"}
    ]
    |> Enum.filter(fn {_label, value, _unit} -> value end)
  end

  # ── Zone 0: client-details (record PII) modal ───────────────────────────────────────

  attr(:client_form, :any, required: true)

  def client_details_modal(assigns) do
    ~H"""
    <.modal id="client-details-modal" show on_cancel={JS.push("cancel_client_details")}>
      <h2 class="text-lg font-display font-bold text-parchment mb-4">{gettext("Client details")}</h2>
      <.form
        for={@client_form}
        id="client-details-form"
        phx-change="validate_client_details"
        phx-submit="save_client_details"
        class="space-y-4"
      >
        <.labeled label={gettext("Full name")}>
          <.input field={@client_form[:full_name]} type="text" />
        </.labeled>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.labeled label={gettext("Date of birth")}>
            <.input field={@client_form[:date_of_birth]} type="date" />
          </.labeled>
          <.labeled label={gettext("Email")}>
            <.input field={@client_form[:email]} type="text" />
          </.labeled>
          <.labeled label={gettext("Phone")}>
            <.input field={@client_form[:phone]} type="text" />
          </.labeled>
          <.labeled label={gettext("Postal code")}>
            <.input field={@client_form[:postal_code]} type="text" />
          </.labeled>
        </div>
        <.labeled label={gettext("Address")}>
          <.input field={@client_form[:address]} type="text" />
        </.labeled>
        <.labeled label={gettext("Work / schedule")}>
          <.input field={@client_form[:work_schedule]} type="text" />
        </.labeled>
        <div class="flex gap-2 pt-1">
          <.action variant={:primary} size={:sm} type="submit" phx-disable-with={gettext("Saving…")}>
            {gettext("Save details")}
          </.action>
          <.action variant={:ghost} size={:sm} type="button" phx-click="cancel_client_details">
            {gettext("Cancel")}
          </.action>
        </div>
      </.form>
    </.modal>
    """
  end

  # ── Zone 3 (left): onboarding answers (read-only reference, collapsed) ────────────────

  attr(:onboarding_answers, :list, default: [])
  attr(:onboarding_locale, :string, default: "en")

  def onboarding_answers_panel(assigns) do
    ~H"""
    <.panel_card :if={@onboarding_answers != []} class="mb-6">
      <details class="group">
        <summary class="flex items-center gap-2 cursor-pointer select-none list-none">
          <.icon
            name="hero-chevron-right"
            class="w-4 h-4 text-parchment-dim transition-transform group-open:rotate-90"
          />
          <h2 class="font-display text-base font-semibold text-parchment">
            {gettext("Onboarding answers")}
          </h2>
        </summary>
        <dl class="space-y-3 mt-4">
          <div :for={{q, a} <- @onboarding_answers}>
            <dt class="text-xs font-semibold uppercase tracking-wide text-parchment-dim">
              {onboarding_prompt(q, a, @onboarding_locale)}
            </dt>
            <dd class="text-parchment text-sm mt-0.5">
              {onboarding_answer_text(q, a, @onboarding_locale)}
            </dd>
          </div>
        </dl>
      </details>
    </.panel_card>
    """
  end

  # ── Zone 3 (right): messages ─────────────────────────────────────────────────────────

  attr(:messages, :list, required: true)
  attr(:current_user_id, :integer, required: true)
  attr(:message_body, :string, default: "")
  attr(:client_name, :string, default: nil)
  attr(:unread_count, :integer, default: 0)

  # Opening this tab is the read receipt (handled server-side in
  # `handle_params`), so the thread is never marked read just by loading the
  # client file on another tab.
  def messages_panel(assigns) do
    ~H"""
    <.panel_card class="mb-6">
      <div class="flex items-center gap-2 mb-3">
        <h2 class="font-display text-base font-semibold text-parchment inline-flex items-center gap-2">
          <.icon name="hero-chat-bubble-left-right" class="w-4 h-4 text-basil" />
          {gettext("Messages with %{name}", name: @client_name)}
        </h2>
        <span
          :if={@unread_count > 0}
          class="px-2 py-0.5 rounded-full bg-paprika/15 text-paprika-soft text-xs font-semibold tabular-nums"
        >
          {gettext("%{count} new", count: @unread_count)}
        </span>
      </div>
      <.message_thread
        messages={@messages}
        current_user_id={@current_user_id}
        body={@message_body}
        height_class="max-h-[32rem]"
        placeholder={gettext("Message your client…")}
      />
    </.panel_card>
    """
  end

  # ── Zone 3 (right): AI meal-plan assistant ───────────────────────────────────────────

  attr(:ai_running, :boolean, default: false)
  attr(:ai_steps, :list, default: [])
  attr(:ai_result, :any, default: nil)
  attr(:ai_error, :any, default: nil)
  attr(:ai_preferences, :string, default: "")
  attr(:client_id, :any, required: true)

  def ai_assist_panel(assigns) do
    assigns = assign(assigns, :state, ai_state(assigns))

    ~H"""
    <.panel_card class="mb-6">
      <div class="flex items-center justify-between mb-3">
        <h2 class="font-display text-base font-semibold text-parchment inline-flex items-center gap-2">
          <.icon name="hero-sparkles" class="w-4 h-4 text-basil" />
          {gettext("AI Meal Plan Assistant")}
        </h2>
        <button
          :if={@state in [:done, :error]}
          phx-click="ai_dismiss"
          class="text-parchment-dim hover:text-parchment text-xs"
        >
          {gettext("Dismiss")}
        </button>
      </div>

      <!-- Idle: the prompt form -->
      <.form
        :if={@state == :idle}
        for={%{}}
        id="ai-assist-form"
        phx-submit="ai_assist"
        class="flex gap-2"
      >
        <input
          type="text"
          name="preferences"
          value={@ai_preferences}
          placeholder={gettext("Dietary notes for this client, e.g. 'low-carb, avoid shellfish'")}
          class="flex-1 bg-ink-panel2 border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm placeholder-parchment-dim focus:outline-none focus:border-paprika"
        />
        <.action variant={:secondary} size={:sm} type="submit" class="whitespace-nowrap">
          {gettext("Draft 7-day Plan")}
        </.action>
      </.form>

      <!-- Running / streamed steps -->
      <div :if={@ai_running or @ai_steps != []} class="space-y-1.5 mt-2" aria-live="polite">
        <div :for={{step, idx} <- Enum.with_index(@ai_steps)} class="flex items-center gap-2">
          <%= if idx == length(@ai_steps) - 1 and @ai_running do %>
            <span class="w-2 h-2 rounded-full bg-basil animate-pulse shrink-0"></span>
          <% else %>
            <.icon name="hero-check" class="w-3.5 h-3.5 text-basil shrink-0" />
          <% end %>
          <span class={[
            "text-sm",
            if(idx == length(@ai_steps) - 1 and @ai_running,
              do: "text-parchment",
              else: "text-parchment-dim"
            )
          ]}>
            {step}
          </span>
        </div>
      </div>

      <!-- Done -->
      <div :if={@state == :done} class="mt-3 p-3 bg-basil/10 border border-basil/30 rounded-lg">
        <p class="text-basil text-sm whitespace-pre-wrap">{@ai_result}</p>
      </div>
      <div :if={@state == :done} class="mt-3 flex gap-2">
        <.action variant={:secondary} size={:sm} href={"/nutritionist/clients/#{@client_id}/calendar"}>
          {gettext("View Plan →")}
        </.action>
        <.action variant={:ghost} size={:sm} phx-click="ai_dismiss">
          {gettext("Draft Another")}
        </.action>
      </div>

      <!-- Error -->
      <div
        :if={@state == :error}
        class="mt-3 p-3 bg-error-500/15 border border-error-500/40 rounded-lg"
      >
        <p class="text-error-500 text-sm">{@ai_error}</p>
      </div>
      <.action :if={@state == :error} variant={:ghost} size={:sm} phx-click="ai_dismiss" class="mt-2">
        {gettext("Try again")}
      </.action>
    </.panel_card>
    """
  end

  # ── Zone 3 (right): assign a saved plan ──────────────────────────────────────────────

  attr(:plan_options, :list, default: [])
  attr(:assign_plan_form, :any, required: true)
  attr(:client_name, :string, default: nil)
  attr(:assign_confirm_msg, :string, default: nil)
  attr(:plan_preview, :any, default: nil)

  def assign_plan_panel(assigns) do
    ~H"""
    <.panel_card class="mb-6">
      <h2 class="font-display text-base font-semibold text-parchment inline-flex items-center gap-2 mb-3">
        <.icon name="hero-clipboard-document-check" class="w-4 h-4 text-basil" />
        {gettext("Assign a saved plan")}
      </h2>

      <%= if @plan_options == [] do %>
        <p class="text-parchment-dim text-sm">
          {gettext("You have no completed plans yet.")}
          <.link navigate={~p"/nutritionist/blueprints"} class="text-basil hover:underline">
            {gettext("Build one in Meal Blueprints →")}
          </.link>
        </p>
      <% else %>
        <p class="text-parchment-dim text-sm mb-3">
          {gettext(
            "Lay one of your plans onto %{name}'s calendar. The plan's 7 days start from the chosen date —",
            name: @client_name
          )}
          <span class="text-paprika-soft">{gettext("any meals already on that week are replaced.")}</span>
        </p>
        <.form
          for={@assign_plan_form}
          id="assign-plan-form"
          phx-change="preview_assign"
          phx-submit="assign_plan"
          class="flex flex-wrap items-end gap-3"
        >
          <div class="flex-1 min-w-[12rem]">
            <label class="block text-sm text-parchment-dim mb-1">{gettext("Plan")}</label>
            <.input
              field={@assign_plan_form[:plan_id]}
              type="select"
              prompt={gettext("Choose a plan…")}
              options={@plan_options}
            />
          </div>
          <div>
            <label class="block text-sm text-parchment-dim mb-1">{gettext("Start date")}</label>
            <.input field={@assign_plan_form[:start_date]} type="date" />
          </div>
          <.action
            variant={:secondary}
            size={:sm}
            type="submit"
            phx-disable-with={gettext("Adding…")}
            data-confirm={@assign_confirm_msg}
          >
            {gettext("Add to calendar")}
          </.action>
        </.form>

        <!-- What this plan lays down — shown before the replace, not after -->
        <div :if={@plan_preview} class="mt-4 pt-4 border-t border-ink-panel2">
          <p class="text-[11px] uppercase tracking-wide font-semibold text-parchment-dim mb-2">
            {gettext("This plan lays down")}
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3">
            <div :for={day <- @plan_preview}>
              <p class="text-xs font-semibold text-parchment mb-1">
                {gettext("Day %{n}", n: day.day)}
              </p>
              <ul class="space-y-0.5">
                <li :for={item <- day.items} class="text-xs text-parchment-dim flex gap-1.5">
                  <span class="text-paprika-soft shrink-0">
                    {MehungryWeb.MealTypeLabels.label(item.meal_type)}
                  </span>
                  <span class="text-parchment truncate">{item.title}</span>
                </li>
              </ul>
            </div>
          </div>
        </div>
      <% end %>
    </.panel_card>
    """
  end


  # ── Zone 4: history (appointments / ratings / plans) ──────────────────────────────────

  attr(:appointments, :list, required: true)
  attr(:noted_appointment_ids, :any, required: true)

  def appointment_history(assigns) do
    ~H"""
    <.panel_card>
      <h2 class="font-display text-base font-semibold text-parchment mb-4">
        {gettext("Appointment History")}
      </h2>
      <%= if Enum.empty?(@appointments) do %>
        <p class="text-parchment-dim text-sm">{gettext("No appointments yet.")}</p>
      <% else %>
        <div class="space-y-3 max-h-64 overflow-y-auto overscroll-contain">
          <div :for={appt <- @appointments} class="border-b border-ink-panel2 pb-3 last:border-0">
            <div class="flex items-start justify-between">
              <p class="text-parchment text-sm font-medium">{appt.title}</p>
              <span class="text-parchment-dim text-xs shrink-0 ml-2">
                {Calendar.strftime(appt.scheduled_at, "%b %d, %Y")}
              </span>
            </div>
            <p :if={appt.notes} class="text-parchment-dim text-xs mt-1">{appt.notes}</p>
            <span
              :if={MapSet.member?(@noted_appointment_ids, appt.id)}
              class="inline-flex items-center gap-1 mt-1.5 px-2 py-0.5 rounded-full bg-basil/15 text-basil text-xs"
            >
              <.icon name="hero-check" class="w-3 h-3" /> {gettext("Visit note recorded")}
            </span>
          </div>
        </div>
      <% end %>
    </.panel_card>
    """
  end

  attr(:ratings, :list, required: true)

  def ratings_panel(assigns) do
    ~H"""
    <.panel_card>
      <h2 class="font-display text-base font-semibold text-parchment mb-4">
        {gettext("Meal Plan Ratings")}
      </h2>
      <%= if Enum.empty?(@ratings) do %>
        <p class="text-parchment-dim text-sm">{gettext("No ratings submitted yet.")}</p>
      <% else %>
        <div class="space-y-3 max-h-64 overflow-y-auto overscroll-contain">
          <div :for={rating <- @ratings} class="border-b border-ink-panel2 pb-3 last:border-0">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-1">
                <.rating_stars score={rating.score} />
                <span class={[
                  "text-xs px-2 py-0.5 rounded-full ml-1",
                  rating.rating_type == "daily" && "bg-basil/15 text-basil",
                  rating.rating_type == "weekly" && "bg-paprika/15 text-paprika-soft"
                ]}>
                  {String.capitalize(rating.rating_type)}
                </span>
              </div>
              <span class="text-parchment-dim text-xs">
                {Calendar.strftime(rating.inserted_at, "%b %d")}
              </span>
            </div>
            <p :if={rating.comment} class="text-parchment-dim text-xs mt-1 italic">
              "{rating.comment}"
            </p>
          </div>
        </div>
      <% end %>
    </.panel_card>
    """
  end

  attr(:score, :integer, required: true)

  defp rating_stars(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1" aria-label={gettext("%{score} of 5", score: @score)}>
      <.icon
        :for={i <- 1..5}
        name="hero-star-solid"
        aria-hidden="true"
        class={"w-4 h-4 " <> if(i <= @score, do: "text-warning-500", else: "text-ink-panel2")}
      />
    </span>
    """
  end

  attr(:meal_plans, :list, required: true)

  def meal_plan_history(assigns) do
    ~H"""
    <.panel_card class="mt-6">
      <h2 class="font-display text-base font-semibold text-parchment mb-4">
        {gettext("Meal Plan History")}
      </h2>
      <%= if Enum.empty?(@meal_plans) do %>
        <p class="text-parchment-dim text-sm">{gettext("No meal plans yet.")}</p>
      <% else %>
        <div class="space-y-2">
          <div
            :for={plan <- @meal_plans}
            class="flex items-center justify-between py-2 border-b border-ink-panel2 last:border-0"
          >
            <div>
              <p class="text-parchment text-sm">{plan.title}</p>
              <p class="text-parchment-dim text-xs">{plan.description}</p>
            </div>
            <span class="text-parchment-dim text-xs">
              {Calendar.strftime(plan.inserted_at, "%b %d, %Y")}
            </span>
          </div>
        </div>
      <% end %>
    </.panel_card>
    """
  end

  attr(:label, :string, required: true)
  slot(:inner_block, required: true)

  # The control is nested inside the <label> so it's programmatically labelled
  # (screen readers / click-to-focus) without threading ids through call sites.
  def labeled(assigns) do
    ~H"""
    <label class="block">
      <span class="block text-sm text-parchment-dim mb-1">{@label}</span>
      {render_slot(@inner_block)}
    </label>
    """
  end

  # ── presentation-only helpers (moved out of the LiveView) ─────────────────────────────

  def present?(val), do: is_binary(val) and String.trim(val) != ""

  def modality_label("phone"), do: gettext("Phone")
  def modality_label("online"), do: gettext("Online")
  def modality_label(_), do: gettext("In person")

  defp detail_value(%{details: details}, key) when is_map(details), do: Map.get(details, key)
  defp detail_value(_, _), do: nil

  defp recall_value(%{details: details}, key) when is_map(details) do
    case Map.get(details, "recall_24h") do
      recall when is_map(recall) -> Map.get(recall, key)
      _ -> nil
    end
  end

  defp recall_value(_, _), do: nil

  defp appointment_options(appointments) do
    for a <- appointments do
      {"#{Calendar.strftime(a.scheduled_at, "%b %d, %Y")} — #{a.title}", a.id}
    end
  end

  defp onboarding_prompt(nil, a, _locale), do: a.prompt_snapshot || "—"
  defp onboarding_prompt(q, _a, locale), do: Mehungry.Onboarding.Question.prompt(q, locale)

  defp onboarding_answer_text(q, a, locale) do
    cond do
      a.value_text not in [nil, ""] -> a.value_text
      a.selected_options not in [nil, []] -> option_labels(q, a.selected_options, locale)
      true -> "—"
    end
  end

  defp option_labels(nil, keys, _locale), do: Enum.join(keys, ", ")

  defp option_labels(q, keys, locale) do
    q.options
    |> Enum.filter(&(&1.key in keys))
    |> Enum.map(&Mehungry.Onboarding.QuestionOption.label(&1, locale))
    |> case do
      [] -> Enum.join(keys, ", ")
      labels -> Enum.join(labels, ", ")
    end
  end

  # ── tiny presentation utilities ───────────────────────────────────────────────────────

  defp tone_text(:good), do: "text-basil"
  defp tone_text(:bad), do: "text-error-500"
  defp tone_text(_), do: "text-parchment-dim"

  # Precedence error > done > running > idle, so the three AI flags can never
  # render a contradictory combination.
  defp ai_state(%{ai_error: e}) when not is_nil(e), do: :error
  defp ai_state(%{ai_result: r}) when not is_nil(r), do: :done
  defp ai_state(%{ai_running: true}), do: :running
  defp ai_state(_), do: :idle

  # A value's standing against a `{low, high}` healthy band: :good inside, :warn
  # outside, nil when either the value or the band is unknown.
  defp band_tone(value, {lo, hi}) when is_number(value) and is_number(lo) and is_number(hi) do
    if value >= lo and value <= hi, do: :good, else: :warn
  end

  defp band_tone(_value, _band), do: nil

  defp band_label(:good), do: gettext("within healthy range")
  defp band_label(:warn), do: gettext("outside healthy range")
  defp band_label(_), do: nil

  defp newest_visit_id([]), do: nil

  defp newest_visit_id(visits) do
    visits
    |> Enum.max_by(&(&1.visit_date || ~D[0001-01-01]), Date, fn -> nil end)
    |> case do
      nil -> nil
      v -> v.id
    end
  end
end
