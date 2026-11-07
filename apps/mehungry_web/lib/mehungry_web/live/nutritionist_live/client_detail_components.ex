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
  alias Mehungry.Professionals.Anthropometrics
  alias Mehungry.Professionals.DietaryHistory.Fields
  alias MehungryWeb.DietaryHistory.Labels
  alias MehungryWeb.MeasurementChart

  # ── Zone 0: header ──────────────────────────────────────────────────────────────

  attr :client, :any, required: true
  attr :client_id, :any, required: true

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

      <div class="ml-auto flex flex-wrap gap-2">
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
        <.action variant={:secondary} size={:sm} phx-click="open_full_record">
          {gettext("Open full record")}
        </.action>
      </div>
    </div>
    """
  end

  # ── Zone 1: at-a-glance summary strip ─────────────────────────────────────────────

  attr :summary, :map, required: true

  def client_summary(assigns) do
    ~H"""
    <div class="grid grid-cols-2 sm:grid-cols-4 gap-2.5 mb-6">
      <!-- Goal -->
      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-3 flex flex-col gap-0.5">
        <span class="text-[11px] uppercase tracking-wide font-semibold text-parchment-dim inline-flex items-center gap-1">
          <.icon name="hero-flag" class="w-3 h-3 text-paprika" /> {gettext("Goal")}
        </span>
        <%= if present?(@summary.goal) do %>
          <span class="text-parchment text-sm font-medium leading-snug line-clamp-2">
            {@summary.goal}
          </span>
        <% else %>
          <.action variant={:ghost} size={:sm} phx-click="edit_intake" class="self-start px-0 mt-0.5">
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
              {gettext("/ goal %{w} kg", w: @summary.ideal_weight_kg)}
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
              :if={band_tone(@summary.bmi, @summary.bmi_band)}
              class={[
                "w-2 h-2 rounded-full",
                band_tone(@summary.bmi, @summary.bmi_band) == :good && "bg-basil",
                band_tone(@summary.bmi, @summary.bmi_band) == :warn && "bg-warning-500"
              ]}
              title={band_label(band_tone(@summary.bmi, @summary.bmi_band))}
            ></span>
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
            {Calendar.strftime(@summary.last_visit.visit_date, "%b %d, %Y")}
          </span>
          <span class="text-parchment-dim text-xs">{modality_label(@summary.last_visit.modality)}</span>
        <% else %>
          <span class="text-parchment-dim text-sm">{gettext("No visits yet")}</span>
        <% end %>
      </div>
    </div>
    """
  end

  # ── Zone 2: progress ──────────────────────────────────────────────────────────────

  attr :progress_cards, :list, required: true
  attr :selected_metric, :string, default: nil
  attr :progress_chart_svg, :any, default: nil
  attr :progress_legend, :list, default: []

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
            "Not enough data yet — recorded measurements (weight, body fat, waist, muscle mass) will chart here once there are at least two readings."
          )}
        </p>
      <% end %>
    </.panel_card>
    """
  end

  # ── Zone 2b: the client's own shared self-tracking journal (read-only) ──────────────

  attr :shared_journal, :any, default: nil
  attr :shared_cards, :list, default: []
  attr :shared_selected, :string, default: nil
  attr :shared_chart_svg, :any, default: nil
  attr :shared_legend, :list, default: []

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

  attr :record, :any, default: nil
  attr :intake, :any, default: nil
  attr :intake_editing?, :boolean, default: false
  attr :intake_form, :any, default: nil
  attr :conditions, :list, default: []
  attr :all_conditions, :list, default: []
  attr :measurement_context, :map, default: %{}

  def intake_panel(assigns) do
    ~H"""
    <.panel_card class="mb-6">
      <div class="flex items-center justify-between mb-4">
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
            {gettext("Open full record →")}
          </.link>
        </div>
        <.action :if={not @intake_editing?} variant={:secondary} size={:sm} phx-click="edit_intake">
          {if @intake, do: gettext("Edit"), else: gettext("Add dietary history")}
        </.action>
      </div>

      <%= cond do %>
        <% @intake_editing? -> %>
          {intake_form(assigns)}
        <% @intake -> %>
          {intake_display(assigns)}
        <% true -> %>
          <p class="text-parchment-dim text-sm mb-2">{gettext("No dietary history recorded yet.")}</p>
          {conditions_panel(assigns)}
      <% end %>
    </.panel_card>
    """
  end

  defp intake_display(assigns) do
    assigns =
      assigns
      |> assign(
        :bmi_tone,
        band_tone(assigns.intake.bmi, MeasurementChart.band(assigns.measurement_context, "bmi"))
      )
      |> assign(
        :weight_tone,
        band_tone(
          assigns.intake.weight_kg,
          MeasurementChart.band(assigns.measurement_context, "weight_kg")
        )
      )

    ~H"""
    <div>
      <p :if={@intake.assessed_on} class="text-parchment-dim text-xs mb-3">
        {gettext("Assessed %{date}", date: Calendar.strftime(@intake.assessed_on, "%b %d, %Y"))}
      </p>

      <!-- Clinical numbers the nutritionist acts on -->
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-2.5 mb-3">
        <.clinical_metric label={gettext("BMI")} value={@intake.bmi} unit="" dot={@bmi_tone} />
        <.clinical_metric label={gettext("TDEE")} value={@intake.tdee_kcal} unit="kcal" />
        <.clinical_metric label={gettext("BMR")} value={@intake.bmr_kcal} unit="kcal" />
        <.clinical_metric
          label={gettext("Weight")}
          value={@intake.weight_kg}
          unit="kg"
          dot={@weight_tone}
        />
      </div>

      <!-- Reference values -->
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-2 mb-4">
        <.metric label={gettext("Sex")} value={Anthropometrics.sex_label(@intake.sex)} unit="" />
        <.metric label={gettext("Age")} value={@intake.age} unit="yrs" />
        <.metric
          label={gettext("Activity")}
          value={Anthropometrics.activity_label(@intake.activity_level)}
          unit=""
        />
        <.metric label={gettext("Height")} value={@intake.height_m} unit="m" />
        <.metric label={gettext("Ideal wt")} value={@intake.ideal_weight_kg} unit="kg" />
        <.metric label={gettext("Usual wt")} value={@intake.usual_weight_kg} unit="kg" />
        <.metric label={gettext("Adjusted wt")} value={@intake.adjusted_weight_kg} unit="kg" />
      </div>

      {conditions_panel(assigns)}

      <p :if={present?(@intake.goal)} class="text-sm text-parchment mb-4">
        <span class="text-parchment-dim">{gettext("Goal:")}</span> {@intake.goal}
      </p>

      <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2 text-sm">
        <%= for {key, label} <- Fields.detail_labels(), val = @intake.details[key], present?(val) do %>
          <div>
            <dt class="text-parchment-dim text-xs">{Labels.translate(label)}</dt>
            <dd class="text-parchment whitespace-pre-line">{val}</dd>
          </div>
        <% end %>
      </dl>

      <%= if recall = @intake.details["recall_24h"] do %>
        <h3 class="text-sm font-semibold text-parchment mt-5 mb-2">{gettext("24-hour recall")}</h3>
        <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2 text-sm">
          <%= for {key, label} <- Fields.recall_labels(), val = recall[key], present?(val) do %>
            <div>
              <dt class="text-parchment-dim text-xs">{Labels.translate(label)}</dt>
              <dd class="text-parchment whitespace-pre-line">{val}</dd>
            </div>
          <% end %>
        </dl>
      <% end %>
    </div>
    """
  end

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
            options={for {v, l} <- Anthropometrics.sexes(), do: {l, v}}
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
            options={for {v, l, _f} <- Anthropometrics.activity_levels(), do: {l, v}}
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

      <h3 class="text-sm font-semibold text-parchment mt-5 mb-2">{gettext("Questionnaire")}</h3>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3">
        <%= for {key, label} <- Fields.detail_labels() do %>
          <.labeled label={Labels.translate(label)}>
            <textarea
              name={"intake[details][#{key}]"}
              rows="2"
              class="w-full bg-ink border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm"
            >{detail_value(@intake, key)}</textarea>
          </.labeled>
        <% end %>
      </div>

      <h3 class="text-sm font-semibold text-parchment mt-5 mb-2">{gettext("24-hour recall")}</h3>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3">
        <%= for {key, label} <- Fields.recall_labels() do %>
          <.labeled label={Labels.translate(label)}>
            <input
              type="text"
              name={"intake[details][recall_24h][#{key}]"}
              value={recall_value(@intake, key)}
              class="w-full bg-ink border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm"
            />
          </.labeled>
        <% end %>
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
  defp conditions_panel(assigns) do
    linked_ids = Enum.map(assigns.conditions, & &1.id)

    assigns =
      assign(
        assigns,
        :available_conditions,
        Enum.reject(assigns.all_conditions, &(&1.id in linked_ids))
      )

    ~H"""
    <div class="mt-6 mb-2 pt-5 border-t border-ink-panel2">
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

  attr :visits, :list, required: true
  attr :record, :any, default: nil

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
            {gettext("View full dietary history →")}
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

  attr :visit, :any, required: true
  attr :open, :boolean, default: false

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
      </div>
    </details>
    """
  end

  # ── Zone 3 (left): new-visit modal ──────────────────────────────────────────────────

  attr :visit_form, :any, required: true
  attr :appointments, :list, default: []

  def visit_form_modal(assigns) do
    ~H"""
    <.modal id="new-visit-modal" show on_cancel={JS.push("cancel_visit")}>
      <h2 class="text-lg font-display font-bold text-parchment mb-4">{gettext("New visit")}</h2>
      <.form
        for={@visit_form}
        id="new-visit-form"
        phx-change="validate_visit"
        phx-submit="save_visit"
        class="space-y-4"
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
          </.labeled>
          <.labeled label={gettext("Body fat (%)")}>
            <.input field={@visit_form[:body_fat_percentage]} type="number" step="any" />
          </.labeled>
          <.labeled label={gettext("Waist (cm)")}>
            <.input field={@visit_form[:waist_cm]} type="number" step="any" />
          </.labeled>
          <.labeled label={gettext("Muscle mass (kg)")}>
            <.input field={@visit_form[:muscle_mass_kg]} type="number" step="any" />
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
            {gettext("Save visit")}
          </.action>
          <.action variant={:ghost} size={:sm} type="button" phx-click="cancel_visit">
            {gettext("Cancel")}
          </.action>
        </div>
      </.form>
    </.modal>
    """
  end

  # ── Zone 3 (left): onboarding answers (read-only reference, collapsed) ────────────────

  attr :onboarding_answers, :list, default: []
  attr :onboarding_locale, :string, default: "en"

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

  attr :messages, :list, required: true
  attr :current_user_id, :integer, required: true
  attr :message_body, :string, default: ""
  attr :client_name, :string, default: nil

  def messages_panel(assigns) do
    ~H"""
    <.panel_card class="mb-6">
      <h2 class="font-display text-base font-semibold text-parchment inline-flex items-center gap-2 mb-3">
        <.icon name="hero-chat-bubble-left-right" class="w-4 h-4 text-basil" />
        {gettext("Messages with %{name}", name: @client_name)}
      </h2>
      <.message_thread
        messages={@messages}
        current_user_id={@current_user_id}
        body={@message_body}
        height_class="max-h-[28rem]"
        placeholder={gettext("Message your client…")}
      />
    </.panel_card>
    """
  end

  # ── Zone 3 (right): AI meal-plan assistant ───────────────────────────────────────────

  attr :ai_running, :boolean, default: false
  attr :ai_steps, :list, default: []
  attr :ai_result, :any, default: nil
  attr :ai_error, :any, default: nil
  attr :ai_preferences, :string, default: ""
  attr :client_id, :any, required: true

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

  attr :plan_options, :list, default: []
  attr :assign_plan_form, :any, required: true
  attr :client_name, :string, default: nil
  attr :assign_confirm_msg, :string, default: nil

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
      <% end %>
    </.panel_card>
    """
  end

  # ── Zone 4: history (appointments / ratings / plans) ──────────────────────────────────

  attr :appointments, :list, required: true
  attr :noted_appointment_ids, :any, required: true

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

  attr :ratings, :list, required: true

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

  attr :score, :integer, required: true

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

  attr :meal_plans, :list, required: true

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

  # ── small shared metric cards ─────────────────────────────────────────────────────────

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :unit, :string, default: ""

  defp metric(assigns) do
    ~H"""
    <div class="bg-ink rounded-lg p-2 text-center">
      <p class="text-parchment-dim text-xs">{@label}</p>
      <p class="text-parchment font-semibold text-sm tabular-nums">
        {if is_nil(@value), do: "—", else: "#{@value} #{@unit}"}
      </p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :unit, :string, default: ""
  attr :dot, :atom, default: nil

  defp clinical_metric(assigns) do
    ~H"""
    <div class="bg-ink rounded-lg p-3 text-center">
      <p class="text-parchment-dim text-[11px] uppercase tracking-wide font-semibold inline-flex items-center justify-center gap-1.5">
        {@label}
        <span
          :if={@dot}
          class={[
            "w-1.5 h-1.5 rounded-full",
            @dot == :good && "bg-basil",
            @dot == :warn && "bg-warning-500"
          ]}
          title={band_label(@dot)}
        ></span>
      </p>
      <p class="text-parchment font-display text-lg tabular-nums">
        {if is_nil(@value),
          do: "—",
          else:
            raw(
              "#{@value}<span class=\"text-xs text-parchment-dim ml-0.5 font-sans\">#{@unit}</span>"
            )}
      </p>
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  def labeled(assigns) do
    ~H"""
    <div>
      <label class="block text-sm text-parchment-dim mb-1">{@label}</label>
      {render_slot(@inner_block)}
    </div>
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
