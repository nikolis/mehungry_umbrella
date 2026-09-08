defmodule MehungryWeb.NutritionistLive.ClientRecord do
  @moduledoc """
  Shows a single `ProfessionalClient` record: the latest intake assessment
  (typed anthropometrics + free-text questionnaire + 24h recall) and the
  chronological consultation-note timeline.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Professionals
  alias Mehungry.Professionals.DietaryHistory.Fields

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    professional_id = socket.assigns.current_user.id

    case fetch_record(professional_id, id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Record not found.")
         |> push_navigate(to: ~p"/nutritionist/records")}

      record ->
        client_id = record.id

        {:ok,
         socket
         |> assign(:record, record)
         |> assign(:intake, Professionals.get_latest_intake(client_id))
         |> assign(:notes, Professionals.list_consultation_notes(client_id))
         |> assign(:page_title, "Record: #{record.full_name}")}
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
      assign(assigns, :detail_labels, Fields.detail_labels())
      |> assign(:recall_labels, Fields.recall_labels())

    ~H"""
    <div class="max-w-4xl mx-auto">
      <div class="flex items-center justify-between">
        <.link
          navigate={~p"/nutritionist/records"}
          class="text-parchment-dim hover:text-parchment text-sm"
        >
          ← Back to records
        </.link>
        <.link
          navigate={~p"/nutritionist/records/#{@record.id}/edit"}
          class="btn btn-sm bg-paprika hover:bg-paprika-soft text-ink border-0"
        >
          Edit
        </.link>
      </div>

      <div class="flex items-center gap-2 mt-2 mb-1">
        <h1 class="text-2xl font-display font-bold text-parchment">{@record.full_name}</h1>
        <%= if @record.user_id do %>
          <span class="px-2 py-0.5 rounded-full bg-basil/20 text-basil text-xs">m3hungry client</span>
        <% else %>
          <span class="px-2 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim text-xs">External</span>
        <% end %>
      </div>
      <p class="text-parchment-dim text-sm mb-6">
        {[@record.email, @record.phone, @record.address]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join(" · ")}
      </p>

      <%= if @intake do %>
        <section class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mb-6">
          <h2 class="text-lg font-display font-bold text-parchment mb-3">
            Intake
            <%= if @intake.assessed_on do %>
              <span class="text-parchment-dim text-sm font-normal">
                · {Calendar.strftime(@intake.assessed_on, "%b %d, %Y")}
              </span>
            <% end %>
          </h2>

          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
            <.metric label="Height" value={@intake.height_m} unit="m" />
            <.metric label="Weight" value={@intake.weight_kg} unit="kg" />
            <.metric label="BMI" value={@intake.bmi} unit="" />
            <.metric label="Ideal wt" value={@intake.ideal_weight_kg} unit="kg" />
            <.metric label="Usual wt" value={@intake.usual_weight_kg} unit="kg" />
            <.metric label="Adjusted wt" value={@intake.adjusted_weight_kg} unit="kg" />
            <.metric label="BMR" value={@intake.bmr_kcal} unit="kcal" />
            <.metric label="TDEE" value={@intake.tdee_kcal} unit="kcal" />
          </div>

          <%= if @intake.goal do %>
            <p class="text-sm text-parchment mb-4">
              <span class="text-parchment-dim">Goal:</span> {@intake.goal}
            </p>
          <% end %>

          <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2 text-sm">
            <%= for {key, label} <- @detail_labels, val = @intake.details[key], present?(val) do %>
              <div>
                <dt class="text-parchment-dim text-xs">{label}</dt>
                <dd class="text-parchment whitespace-pre-line">{val}</dd>
              </div>
            <% end %>
          </dl>

          <%= if recall = @intake.details["recall_24h"] do %>
            <h3 class="text-sm font-semibold text-parchment mt-5 mb-2">24-hour recall</h3>
            <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2 text-sm">
              <%= for {key, label} <- @recall_labels, val = recall[key], present?(val) do %>
                <div>
                  <dt class="text-parchment-dim text-xs">{label}</dt>
                  <dd class="text-parchment">{val}</dd>
                </div>
              <% end %>
            </dl>
          <% end %>
        </section>
      <% end %>

      <section>
        <h2 class="text-lg font-display font-bold text-parchment mb-3">
          Consultation notes ({length(@notes)})
        </h2>

        <%= if Enum.empty?(@notes) do %>
          <p class="text-parchment-dim text-sm">No consultation notes.</p>
        <% else %>
          <ol class="space-y-4">
            <%= for note <- @notes do %>
              <li class="bg-ink-panel border border-ink-panel2 rounded-xl p-4">
                <div class="flex items-center gap-2 mb-2 text-sm">
                  <%= if note.visit_number do %>
                    <span class="px-2 py-0.5 rounded-full bg-paprika/20 text-paprika text-xs">
                      Visit {note.visit_number}
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
                    <p class="text-xs text-parchment-dim mb-1">To do</p>
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

  defp modality_label("phone"), do: "Phone"
  defp modality_label("online"), do: "Online"
  defp modality_label(_), do: "In person"
end
