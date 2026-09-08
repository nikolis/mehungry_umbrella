defmodule MehungryWeb.NutritionistLive.Records do
  @moduledoc """
  Roster of a nutritionist's off-platform client records (`ProfessionalClient`),
  with a CSV import flow (upload → preview → confirm) for migrating existing
  "ΔΙΑΤΡΟΦΟΛΟΓΙΚΟ ΙΣΤΟΡΙΚΟ" Google-Sheet exports.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Professionals
  alias Mehungry.Professionals.DietaryHistory.{CsvParser, Importer}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:records, Professionals.list_client_records(socket.assigns.current_user.id))
      |> assign(:preview, nil)
      |> assign(:csv_content, nil)
      |> assign(:import_name, "")
      |> allow_upload(:csv, accept: ~w(.csv), max_entries: 1, max_file_size: 5_000_000)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :page_title, "Client Records")}
  end

  # ── Events ──────────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("validate", %{"name" => name}, socket) do
    {:noreply, assign(socket, :import_name, name)}
  end

  def handle_event("preview", %{"name" => name}, socket) do
    case read_upload(socket) do
      {:ok, content} ->
        case CsvParser.parse(content) do
          {:ok, parsed} ->
            {:noreply,
             socket
             |> assign(:csv_content, content)
             |> assign(:import_name, name)
             |> assign(:preview, summarize(parsed, name))}

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
     |> push_patch(to: ~p"/nutritionist/records")}
  end

  def handle_event("confirm_import", _params, socket) do
    professional_id = socket.assigns.current_user.id

    opts =
      if socket.assigns.import_name != "", do: [full_name: socket.assigns.import_name], else: []

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
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-display font-bold text-parchment">Client Records</h1>
        <div class="flex gap-2">
          <.link
            navigate={~p"/nutritionist/records/new"}
            class="btn btn-sm bg-basil hover:bg-basil/80 text-ink border-0"
          >
            + New client
          </.link>
          <.link
            patch={~p"/nutritionist/records/import"}
            class="btn btn-sm bg-paprika hover:bg-paprika-soft text-ink border-0"
          >
            + Import CSV
          </.link>
        </div>
      </div>

      <%= if @live_action == :import do %>
        {import_panel(assigns)}
      <% end %>

      <%= if Enum.empty?(@records) do %>
        <div class="text-center py-16">
          <p class="text-parchment-dim mb-4">No client records yet.</p>
          <.link
            navigate={~p"/nutritionist/records/new"}
            class="text-basil hover:text-basil/80 text-sm block mb-2"
          >
            Add a new client →
          </.link>
          <.link
            patch={~p"/nutritionist/records/import"}
            class="text-paprika hover:text-paprika-soft text-sm"
          >
            Import a dietary-history sheet →
          </.link>
        </div>
      <% else %>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <%= for record <- @records do %>
            <.link
              navigate={~p"/nutritionist/records/#{record.id}"}
              class="block bg-ink-panel border border-ink-panel2 rounded-xl p-4 hover:border-paprika transition"
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
    <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mb-6">
      <%= if @preview do %>
        <h2 class="text-lg font-display font-bold text-parchment mb-3">Preview import</h2>
        <dl class="grid grid-cols-2 gap-y-2 text-sm mb-4">
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
        <div class="flex gap-2">
          <button
            phx-click="confirm_import"
            class="btn btn-sm bg-basil hover:bg-basil/80 text-ink border-0"
          >
            Confirm &amp; import
          </button>
          <button
            phx-click="cancel_import"
            class="btn btn-sm bg-ink-panel2 text-parchment-dim border-0"
          >
            Cancel
          </button>
        </div>
      <% else %>
        <h2 class="text-lg font-display font-bold text-parchment mb-3">Import dietary-history CSV</h2>
        <form id="csv-import-form" phx-change="validate" phx-submit="preview">
          <div class="mb-3">
            <label class="block text-xs text-parchment-dim mb-1">Client name (optional — used if the sheet has none)</label>
            <input
              type="text"
              name="name"
              value={@import_name}
              class="w-full bg-ink border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm"
              placeholder="e.g. Maria K."
            />
          </div>
          <div class="mb-3" phx-drop-target={@uploads.csv.ref}>
            <.live_file_input upload={@uploads.csv} class="text-sm text-parchment-dim" />
          </div>
          <%= for entry <- @uploads.csv.entries do %>
            <p class="text-parchment-dim text-xs mb-2">{entry.client_name}</p>
            <%= for err <- upload_errors(@uploads.csv, entry) do %>
              <p class="text-red-400 text-xs">{error_to_string(err)}</p>
            <% end %>
          <% end %>
          <div class="flex gap-2">
            <button
              type="submit"
              class="btn btn-sm bg-paprika hover:bg-paprika-soft text-ink border-0"
            >
              Preview
            </button>
            <button
              type="button"
              phx-click="cancel_import"
              class="btn btn-sm bg-ink-panel2 text-parchment-dim border-0"
            >
              Cancel
            </button>
          </div>
        </form>
      <% end %>
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
