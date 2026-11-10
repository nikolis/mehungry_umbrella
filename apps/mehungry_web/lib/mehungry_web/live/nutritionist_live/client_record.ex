defmodule MehungryWeb.NutritionistLive.ClientRecord do
  @moduledoc """
  Shows a single `ProfessionalClient` record: the latest intake assessment
  (typed anthropometrics + free-text questionnaire + 24h recall) and the
  chronological consultation-note timeline.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Professionals
  alias MehungryWeb.AnthropometricLabels
  alias Mehungry.Professionals.DietaryHistory.Fields
  alias MehungryWeb.DietaryHistory.Labels
  alias MehungryWeb.NutritionistLive.ClientDetailComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    professional_id = socket.assigns.current_user.id

    case fetch_record(professional_id, id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Record not found."))
         |> push_navigate(to: ~p"/nutritionist/clients")}

      record ->
        client_id = record.id

        {:ok,
         socket
         |> assign(:record, record)
         |> assign(:conditions, Professionals.list_client_conditions(client_id))
         |> assign(:intake, Professionals.get_latest_intake(client_id))
         |> assign(:notes, Professionals.list_consultation_notes(client_id))
         |> assign(:page_title, gettext("Record: %{name}", name: record.full_name))}
    end
  end

  defp fetch_record(professional_id, id) do
    Professionals.get_client_record!(professional_id, id)
  rescue
    Ecto.NoResultsError -> nil
    Ecto.Query.CastError -> nil
  end

  # ── Render ──────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns, :detail_groups, ClientDetailComponents.detail_field_groups())
      |> assign(:recall_labels, Fields.recall_labels())

    ~H"""
    <%!-- Print only the record itself, regardless of the surrounding app chrome.
          The chrome is collapsed with display:none (so it reserves no space) and
          the record subtree is kept in NORMAL FLOW — no position:absolute, which
          clips long multi-page records in some print engines. `break-inside` keeps
          each section/visit from splitting across a page. --%>
    <style>
      @media print {
        @page { margin: 1.5cm; }
        .mobile_header, nav, [role="alert"], #printable .no-print { display: none !important; }
        body * { visibility: hidden; }
        #printable, #printable * { visibility: visible; }
        #printable { color: #000; }
        #printable section, #printable li { break-inside: avoid; }
      }
    </style>
    <div id="printable" class="max-w-4xl mx-auto">
      <div class="flex items-center justify-between no-print">
        <.link
          navigate={~p"/nutritionist/clients"}
          class="text-parchment-dim hover:text-parchment text-sm"
        >
          {gettext("← Back to clients")}
        </.link>
        <div class="flex items-center gap-2">
          <.action variant={:secondary} size={:sm} onclick="window.print()">
            <.icon name="hero-printer" class="w-4 h-4" /> {gettext("Print / Save as PDF")}
          </.action>
          <.action
            variant={:primary}
            size={:sm}
            navigate={~p"/nutritionist/clients/#{@record.user_id}"}
          >
            {gettext("Edit on client overview")}
          </.action>
        </div>
      </div>

      <div class="flex items-center gap-2 mt-2 mb-1">
        <h1 class="text-2xl font-display font-bold text-parchment">{@record.full_name}</h1>
        <span class="px-2 py-0.5 rounded-full bg-basil/20 text-basil text-xs">{gettext(
          "m3hungry client"
        )}</span>
      </div>
      <p class="text-parchment-dim text-sm mb-6">
        {[@record.email, @record.phone, @record.address]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join(" · ")}
      </p>

      <%= unless Enum.empty?(@conditions) do %>
        <section class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mb-6">
          <h2 class="text-lg font-display font-bold text-parchment mb-3">
            {gettext("Health conditions")}
          </h2>
          <div class="flex flex-wrap gap-2">
            <%= for condition <- @conditions do %>
              <span class="px-3 py-1 rounded-full bg-paprika/20 text-paprika text-sm">
                {condition.name}
              </span>
            <% end %>
          </div>
        </section>
      <% end %>

      <%= if @intake do %>
        <section class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mb-6">
          <h2 class="text-lg font-display font-bold text-parchment mb-3">
            {gettext("Intake")}
            <%= if @intake.assessed_on do %>
              <span class="text-parchment-dim text-sm font-normal">
                · {Calendar.strftime(@intake.assessed_on, "%b %d, %Y")}
              </span>
            <% end %>
          </h2>

          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
            <.metric
              label={gettext("Sex")}
              value={AnthropometricLabels.sex_label(@intake.sex)}
              unit=""
            />
            <.metric label={gettext("Age")} value={@intake.age} unit={gettext("yrs")} />
            <.metric
              label={gettext("Activity")}
              value={AnthropometricLabels.activity_label(@intake.activity_level)}
              unit=""
            />
            <.metric label={gettext("Height")} value={@intake.height_m} unit="m" />
            <.metric label={gettext("Weight")} value={@intake.weight_kg} unit="kg" />
            <.metric label={gettext("BMI")} value={@intake.bmi} unit="" />
            <.metric label={gettext("Ideal wt")} value={@intake.ideal_weight_kg} unit="kg" />
            <.metric label={gettext("Usual wt")} value={@intake.usual_weight_kg} unit="kg" />
            <.metric label={gettext("Adjusted wt")} value={@intake.adjusted_weight_kg} unit="kg" />
            <.metric label={gettext("BMR")} value={@intake.bmr_kcal} unit="kcal" />
            <.metric label={gettext("TDEE")} value={@intake.tdee_kcal} unit="kcal" />
          </div>

          <%= if @intake.goal do %>
            <p class="text-sm text-parchment mb-4">
              <span class="text-parchment-dim">{gettext("Goal:")}</span> {@intake.goal}
            </p>
          <% end %>

          <%= for {group, fields} <- @detail_groups,
                  items = filled_items(fields, @intake.details),
                  items != [] do %>
            <h3 class="text-sm font-semibold text-parchment mt-5 mb-2">
              {ClientDetailComponents.section_title(group)}
            </h3>
            <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2 text-sm">
              <%= for {label, val} <- items do %>
                <div>
                  <dt class="text-parchment-dim text-xs">{Labels.translate(label)}</dt>
                  <dd class="text-parchment whitespace-pre-line">{val}</dd>
                </div>
              <% end %>
            </dl>
          <% end %>

          <%= if recall = @intake.details["recall_24h"] do %>
            <h3 class="text-sm font-semibold text-parchment mt-5 mb-2">
              {gettext("24-hour recall")}
            </h3>
            <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2 text-sm">
              <%= for {key, label} <- @recall_labels, val = recall[key], present?(val) do %>
                <div>
                  <dt class="text-parchment-dim text-xs">{Labels.translate(label)}</dt>
                  <dd class="text-parchment">{val}</dd>
                </div>
              <% end %>
            </dl>
          <% end %>
        </section>
      <% end %>

      <section>
        <h2 class="text-lg font-display font-bold text-parchment mb-3">
          {gettext("Consultation notes (%{count})", count: length(@notes))}
        </h2>

        <%= if Enum.empty?(@notes) do %>
          <p class="text-parchment-dim text-sm">{gettext("No consultation notes.")}</p>
        <% else %>
          <ol class="space-y-4">
            <%= for note <- @notes do %>
              <li class="bg-ink-panel border border-ink-panel2 rounded-xl p-4">
                <div class="flex items-center gap-2 mb-2 text-sm">
                  <%= if note.visit_number do %>
                    <span class="px-2 py-0.5 rounded-full bg-paprika/20 text-paprika text-xs">
                      {gettext("Visit %{number}", number: note.visit_number)}
                    </span>
                  <% end %>
                  <span class="text-parchment-dim">
                    {if note.visit_date,
                      do: Calendar.strftime(note.visit_date, "%b %d, %Y"),
                      else: "—"}
                  </span>
                  <span class="px-2 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim text-xs">
                    {modality_label(note.modality)}
                  </span>
                </div>
                <%= if note.body do %>
                  <p class="text-parchment text-sm whitespace-pre-line">{note.body}</p>
                <% end %>
                <%= if note.todo do %>
                  <div class="mt-3 pt-3 border-t border-ink-panel2">
                    <p class="text-xs text-parchment-dim mb-1">{gettext("To do")}</p>
                    <p class="text-parchment text-sm whitespace-pre-line">{note.todo}</p>
                  </div>
                <% end %>
              </li>
            <% end %>
          </ol>
        <% end %>
      </section>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :unit, :string, default: ""

  defp metric(assigns) do
    ~H"""
    <div class="bg-ink rounded-lg p-2 text-center">
      <p class="text-parchment-dim text-xs">{@label}</p>
      <p class="text-parchment font-semibold text-sm">
        {if is_nil(@value), do: "—", else: "#{@value} #{@unit}"}
      </p>
    </div>
    """
  end

  defp present?(val), do: is_binary(val) and String.trim(val) != ""

  defp filled_items(fields, details) when is_map(details) do
    for {key, label} <- fields, val = details[key], present?(val), do: {label, val}
  end

  defp filled_items(_fields, _details), do: []

  defp modality_label("phone"), do: gettext("Phone")
  defp modality_label("online"), do: gettext("Online")
  defp modality_label(_), do: gettext("In person")
end
