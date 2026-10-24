defmodule MehungryWeb.NutritionistLive.Clients do
  @moduledoc """
  The single nutritionist client roster. Lists the professional's
  `TutorClientAssignment`s (managed stand-ins **and** invited platform users),
  shows whether each one has a dietary-history file (`ProfessionalClient`), and
  hosts the CSV dietary-history import (`:import` action) against a picked
  assigned client. The per-client hub is `ClientDetail` (`/clients/:id`), which
  creates the file lazily on first intake/visit.
  """
  use MehungryWeb, :live_view

  alias Mehungry.{Accounts, Professionals}
  alias Mehungry.Professionals.DietaryHistory.{CsvParser, Importer}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    socket =
      socket
      |> assign(:page_title, "My Clients")
      |> assign(:confirm_remove_id, nil)
      |> assign(:show_new_form, false)
      |> assign(:new_alias, "")
      |> assign(:claim_link, nil)
      |> assign(:preview, nil)
      |> assign(:csv_content, nil)
      |> assign(:linked_user_id, nil)
      |> assign(:linked_user_label, nil)
      |> allow_upload(:csv, accept: ~w(.csv), max_entries: 1, max_file_size: 5_000_000)
      |> load_clients(user.id)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :legacy_redirect}} = socket) do
    {:noreply, push_navigate(socket, to: ~p"/nutritionist/clients")}
  end

  def handle_params(params, _uri, socket) do
    socket =
      case socket.assigns.live_action do
        :import -> maybe_preselect_client(socket, params["client_id"])
        _ -> socket
      end

    {:noreply, socket}
  end

  # Deep-link from ClientDetail: /clients/import?client_id=… preselects the target.
  defp maybe_preselect_client(socket, nil), do: socket

  defp maybe_preselect_client(socket, client_id) do
    case Enum.find(socket.assigns.clients, &(to_string(&1.client.id) == to_string(client_id))) do
      nil -> socket
      assignment -> link_user(socket, assignment.client, flash: false)
    end
  end

  # ── Roster events ─────────────────────────────────────────────────────────────

  @impl true
  def handle_event("confirm_remove", %{"client-id" => id}, socket) do
    {:noreply, assign(socket, :confirm_remove_id, String.to_integer(id))}
  end

  def handle_event("cancel_remove", _params, socket) do
    {:noreply, assign(socket, :confirm_remove_id, nil)}
  end

  def handle_event("remove_client", %{"client-id" => id}, socket) do
    professional_id = socket.assigns.current_user.id

    case Professionals.remove_client(professional_id, String.to_integer(id)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:confirm_remove_id, nil)
         |> load_clients(professional_id)
         |> put_flash(:info, "Client removed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove client.")}
    end
  end

  def handle_event("new_client", _params, socket) do
    {:noreply, socket |> assign(:show_new_form, true) |> assign(:claim_link, nil)}
  end

  def handle_event("cancel_new", _params, socket) do
    {:noreply, assign(socket, :show_new_form, false)}
  end

  def handle_event("create_client", %{"alias" => alias_name}, socket) do
    professional_id = socket.assigns.current_user.id

    case alias_name |> to_string() |> String.trim() do
      "" ->
        {:noreply, put_flash(socket, :error, "Please enter a name for the client.")}

      trimmed ->
        case Professionals.create_managed_client(professional_id, trimmed) do
          {:ok, %{claim_token: token}} ->
            {:noreply,
             socket
             |> assign(:show_new_form, false)
             |> assign(:new_alias, "")
             |> assign(:claim_link, claim_url(token))
             |> load_clients(professional_id)
             |> put_flash(:info, "Client created. Share the claim link below so they can log in.")}

          {:error, _changeset} ->
            {:noreply,
             put_flash(socket, :error, "Could not create the client. Please try again.")}
        end
    end
  end

  def handle_event("regenerate_link", %{"client-id" => id}, socket) do
    professional_id = socket.assigns.current_user.id

    case Professionals.regenerate_claim_token(professional_id, String.to_integer(id)) do
      {:ok, token} ->
        {:noreply,
         socket
         |> assign(:claim_link, claim_url(token))
         |> put_flash(:info, "New claim link generated. The previous link no longer works.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not generate a claim link for this client.")}
    end
  end

  def handle_event("dismiss_link", _params, socket) do
    {:noreply, assign(socket, :claim_link, nil)}
  end

  # ── CSV import events ───────────────────────────────────────────────────────────

  # phx-change hook the upload form needs; nothing to persist here.
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
     |> push_patch(to: ~p"/nutritionist/clients")}
  end

  def handle_event("pick_client", %{"user_id" => ""}, socket) do
    {:noreply, socket |> assign(:linked_user_id, nil) |> assign(:linked_user_label, nil)}
  end

  def handle_event("pick_client", %{"user_id" => user_id}, socket) do
    case safe_get_user(user_id) do
      nil -> {:noreply, put_flash(socket, :error, "That client could not be found.")}
      user -> {:noreply, link_user(socket, user)}
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

  # ── Data loading ────────────────────────────────────────────────────────────────

  defp load_clients(socket, professional_id) do
    socket
    |> assign(:clients, Professionals.list_clients(professional_id))
    |> assign(:records, Professionals.records_by_user_id(professional_id))
    |> assign(:unread, Professionals.unread_counts_by_client(professional_id))
  end

  # options for the import client <select>, derived from the loaded roster.
  defp assigned_client_options(clients) do
    for assignment <- clients do
      client = assignment.client
      {client.name || client.email, client.id}
    end
  end

  # Anchor the import to the picked platform user.
  defp link_user(socket, user, opts \\ []) do
    label = user.name || user.email

    socket
    |> assign(:linked_user_id, user.id)
    |> assign(:linked_user_label, label)
    |> then(fn s ->
      if Keyword.get(opts, :flash, true), do: put_flash(s, :info, "Linked to #{label}."), else: s
    end)
  end

  defp safe_get_user(id) do
    Accounts.get_user!(id)
  rescue
    Ecto.NoResultsError -> nil
    Ecto.Query.CastError -> nil
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

  defp claim_url(token), do: MehungryWeb.Endpoint.url() <> "/claim/" <> token

  # ── Render ──────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <.page_header title="My Clients">
        <:actions>
          <.action variant={:secondary} size={:sm} patch={~p"/nutritionist/clients/import"}>
            Import CSV
          </.action>
          <.action variant={:secondary} size={:sm} phx-click="new_client">
            Create client
          </.action>
          <.action variant={:primary} size={:sm} navigate={~p"/nutritionist/invitations"}>
            Invite client
          </.action>
        </:actions>
      </.page_header>

      <p class="text-parchment-dim text-xs mb-4 -mt-2">
        <span class="text-parchment">Create client</span>
        — for someone without an account yet (you plan now, they claim later).
        <span class="text-parchment">Invite client</span>
        — connect an existing m3hungry user.
      </p>

      <%= if @live_action == :import do %>
        {import_panel(assigns)}
      <% end %>

      <%= if @show_new_form do %>
        <.panel_card class="mb-4">
          <form phx-submit="create_client" class="flex flex-col sm:flex-row gap-3 sm:items-end">
            <div class="flex-1">
              <label class="block text-sm text-parchment-dim mb-1">Client name (alias)</label>
              <input
                type="text"
                name="alias"
                value={@new_alias}
                autofocus
                placeholder="e.g. Maria K."
                class="w-full rounded-lg bg-ink-panel2 border border-ink-panel2 text-parchment px-3 py-2.5 focus:border-paprika focus:outline-none"
              />
              <p class="text-parchment-dim text-xs mt-1">
                Creates a login-less account you can plan for right away. Share the claim link
                to let them log in later — all their data carries over.
              </p>
            </div>
            <div class="flex gap-2">
              <button
                type="submit"
                class="text-sm py-2.5 px-4 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-bold transition"
              >
                Create
              </button>
              <button
                type="button"
                phx-click="cancel_new"
                class="text-sm py-2.5 px-4 rounded-lg bg-ink-panel2 hover:bg-ink text-parchment-dim transition"
              >
                Cancel
              </button>
            </div>
          </form>
        </.panel_card>
      <% end %>

      <%= if @claim_link do %>
        <.panel_card class="mb-4 border-paprika/40">
          <div class="flex items-start justify-between gap-3 mb-2">
            <p class="text-parchment text-sm font-medium">Claim link</p>
            <button
              phx-click="dismiss_link"
              class="text-parchment-dim hover:text-parchment text-xs"
              title="Dismiss"
            >
              ✕
            </button>
          </div>
          <p class="text-parchment-dim text-xs mb-3">
            Send this to your client. When they open it they set their own email and password
            and take over the account — keeping the calendar and meal plans you built.
          </p>
          <div class="flex gap-2">
            <input
              type="text"
              readonly
              value={@claim_link}
              onclick="this.select()"
              class="flex-1 rounded-lg bg-ink-panel2 border border-ink-panel2 text-parchment px-3 py-2 text-sm"
            />
            <button
              type="button"
              onclick={"navigator.clipboard.writeText('#{@claim_link}')"}
              class="text-sm py-2 px-4 rounded-lg bg-ink-panel2 hover:bg-ink border border-ink-panel2 text-parchment transition"
            >
              Copy
            </button>
          </div>
        </.panel_card>
      <% end %>

      <%= if Enum.empty?(@clients) do %>
        <.panel_card class="text-center py-16">
          <p class="text-parchment font-medium mb-1">No clients yet</p>
          <p class="text-parchment-dim text-sm mb-5">
            Create a client to start planning, or invite an existing m3hungry user to connect.
          </p>
          <.action variant={:primary} size={:sm} phx-click="new_client">
            Create your first client
          </.action>
        </.panel_card>
      <% else %>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <%= for assignment <- @clients do %>
            <% client = assignment.client %>
            <% unclaimed = Accounts.managed_unclaimed?(client) %>
            <% record = @records[client.id] %>
            <% unread = Map.get(@unread, client.id, 0) %>
            <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-4">
              <div class="flex items-center gap-3 mb-3">
                <%= if client.profile_pic do %>
                  <img src={client.profile_pic} class="w-10 h-10 rounded-full object-cover" />
                <% else %>
                  <div class="w-10 h-10 rounded-full bg-basil flex items-center justify-center text-ink font-bold text-sm">
                    {String.first(client.name || "?")}
                  </div>
                <% end %>
                <div>
                  <div class="flex items-center gap-2">
                    <p class="text-parchment font-medium text-sm">{client.name || client.email}</p>
                    <%= if unclaimed do %>
                      <span class="text-[10px] uppercase tracking-wide px-1.5 py-0.5 rounded bg-paprika/20 text-paprika-soft">
                        Pending claim
                      </span>
                    <% end %>
                    <%= if unread > 0 do %>
                      <span
                        class="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full bg-red-500 text-white font-bold"
                        title="Unread messages"
                      >
                        <svg class="w-2.5 h-2.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2.5"
                            d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
                          />
                        </svg>
                        {unread}
                      </span>
                    <% end %>
                  </div>
                  <p class="text-parchment-dim text-xs">
                    Client since {Calendar.strftime(assignment.inserted_at, "%b %Y")}
                  </p>
                  <%= if record do %>
                    <.link
                      navigate={~p"/nutritionist/records/#{record.id}"}
                      class="inline-flex items-center gap-1 mt-1 text-basil hover:underline text-xs"
                    >
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2.5"
                          d="M5 13l4 4L19 7"
                        />
                      </svg>
                      Dietary history
                    </.link>
                  <% else %>
                    <.link
                      navigate={~p"/nutritionist/clients/#{client.id}"}
                      class="inline-block mt-1 text-parchment-dim hover:text-parchment text-xs"
                    >
                      + Start file
                    </.link>
                  <% end %>
                </div>
              </div>

              <div class="flex gap-2">
                <a
                  href={"/nutritionist/clients/#{client.id}"}
                  class="flex-1 text-center text-xs py-1.5 rounded-lg bg-ink-panel2 hover:bg-ink border border-ink-panel2 text-parchment-dim hover:text-parchment transition"
                >
                  Overview
                </a>
                <a
                  href={"/nutritionist/clients/#{client.id}/calendar"}
                  class="flex-1 inline-flex items-center justify-center gap-1.5 text-xs py-1.5 rounded-lg bg-paprika hover:bg-paprika-soft text-ink transition"
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="2"
                    stroke="currentColor"
                    class="size-3.5 flex-shrink-0"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 0 1 2.25-2.25h13.5A2.25 2.25 0 0 1 21 7.5v11.25m-18 0A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75m-18 0v-7.5A2.25 2.25 0 0 1 5.25 9h13.5A2.25 2.25 0 0 1 21 11.25v7.5"
                    />
                  </svg>
                  View Plan
                </a>
                <%= if @confirm_remove_id == client.id do %>
                  <button
                    phx-click="remove_client"
                    phx-value-client-id={client.id}
                    class="text-xs py-1.5 px-3 rounded-lg bg-red-700 hover:bg-red-600 text-white transition"
                  >
                    Confirm
                  </button>
                  <button
                    phx-click="cancel_remove"
                    class="text-xs py-1.5 px-3 rounded-lg bg-ink-panel2 hover:bg-ink text-parchment-dim transition"
                  >
                    Cancel
                  </button>
                <% else %>
                  <button
                    phx-click="confirm_remove"
                    phx-value-client-id={client.id}
                    class="text-xs py-1.5 px-2 rounded-lg bg-ink-panel2 hover:bg-red-900/60 text-parchment-dim hover:text-red-400 transition"
                    title="Remove client"
                  >
                    ✕
                  </button>
                <% end %>
              </div>

              <%= if unclaimed do %>
                <button
                  phx-click="regenerate_link"
                  phx-value-client-id={client.id}
                  class="mt-2 w-full text-center text-xs py-1.5 rounded-lg bg-ink-panel2 hover:bg-ink border border-ink-panel2 text-parchment-dim hover:text-parchment transition"
                >
                  Get claim link
                </button>
              <% end %>
            </div>
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
    assigns = assign(assigns, :options, assigned_client_options(assigns.clients))

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
          <%= for {label, id} <- @options do %>
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
