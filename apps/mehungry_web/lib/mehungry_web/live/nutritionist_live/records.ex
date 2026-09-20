defmodule MehungryWeb.NutritionistLive.Records do
  @moduledoc """
  Roster of a nutritionist's off-platform client records (`ProfessionalClient`),
  with a CSV import flow (upload → preview → confirm) for migrating existing
  "ΔΙΑΤΡΟΦΟΛΟΓΙΚΟ ΙΣΤΟΡΙΚΟ" Google-Sheet exports.
  """
  use MehungryWeb, :live_view

  alias Mehungry.{Accounts, Professionals}
  alias Mehungry.Professionals.DietaryHistory.{CsvParser, Importer}

  @impl true
  def mount(_params, _session, socket) do
    professional_id = socket.assigns.current_user.id

    socket =
      socket
      |> assign(:records, Professionals.list_client_records(professional_id))
      |> assign(:preview, nil)
      |> assign(:csv_content, nil)
      |> assign(:linked_user_id, nil)
      |> assign(:linked_user_label, nil)
      |> assign(:assigned_clients, assigned_client_options(professional_id))
      |> allow_upload(:csv, accept: ~w(.csv), max_entries: 1, max_file_size: 5_000_000)

    {:ok, socket}
  end

  # options for the client <select>: {label, platform user id}
  defp assigned_client_options(professional_id) do
    professional_id
    |> Professionals.list_clients()
    |> Enum.map(fn assignment ->
      client = assignment.client
      {client.name || client.email, client.id}
    end)
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :page_title, "Client Records")}
  end

  # ── Events ──────────────────────────────────────────────────────────────────────

  # phx-change hook the upload form needs; nothing to persist here.
  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("preview", _params, socket) do
    case read_upload(socket) do
      {:ok, content} ->
        case CsvParser.parse(content) do
          {:ok, parsed} ->
            {:noreply,
             socket
             |> assign(:csv_content, content)
             |> assign(:preview, summarize(parsed, socket.assigns.linked_user_label))}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Could not parse CSV: #{inspect(reason)}")}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Please choose a CSV file first.")}
    end
  end

  def handle_event("cancel_import", _params, socket) do
    {:noreply,
     socket
     |> assign(:preview, nil)
     |> assign(:csv_content, nil)
     |> assign(:linked_user_id, nil)
     |> assign(:linked_user_label, nil)
     |> push_patch(to: ~p"/nutritionist/records")}
  end

  def handle_event("pick_client", %{"user_id" => ""}, socket) do
    {:noreply, socket |> assign(:linked_user_id, nil) |> assign(:linked_user_label, nil)}
  end

  def handle_event("pick_client", %{"user_id" => user_id}, socket) do
    case safe_get_user(user_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That client could not be found.")}

      user ->
        {:noreply, link_user(socket, user)}
    end
  end

  def handle_event("confirm_import", _params, socket) do
    professional_id = socket.assigns.current_user.id

    case socket.assigns.linked_user_id do
      nil ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Select the m3hungry client this record belongs to before importing."
         )}

      user_id ->
        # Sheet name wins; the linked account's name is the fallback when it's blank.
        opts =
          [user_id: user_id] ++
            if(socket.assigns.linked_user_label,
              do: [full_name: socket.assigns.linked_user_label],
              else: []
            )

        case Importer.import_csv(professional_id, socket.assigns.csv_content, opts) do
          {:ok, %{client: client, notes_count: n}} ->
            {:noreply,
             socket
             |> put_flash(:info, "Imported #{client.full_name} with #{n} consultation notes.")
             |> push_navigate(to: ~p"/nutritionist/records/#{client.id}")}

          {:error, step, reason, _changes} ->
            {:noreply, put_flash(socket, :error, "Import failed at #{step}: #{inspect(reason)}")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Import failed: #{inspect(reason)}")}
        end
    end
  end

  defp safe_get_user(id) do
    Accounts.get_user!(id)
  rescue
    Ecto.NoResultsError -> nil
    Ecto.Query.CastError -> nil
  end

  # Anchor the record to the picked platform user.
  defp link_user(socket, user) do
    label = user.name || user.email

    socket
    |> assign(:linked_user_id, user.id)
    |> assign(:linked_user_label, label)
    |> put_flash(:info, "Linked to #{label}.")
  end

  defp read_upload(socket) do
    case consume_uploaded_entries(socket, :csv, fn %{path: path}, _entry ->
           {:ok, File.read!(path)}
         end) do
      [content] -> {:ok, content}
      _ -> :error
    end
  end

  defp summarize(parsed, name_override) do
    intake = parsed.intake

    %{
      full_name: presence(parsed.client[:full_name]) || presence(name_override) || "Νέος πελάτης",
      notes_count: length(parsed.consultation_notes),
      bmi: intake[:bmi],
      weight_kg: intake[:weight_kg],
      goal: intake[:goal],
      first_visit:
        parsed.consultation_notes
        |> Enum.map(& &1.visit_date)
        |> Enum.reject(&is_nil/1)
        |> Enum.min(fn -> nil end),
      last_visit:
        parsed.consultation_notes
        |> Enum.map(& &1.visit_date)
        |> Enum.reject(&is_nil/1)
        |> Enum.max(fn -> nil end)
    }
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(s) when is_binary(s), do: if(String.trim(s) == "", do: nil, else: s)

  # ── Render ──────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <.page_header title="Client Records">
        <:actions>
          <.action variant={:secondary} size={:sm} patch={~p"/nutritionist/records/import"}>
            Import CSV
          </.action>
          <.action variant={:primary} size={:sm} navigate={~p"/nutritionist/records/new"}>
            New client
          </.action>
        </:actions>
      </.page_header>

      <%= if @live_action == :import do %>
        {import_panel(assigns)}
      <% end %>

      <%= if Enum.empty?(@records) do %>
        <.panel_card class="text-center py-16">
          <p class="text-parchment font-medium mb-1">No client records yet</p>
          <p class="text-parchment-dim text-sm mb-5">
            Add a client by hand, or import an existing dietary-history sheet.
          </p>
          <div class="flex items-center justify-center gap-2">
            <.action variant={:secondary} size={:sm} patch={~p"/nutritionist/records/import"}>
              Import CSV
            </.action>
            <.action variant={:primary} size={:sm} navigate={~p"/nutritionist/records/new"}>
              New client
            </.action>
          </div>
        </.panel_card>
      <% else %>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <%= for record <- @records do %>
            <.link
              navigate={~p"/nutritionist/records/#{record.id}"}
              class="block bg-ink-panel border border-ink-panel2 rounded-2xl p-4 hover:border-paprika-soft transition-colors"
            >
              <p class="text-parchment font-medium">{record.full_name}</p>
              <p class="text-parchment-dim text-xs mt-1">
                {record.email || record.phone || "—"}
              </p>
              <p class="text-parchment-dim text-xs mt-2">
                Added {Calendar.strftime(record.inserted_at, "%b %d, %Y")}
              </p>
            </.link>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp import_panel(assigns) do
    ~H"""
    <.panel_card class="mb-6">
      <%= if @preview do %>
        <h2 class="text-lg font-display font-bold text-parchment mb-3">Preview import</h2>
        <dl class="grid grid-cols-2 gap-y-2 text-sm mb-4">
          <dt class="text-parchment-dim">Client account</dt>
          <dd class="text-parchment">{@linked_user_label || "— not selected —"}</dd>
          <dt class="text-parchment-dim">Client</dt>
          <dd class="text-parchment">{@preview.full_name}</dd>
          <dt class="text-parchment-dim">Consultation notes</dt>
          <dd class="text-parchment">{@preview.notes_count}</dd>
          <dt class="text-parchment-dim">BMI / Weight</dt>
          <dd class="text-parchment">{@preview.bmi || "—"} / {@preview.weight_kg || "—"} kg</dd>
          <dt class="text-parchment-dim">Goal</dt>
          <dd class="text-parchment">{@preview.goal || "—"}</dd>
          <dt class="text-parchment-dim">Visit range</dt>
          <dd class="text-parchment">
            {fmt_date(@preview.first_visit)} – {fmt_date(@preview.last_visit)}
          </dd>
        </dl>

        {client_select(assigns)}

        <%= if is_nil(@linked_user_id) do %>
          <p class="text-red-400 text-xs mb-3">
            Select the m3hungry client this record belongs to — records can't be headless.
          </p>
        <% end %>

        <div class="flex gap-2">
          <.action
            variant={:primary}
            size={:sm}
            phx-click="confirm_import"
            disabled={is_nil(@linked_user_id)}
          >
            Confirm &amp; import
          </.action>
          <.action variant={:ghost} size={:sm} phx-click="cancel_import">
            Cancel
          </.action>
        </div>
      <% else %>
        <h2 class="text-lg font-display font-bold text-parchment mb-3">Import dietary-history CSV</h2>

        {client_select(assigns)}

        <form id="csv-import-form" phx-change="validate" phx-submit="preview" class="mt-4">
          <div class="mb-3" phx-drop-target={@uploads.csv.ref}>
            <label
              for={@uploads.csv.ref}
              class="flex flex-col items-center justify-center gap-1 border-2 border-dashed border-ink-panel2 rounded-xl px-4 py-8 text-center cursor-pointer hover:border-paprika-soft transition-colors"
            >
              <span class="text-parchment text-sm font-medium">
                Drag &amp; drop a CSV file here
              </span>
              <span class="text-parchment-dim text-xs">or click to browse your files</span>
              <.live_file_input upload={@uploads.csv} class="sr-only" />
            </label>
          </div>
          <%= for entry <- @uploads.csv.entries do %>
            <p class="text-parchment text-xs mb-2">Selected: {entry.client_name}</p>
            <%= for err <- upload_errors(@uploads.csv, entry) do %>
              <p class="text-red-400 text-xs">{error_to_string(err)}</p>
            <% end %>
          <% end %>
          <div class="flex gap-2">
            <.action variant={:primary} size={:sm} type="submit">Preview</.action>
            <.action variant={:ghost} size={:sm} type="button" phx-click="cancel_import">
              Cancel
            </.action>
          </div>
        </form>
      <% end %>
    </.panel_card>
    """
  end

  # Required client-account picker — a record is never headless.
  defp client_select(assigns) do
    ~H"""
    <div class="bg-ink rounded-lg p-3">
      <label class="block text-xs text-parchment-dim mb-1">
        m3hungry client (required)
      </label>
      <form id="pick-client-form" phx-change="pick_client">
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

      <p class="text-xs text-parchment-dim mt-2">
        <%= if @linked_user_id do %>
          Linked to {@linked_user_label}.
        <% else %>
          Pick the registered client this dietary history belongs to.
        <% end %>
      </p>
    </div>
    """
  end

  defp fmt_date(nil), do: "—"
  defp fmt_date(%Date{} = d), do: Calendar.strftime(d, "%b %d, %Y")

  defp error_to_string(:too_large), do: "File is too large (max 5MB)."
  defp error_to_string(:not_accepted), do: "Only .csv files are accepted."
  defp error_to_string(:too_many_files), do: "Please choose a single file."
  defp error_to_string(other), do: to_string(other)
end
