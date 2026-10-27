defmodule MehungryWeb.NutritionistLive.ClientRecordEditor do
  @moduledoc """
  Full dietary-history editor for a `ProfessionalClient` record (`:edit` only).

  The record is always reached from a client (the roster / `ClientDetail`), which
  creates it via `ensure_record/1` — so the platform-user association is already
  set and there is no picker here. Persists incrementally (mirroring
  `ArticleEditor`): the client details form, a single `ClientIntake` (typed
  anthropometrics + the free-form questionnaire/24h-recall `details` map), and a
  repeatable list of `ConsultationNote`s.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Professionals
  alias Mehungry.Professionals.{ClientIntake, ConsultationNote}
  alias Mehungry.Professionals.Anthropometrics
  alias Mehungry.Professionals.DietaryHistory.Fields
  alias Mehungry.Health

  @energy_source_fields ~w(height_m weight_kg sex age activity_level)

  # ── Mount ─────────────────────────────────────────────────────────────────────

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    professional_id = socket.assigns.current_user.id

    case fetch_record(professional_id, id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Record not found.")
         |> push_navigate(to: ~p"/nutritionist/clients")}

      record ->
        {:ok, assign_edit(socket, record)}
    end
  end

  defp assign_edit(socket, record) do
    intake =
      Professionals.get_latest_intake(record.id) ||
        %ClientIntake{professional_client_id: record.id}

    socket
    |> assign(:page_title, "Edit: #{record.full_name}")
    |> assign(:record, record)
    |> assign(:client_changeset, Professionals.change_client_record(record))
    |> assign(:intake, intake)
    |> assign(:intake_changeset, new_intake_changeset(intake, record))
    |> assign(:notes, notes_newest_first(record.id))
    |> assign(:all_conditions, Health.list_conditions())
    |> assign_conditions()
  end

  defp assign_conditions(socket) do
    assign(socket, :conditions, Professionals.list_client_conditions(socket.assigns.record.id))
  end

  defp fetch_record(professional_id, id) do
    Professionals.get_client_record!(professional_id, id)
  rescue
    Ecto.NoResultsError -> nil
    Ecto.Query.CastError -> nil
  end

  # ── Client details form ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("validate_client", %{"client" => params}, socket) do
    changeset =
      socket.assigns.record
      |> Professionals.change_client_record(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :client_changeset, changeset)}
  end

  def handle_event("save_client", %{"client" => params}, socket) do
    save_client(params, socket)
  end

  # ── Health conditions (structured client↔condition link) ────────────────────────

  def handle_event("add_condition", %{"condition_id" => ""}, socket), do: {:noreply, socket}

  def handle_event("add_condition", %{"condition_id" => condition_id}, socket) do
    Professionals.add_client_condition(socket.assigns.record.id, condition_id)
    {:noreply, socket |> assign_conditions() |> put_flash(:info, "Condition added.")}
  end

  def handle_event("remove_condition", %{"id" => condition_id}, socket) do
    Professionals.remove_client_condition(socket.assigns.record.id, condition_id)
    {:noreply, assign_conditions(socket)}
  end

  # ── Intake form (edit only) ─────────────────────────────────────────────────────

  def handle_event("validate_intake", %{"intake" => params} = payload, socket) do
    changeset =
      socket.assigns.intake
      |> Professionals.change_intake(params)
      |> Map.put(:action, :validate)
      |> recompute_energy(payload["_target"])

    {:noreply, assign(socket, :intake_changeset, changeset)}
  end

  def handle_event("save_intake", %{"intake" => params}, socket) do
    attrs = Map.put(params, "professional_client_id", socket.assigns.record.id)

    result =
      case socket.assigns.intake do
        %ClientIntake{id: nil} -> Professionals.create_intake(attrs)
        intake -> Professionals.update_intake(intake, attrs)
      end

    case result do
      {:ok, intake} ->
        {:noreply,
         socket
         |> assign(:intake, intake)
         |> assign(:intake_changeset, Professionals.change_intake(intake))
         |> put_flash(:info, "Intake saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :intake_changeset, changeset)}
    end
  end

  # ── Consultation notes (edit only) ──────────────────────────────────────────────

  def handle_event("add_note", _params, socket) do
    {:ok, _} =
      Professionals.create_consultation_note(%{
        "professional_client_id" => socket.assigns.record.id
      })

    {:noreply, reload_notes(socket)}
  end

  def handle_event("save_note", %{"note" => %{"_id" => id} = params}, socket) do
    note = fetch_note(socket, id)

    case Professionals.update_consultation_note(note, Map.delete(params, "_id")) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Note saved.") |> reload_notes()}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not save note.")}
    end
  end

  def handle_event("delete_note", %{"id" => id}, socket) do
    {:ok, _} = socket |> fetch_note(id) |> Professionals.delete_consultation_note()
    {:noreply, reload_notes(socket)}
  end

  defp fetch_note(socket, id) do
    id = String.to_integer(to_string(id))
    Enum.find(socket.assigns.notes, &(&1.id == id))
  end

  defp reload_notes(socket) do
    assign(socket, :notes, notes_newest_first(socket.assigns.record.id))
  end

  # The read-only record view keeps notes oldest-first (a chronological timeline);
  # the editor shows newest first so a just-added (still blank) note lands on top.
  defp notes_newest_first(client_id) do
    client_id |> Professionals.list_consultation_notes() |> Enum.reverse()
  end

  # ── Event helpers ───────────────────────────────────────────────────────────────

  # The record's `professional_id`/`user_id` are already set (it was created from
  # the client), so the details form only updates the editable PII fields.
  defp save_client(params, socket) do
    case Professionals.update_client_record(socket.assigns.record, params) do
      {:ok, record} ->
        {:noreply,
         socket
         |> assign(:record, record)
         |> assign(:client_changeset, Professionals.change_client_record(record))
         |> put_flash(:info, "Client saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :client_changeset, changeset)}
    end
  end

  # ── Render ──────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns, :detail_labels, Fields.detail_labels())
      |> assign(:recall_labels, Fields.recall_labels())
      |> assign(:modalities, ConsultationNote.modalities())

    ~H"""
    <div class="profile-form max-w-4xl mx-auto pb-16">
      <.link
        navigate={~p"/nutritionist/clients/#{@record.user_id}"}
        class="text-parchment-dim hover:text-parchment text-sm"
      >
        ← Back to client
      </.link>

      <h1 class="text-2xl font-display font-bold text-parchment mt-2 mb-6">
        {@record.full_name}
      </h1>

      {client_section(assigns)}
      {conditions_section(assigns)}
      {intake_section(assigns)}
      {notes_section(assigns)}
    </div>
    """
  end

  # ── Client details ──────────────────────────────────────────────────────────────

  defp client_section(assigns) do
    ~H"""
    <section class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mb-6">
      <h2 class="text-lg font-display font-bold text-parchment mb-4">Client details</h2>

      <.form
        :let={f}
        for={@client_changeset}
        as={:client}
        id="client-details-form"
        phx-change="validate_client"
        phx-submit="save_client"
        class="space-y-4 mt-4"
      >
        <.labeled label="Full name">
          <.input field={f[:full_name]} type="text" />
        </.labeled>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.labeled label="Date of birth">
            <.input field={f[:date_of_birth]} type="date" />
          </.labeled>
          <.labeled label="Email">
            <.input field={f[:email]} type="text" />
          </.labeled>
          <.labeled label="Phone">
            <.input field={f[:phone]} type="text" />
          </.labeled>
          <.labeled label="Postal code">
            <.input field={f[:postal_code]} type="text" />
          </.labeled>
        </div>
        <.labeled label="Address">
          <.input field={f[:address]} type="text" />
        </.labeled>
        <.labeled label="Work / schedule">
          <.input field={f[:work_schedule]} type="text" />
        </.labeled>

        <.action variant={:primary} size={:sm} type="submit">
          Save details
        </.action>
      </.form>
    </section>
    """
  end

  # ── Health conditions ─────────────────────────────────────────────────────────

  defp conditions_section(assigns) do
    linked_ids = Enum.map(assigns.conditions, & &1.id)
    available = Enum.reject(assigns.all_conditions, &(&1.id in linked_ids))
    assigns = assign(assigns, :available_conditions, available)

    ~H"""
    <section class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mb-6">
      <h2 class="text-lg font-display font-bold text-parchment mb-1">Health conditions</h2>
      <p class="text-parchment-dim text-sm mb-4">
        Link existing conditions to this client. Only you, the nutritionist, can record these.
      </p>

      <%= if Enum.empty?(@conditions) do %>
        <p class="text-parchment-dim text-sm mb-4">No conditions recorded yet.</p>
      <% else %>
        <div class="flex flex-wrap gap-2 mb-4">
          <%= for condition <- @conditions do %>
            <span class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-paprika/20 text-paprika text-sm">
              {condition.name}
              <button
                type="button"
                phx-click="remove_condition"
                phx-value-id={condition.id}
                aria-label={"Remove #{condition.name}"}
                class="hover:text-parchment"
              >
                ✕
              </button>
            </span>
          <% end %>
        </div>
      <% end %>

      <%= if Enum.empty?(@available_conditions) do %>
        <p class="text-parchment-dim text-sm">All conditions in the registry are already linked.</p>
      <% else %>
        <form phx-submit="add_condition" class="flex flex-wrap items-end gap-3">
          <.labeled label="Add a condition">
            <select
              name="condition_id"
              class="bg-ink border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm min-w-56"
            >
              <option value="">— Select a condition —</option>
              <%= for condition <- @available_conditions do %>
                <option value={condition.id}>{condition.name}</option>
              <% end %>
            </select>
          </.labeled>
          <.action variant={:primary} size={:sm} type="submit">Add</.action>
        </form>
      <% end %>
    </section>
    """
  end

  # ── Intake ──────────────────────────────────────────────────────────────────────

  defp intake_section(assigns) do
    ~H"""
    <.form
      :let={f}
      for={@intake_changeset}
      as={:intake}
      id="intake-form"
      phx-change="validate_intake"
      phx-submit="save_intake"
      class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mb-6"
    >
      <h2 class="text-lg font-display font-bold text-parchment mb-4">Intake</h2>

      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
        <.labeled label="Assessed on">
          <.input field={f[:assessed_on]} type="date" />
        </.labeled>
        <.labeled label="Sex">
          <.input
            field={f[:sex]}
            type="select"
            prompt="—"
            options={for {v, l} <- Anthropometrics.sexes(), do: {l, v}}
          />
        </.labeled>
        <.labeled label="Age">
          <.input field={f[:age]} type="number" />
        </.labeled>
        <.labeled label="Activity level">
          <.input
            field={f[:activity_level]}
            type="select"
            prompt="—"
            options={for {v, l, _f} <- Anthropometrics.activity_levels(), do: {l, v}}
          />
        </.labeled>
        <.labeled label="Height (m)">
          <.input field={f[:height_m]} type="number" step="0.01" />
        </.labeled>
        <.labeled label="Weight (kg)">
          <.input field={f[:weight_kg]} type="number" step="0.1" />
        </.labeled>
        <.labeled label="BMI (auto)">
          <.input field={f[:bmi]} type="number" step="0.1" />
        </.labeled>
        <.labeled label="Usual wt (kg)">
          <.input field={f[:usual_weight_kg]} type="number" step="0.1" />
        </.labeled>
        <.labeled label="Ideal wt (kg)">
          <.input field={f[:ideal_weight_kg]} type="number" step="0.1" />
        </.labeled>
        <.labeled label="Adjusted wt (kg)">
          <.input field={f[:adjusted_weight_kg]} type="number" step="0.1" />
        </.labeled>
        <.labeled label="BMR (auto, kcal)">
          <.input field={f[:bmr_kcal]} type="number" />
        </.labeled>
        <.labeled label="TDEE (auto, kcal)">
          <.input field={f[:tdee_kcal]} type="number" />
        </.labeled>
      </div>

      <.labeled label="Goal">
        <.input field={f[:goal]} type="text" />
      </.labeled>

      <h3 class="text-sm font-semibold text-parchment mt-5 mb-2">Questionnaire</h3>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3">
        <%= for {key, label} <- @detail_labels do %>
          <.labeled label={label}>
            <textarea
              name={"intake[details][#{key}]"}
              rows="2"
              class="w-full bg-ink border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm"
            >{detail_value(@intake, key)}</textarea>
          </.labeled>
        <% end %>
      </div>

      <h3 class="text-sm font-semibold text-parchment mt-5 mb-2">24-hour recall</h3>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3">
        <%= for {key, label} <- @recall_labels do %>
          <.labeled label={label}>
            <input
              type="text"
              name={"intake[details][recall_24h][#{key}]"}
              value={recall_value(@intake, key)}
              class="w-full bg-ink border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm"
            />
          </.labeled>
        <% end %>
      </div>

      <.action variant={:primary} size={:sm} type="submit" class="mt-5">Save intake</.action>
    </.form>
    """
  end

  # New intake: prefill `age` from the client's date of birth so the common case
  # needs no typing. Existing intakes keep their stored age.
  defp new_intake_changeset(%ClientIntake{id: nil} = intake, record) do
    case {intake.age, client_age(record)} do
      {nil, age} when is_integer(age) -> Professionals.change_intake(intake, %{"age" => age})
      _ -> Professionals.change_intake(intake)
    end
  end

  defp new_intake_changeset(intake, _record), do: Professionals.change_intake(intake)

  defp client_age(%{date_of_birth: %Date{} = dob}) do
    today = Date.utc_today()
    age = today.year - dob.year - if(Date.compare(replace_year(dob, today.year), today) == :gt, do: 1, else: 0)
    if age > 0, do: age
  end

  defp client_age(_), do: nil

  defp replace_year(%Date{month: 2, day: 29} = dob, year) do
    # Guard against non-leap target years so the birthday comparison never crashes.
    case Date.new(year, 2, 29) do
      {:ok, date} -> date
      {:error, _} -> %Date{dob | year: year, day: 28}
    end
  end

  defp replace_year(dob, year), do: %Date{dob | year: year}

  # Recompute BMI/BMR/TDEE only when a *source* input changed (overwriting the
  # outputs so they track inputs live). Editing an output directly leaves it as
  # typed — the override path.
  defp recompute_energy(changeset, target) do
    if target && List.last(target) in @energy_source_fields do
      derived =
        Anthropometrics.compute(%{
          height_m: Ecto.Changeset.get_field(changeset, :height_m),
          weight_kg: Ecto.Changeset.get_field(changeset, :weight_kg),
          sex: Ecto.Changeset.get_field(changeset, :sex),
          age: Ecto.Changeset.get_field(changeset, :age),
          activity_level: Ecto.Changeset.get_field(changeset, :activity_level)
        })

      Enum.reduce(derived, changeset, fn {field, value}, acc ->
        Ecto.Changeset.put_change(acc, field, value)
      end)
    else
      changeset
    end
  end

  defp detail_value(%ClientIntake{details: details}, key) when is_map(details),
    do: Map.get(details, key)

  defp detail_value(_, _), do: nil

  defp recall_value(%ClientIntake{details: details}, key) when is_map(details) do
    case Map.get(details, "recall_24h") do
      recall when is_map(recall) -> Map.get(recall, key)
      _ -> nil
    end
  end

  defp recall_value(_, _), do: nil

  # ── Consultation notes ──────────────────────────────────────────────────────────

  defp notes_section(assigns) do
    ~H"""
    <section>
      <div class="flex items-center justify-between mb-3">
        <h2 class="text-lg font-display font-bold text-parchment">
          Consultation notes ({length(@notes)})
        </h2>
        <.action variant={:secondary} size={:sm} type="button" phx-click="add_note">
          Add note
        </.action>
      </div>

      <%= if Enum.empty?(@notes) do %>
        <p class="text-parchment-dim text-sm">No consultation notes yet.</p>
      <% else %>
        <div class="space-y-4">
          <%= for note <- @notes do %>
            {note_form(assign(assigns, :note, note))}
          <% end %>
        </div>
      <% end %>
    </section>
    """
  end

  defp note_form(assigns) do
    ~H"""
    <.form
      :let={f}
      for={Professionals.change_consultation_note(@note)}
      as={:note}
      id={"note-form-#{@note.id}"}
      phx-submit="save_note"
      class="bg-ink-panel border border-ink-panel2 rounded-2xl p-4"
    >
      <input type="hidden" name="note[_id]" value={@note.id} />
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-3">
        <.labeled label="Visit #">
          <.input field={f[:visit_number]} type="number" />
        </.labeled>
        <.labeled label="Date">
          <.input field={f[:visit_date]} type="date" />
        </.labeled>
        <.labeled label="Modality">
          <.input field={f[:modality]} type="select" options={modality_options(@modalities)} />
        </.labeled>
        <.labeled label="Weight (kg)">
          <.input field={f[:weight_kg]} type="number" step="0.1" />
        </.labeled>
      </div>
      <.labeled label="Notes">
        <.input field={f[:body]} type="textarea" rows="3" />
      </.labeled>
      <div class="mt-3">
        <.labeled label="To do">
          <.input field={f[:todo]} type="textarea" rows="2" />
        </.labeled>
      </div>
      <div class="flex gap-2 mt-3">
        <.action variant={:primary} size={:sm} type="submit">Save note</.action>
        <.action
          variant={:danger}
          size={:sm}
          type="button"
          phx-click="delete_note"
          phx-value-id={@note.id}
          data-confirm="Delete this note?"
        >
          Delete
        </.action>
      </div>
    </.form>
    """
  end

  defp modality_options(modalities) do
    Enum.map(modalities, fn m ->
      {m |> String.replace("_", " ") |> String.capitalize(), m}
    end)
  end

  # ── Shared bits ─────────────────────────────────────────────────────────────────

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp labeled(assigns) do
    ~H"""
    <div>
      <label class="block text-sm text-parchment-dim mb-1">{@label}</label>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
