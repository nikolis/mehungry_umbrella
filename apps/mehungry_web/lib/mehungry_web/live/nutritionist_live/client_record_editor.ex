defmodule MehungryWeb.NutritionistLive.ClientRecordEditor do
  @moduledoc """
  Manual authoring UI for a `ProfessionalClient` dietary-history record — the
  by-hand counterpart to the CSV import in `NutritionistLive.Records`.

  `:new` collects the client's identity and its association (external person, or
  an m3hungry platform user picked from the nutritionist's assigned clients / by
  email), then navigates into `:edit`, which persists incrementally (mirroring
  `ArticleEditor`): the client details form, a single `ClientIntake` (typed
  anthropometrics + the free-form questionnaire/24h-recall `details` map), and a
  repeatable list of `ConsultationNote`s.
  """
  use MehungryWeb, :live_view

  alias Mehungry.{Accounts, Professionals}
  alias Mehungry.Professionals.{ProfessionalClient, ClientIntake, ConsultationNote}
  alias Mehungry.Professionals.DietaryHistory.Fields

  # ── Mount ─────────────────────────────────────────────────────────────────────

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
        {:ok, assign_edit(socket, record)}
    end
  end

  def mount(_params, _session, socket) do
    professional_id = socket.assigns.current_user.id
    client = %ProfessionalClient{professional_id: professional_id}

    {:ok,
     socket
     |> assign(:page_title, "New client")
     |> assign(:record, client)
     |> assign(:client_changeset, Professionals.change_client_record(client))
     |> assign(:link_mode, :external)
     |> assign(:linked_user_id, nil)
     |> assign(:assigned_clients, assigned_client_options(professional_id))
     |> assign(:email_lookup, "")}
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
    |> assign(:intake_changeset, Professionals.change_intake(intake))
    |> assign(:notes, notes_newest_first(record.id))
    |> assign(:link_mode, if(record.user_id, do: :platform, else: :external))
    |> assign(:linked_user_id, record.user_id)
    |> assign(:assigned_clients, assigned_client_options(record.professional_id))
    |> assign(:email_lookup, "")
  end

  defp fetch_record(professional_id, id) do
    Professionals.get_client_record!(professional_id, id)
  rescue
    Ecto.NoResultsError -> nil
    Ecto.Query.CastError -> nil
  end

  # options for the assigned-clients <select>: {label, platform user id}
  defp assigned_client_options(professional_id) do
    professional_id
    |> Professionals.list_clients()
    |> Enum.map(fn assignment ->
      client = assignment.client
      {client.name || client.email, client.id}
    end)
  end

  # ── Association (external vs. m3hungry user) ────────────────────────────────────

  @impl true
  def handle_event("set_link_mode", %{"mode" => "external"}, socket) do
    {:noreply,
     socket
     |> assign(:link_mode, :external)
     |> assign(:linked_user_id, nil)}
  end

  def handle_event("set_link_mode", %{"mode" => "platform"}, socket) do
    {:noreply, assign(socket, :link_mode, :platform)}
  end

  def handle_event("pick_assigned", %{"user_id" => ""}, socket) do
    {:noreply, assign(socket, :linked_user_id, nil)}
  end

  def handle_event("pick_assigned", %{"user_id" => user_id}, socket) do
    case safe_get_user(user_id) do
      nil -> {:noreply, put_flash(socket, :error, "That client could not be found.")}
      user -> {:noreply, link_user(socket, user)}
    end
  end

  def handle_event("lookup_email", %{"email" => email}, socket) do
    case email |> to_string() |> String.trim() do
      "" ->
        {:noreply, put_flash(socket, :error, "Enter an email to look up.")}

      trimmed ->
        case Accounts.get_user_by_email(trimmed) do
          nil ->
            {:noreply,
             socket
             |> assign(:email_lookup, trimmed)
             |> put_flash(:error, "No m3hungry account found for #{trimmed}.")}

          user ->
            {:noreply, socket |> assign(:email_lookup, "") |> link_user(user)}
        end
    end
  end

  # ── Client details form ─────────────────────────────────────────────────────────

  def handle_event("validate_client", %{"client" => params}, socket) do
    changeset =
      socket.assigns.record
      |> Professionals.change_client_record(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :client_changeset, changeset)}
  end

  def handle_event("save_client", %{"client" => params}, socket) do
    attrs =
      params
      |> Map.put("professional_id", socket.assigns.current_user.id)
      |> Map.put("user_id", user_id_for_save(socket))

    case socket.assigns.record do
      %ProfessionalClient{id: nil} ->
        case Professionals.create_client_record(attrs) do
          {:ok, record} ->
            {:noreply,
             socket
             |> put_flash(:info, "Client created.")
             |> push_navigate(to: ~p"/nutritionist/records/#{record.id}/edit")}

          {:error, changeset} ->
            {:noreply, assign(socket, :client_changeset, Map.put(changeset, :action, :insert))}
        end

      record ->
        case Professionals.update_client_record(record, attrs) do
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
  end

  # ── Intake form (edit only) ─────────────────────────────────────────────────────

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

  defp safe_get_user(id) do
    Accounts.get_user!(id)
  rescue
    Ecto.NoResultsError -> nil
    Ecto.Query.CastError -> nil
  end

  # Set the linked user id and prefill name/email into the (unsaved) client form.
  defp link_user(socket, user) do
    attrs = %{
      "full_name" => user.name || socket.assigns.record.full_name,
      "email" => user.email
    }

    socket
    |> assign(:linked_user_id, user.id)
    |> assign(:client_changeset, Professionals.change_client_record(socket.assigns.record, attrs))
    |> put_flash(:info, "Linked to #{user.name || user.email}.")
  end

  defp user_id_for_save(socket) do
    case socket.assigns.link_mode do
      :platform -> socket.assigns.linked_user_id
      :external -> nil
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
        navigate={~p"/nutritionist/records"}
        class="text-parchment-dim hover:text-parchment text-sm"
      >
        ← Back to records
      </.link>

      <h1 class="text-2xl font-display font-bold text-parchment mt-2 mb-6">
        {if @live_action == :new, do: "New client", else: @record.full_name}
      </h1>

      {client_section(assigns)}

      <%= if @live_action == :edit do %>
        {intake_section(assigns)}
        {notes_section(assigns)}
      <% end %>
    </div>
    """
  end

  # ── Client details ──────────────────────────────────────────────────────────────

  defp client_section(assigns) do
    ~H"""
    <section class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mb-6">
      <h2 class="text-lg font-display font-bold text-parchment mb-4">Client details</h2>

      {association_control(assigns)}

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
          {if @live_action == :new, do: "Create client", else: "Save details"}
        </.action>
      </.form>
    </section>
    """
  end

  defp association_control(assigns) do
    ~H"""
    <div class="bg-ink rounded-lg p-3 mb-2">
      <div class="flex gap-2 mb-3">
        <button
          type="button"
          phx-click="set_link_mode"
          phx-value-mode="external"
          class={link_tab_class(@link_mode == :external)}
        >
          External person
        </button>
        <button
          type="button"
          phx-click="set_link_mode"
          phx-value-mode="platform"
          class={link_tab_class(@link_mode == :platform)}
        >
          m3hungry client
        </button>
      </div>

      <%= if @link_mode == :platform do %>
        <div class="space-y-3">
          <.labeled label="Pick from your clients">
            <form id="pick-assigned-form" phx-change="pick_assigned">
              <select
                name="user_id"
                class="w-full bg-ink-panel border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm"
              >
                <option value="">— select a client —</option>
                <%= for {label, id} <- @assigned_clients do %>
                  <option value={id} selected={@linked_user_id == id}>{label}</option>
                <% end %>
              </select>
            </form>
          </.labeled>

          <.labeled label="…or look up by account email">
            <form id="lookup-email-form" phx-submit="lookup_email" class="flex gap-2">
              <input
                type="text"
                name="email"
                value={@email_lookup}
                placeholder="client@example.com"
                class="flex-1 bg-ink-panel border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm"
              />
              <.action variant={:secondary} size={:sm} type="submit">Look up</.action>
            </form>
          </.labeled>

          <p class="text-xs text-parchment-dim">
            <%= if @linked_user_id do %>
              Linked to m3hungry account {@linked_user_id}. Name &amp; email were prefilled — edit below if needed.
            <% else %>
              Select or look up a registered client, then save.
            <% end %>
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  defp link_tab_class(active?) do
    base = "text-xs px-3 py-1.5 rounded-lg border transition-colors "

    if active?,
      do: base <> "bg-ink-panel2 text-parchment border-paprika-soft",
      else: base <> "bg-transparent text-parchment-dim border-ink-panel2 hover:text-parchment"
  end

  # ── Intake ──────────────────────────────────────────────────────────────────────

  defp intake_section(assigns) do
    ~H"""
    <.form
      :let={f}
      for={@intake_changeset}
      as={:intake}
      id="intake-form"
      phx-submit="save_intake"
      class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mb-6"
    >
      <h2 class="text-lg font-display font-bold text-parchment mb-4">Intake</h2>

      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
        <.labeled label="Assessed on">
          <.input field={f[:assessed_on]} type="date" />
        </.labeled>
        <.labeled label="Height (m)">
          <.input field={f[:height_m]} type="number" step="0.01" />
        </.labeled>
        <.labeled label="Weight (kg)">
          <.input field={f[:weight_kg]} type="number" step="0.1" />
        </.labeled>
        <.labeled label="BMI">
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
        <.labeled label="BMR (kcal)">
          <.input field={f[:bmr_kcal]} type="number" />
        </.labeled>
        <.labeled label="TDEE (kcal)">
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
