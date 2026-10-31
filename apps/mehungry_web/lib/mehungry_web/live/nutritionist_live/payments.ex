defmodule MehungryWeb.NutritionistLive.Payments do
  @moduledoc """
  The nutritionist's Payments workspace: guided Stripe Connect onboarding (the
  payout connection + status badge), the service/package price list, and the
  mandatory free-intro notice.

  Stripe onboarding lives here (moved out of the profile editor) so all payment
  concerns are in one place. The status badge is still binary in this phase;
  Phase C upgrades it to the multi-state `stripe_status/1` machine.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Professionals
  alias Mehungry.Professionals.{ProfessionalProfile, ProfessionalService}
  alias Mehungry.Billing.StripeHandler

  # ═══════════════════════════════════════════════════════════════════════════
  # Update (mount / events)
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user

    profile =
      Professionals.get_professional_profile(user.id) || %ProfessionalProfile{user_id: user.id}

    # Guarantee the locked free-intro row exists before listing.
    Professionals.ensure_intro_service(user.id)

    {:ok,
     socket
     |> assign(:page_title, "Payments")
     |> assign(:profile, profile)
     |> assign(:service_form, nil)
     |> assign(:editing_id, nil)
     |> maybe_sync_stripe(profile, params)
     |> load_services()}
  end

  @impl true
  def handle_event("connect_stripe", _params, socket) do
    user = socket.assigns.current_user
    profile = socket.assigns.profile

    cond do
      is_nil(profile.id) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Create your public profile first, then connect payouts here."
         )}

      true ->
        with {:ok, account_id} <- ensure_stripe_account(profile, user),
             {:ok, url} <-
               StripeHandler.create_account_link(
                 account_id,
                 url(~p"/nutritionist/payments?stripe=refresh"),
                 url(~p"/nutritionist/payments?stripe=return")
               ) do
          {:noreply, redirect(socket, external: url)}
        else
          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Could not start payout onboarding: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("new_service", %{"kind" => kind}, socket) when kind in ~w(session package) do
    user = socket.assigns.current_user

    service = %ProfessionalService{
      professional_id: user.id,
      kind: kind,
      position: next_position(socket.assigns.services)
    }

    {:noreply,
     socket
     |> assign(:editing_id, nil)
     |> assign(:service_form, Professionals.change_service(service))}
  end

  @impl true
  def handle_event("edit_service", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Professionals.get_service_for_professional(user.id, id) do
      nil ->
        {:noreply, socket}

      service ->
        {:noreply,
         socket
         |> assign(:editing_id, service.id)
         |> assign(:service_form, Professionals.change_service(service))}
    end
  end

  @impl true
  def handle_event("cancel_service", _params, socket) do
    {:noreply, socket |> assign(:service_form, nil) |> assign(:editing_id, nil)}
  end

  @impl true
  def handle_event("validate_service", %{"professional_service" => params}, socket) do
    changeset =
      socket.assigns.service_form.data
      |> Professionals.change_service(with_professional_id(params, socket))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :service_form, changeset)}
  end

  @impl true
  def handle_event("save_service", %{"professional_service" => params}, socket) do
    user = socket.assigns.current_user
    params = with_professional_id(params, socket)

    result =
      case socket.assigns.editing_id do
        nil ->
          # kind + position are server-controlled (set when the form opened),
          # not submitted by the form — inject them from the changeset's struct.
          data = socket.assigns.service_form.data

          params
          |> Map.put("kind", data.kind)
          |> Map.put("position", data.position)
          |> Professionals.create_service()

        id ->
          case Professionals.get_service_for_professional(user.id, id) do
            nil -> {:error, :not_found}
            service -> Professionals.update_service(service, params)
          end
      end

    case result do
      {:ok, _service} ->
        {:noreply,
         socket
         |> assign(:service_form, nil)
         |> assign(:editing_id, nil)
         |> load_services()
         |> put_flash(:info, "Service saved.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :service_form, Map.put(changeset, :action, :insert))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save the service.")}
    end
  end

  @impl true
  def handle_event("archive_service", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    with service when not is_nil(service) <-
           Professionals.get_service_for_professional(user.id, id),
         {:ok, _} <- Professionals.archive_service(service) do
      {:noreply, load_services(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_service", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Professionals.get_service_for_professional(user.id, id) do
      nil ->
        {:noreply, socket}

      service ->
        case Professionals.delete_service(service) do
          {:ok, _} -> {:noreply, socket |> load_services() |> put_flash(:info, "Service removed.")}
          {:error, :intro_undeletable} -> {:noreply, socket}
          {:error, _} -> {:noreply, put_flash(socket, :error, "Could not remove the service.")}
        end
    end
  end

  # ── Private: data + stripe ──────────────────────────────────────────────────

  defp load_services(socket) do
    assign(socket, :services, Professionals.list_services(socket.assigns.current_user.id))
  end

  defp with_professional_id(params, socket),
    do: Map.put(params, "professional_id", socket.assigns.current_user.id)

  defp next_position([]), do: 0
  defp next_position(services), do: (services |> Enum.map(& &1.position) |> Enum.max()) + 1

  # Create the Connect account on first use and persist its id.
  defp ensure_stripe_account(%{stripe_connect_account_id: id} = _p, _user)
       when is_binary(id) and id != "",
       do: {:ok, id}

  defp ensure_stripe_account(profile, user) do
    with {:ok, account_id} <- StripeHandler.create_connect_account(user.email),
         {:ok, _} <-
           Professionals.update_professional_stripe(profile, %{
             stripe_connect_account_id: account_id
           }) do
      {:ok, account_id}
    end
  end

  # After Stripe redirects back, refresh charges_enabled from the API.
  defp maybe_sync_stripe(socket, %{stripe_connect_account_id: id} = profile, %{"stripe" => "return"})
       when is_binary(id) and id != "" do
    case StripeHandler.get_connect_account(id) do
      {:ok, %{charges_enabled: enabled}} ->
        {:ok, updated} =
          Professionals.update_professional_stripe(profile, %{stripe_charges_enabled: enabled})

        assign(socket, :profile, updated)

      _ ->
        socket
    end
  end

  defp maybe_sync_stripe(socket, _profile, _params), do: socket

  # ═══════════════════════════════════════════════════════════════════════════
  # Render
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto pb-16">
      <h1 class="text-2xl font-display font-bold text-parchment mb-6">Payments</h1>

      <!-- Stripe onboarding -->
      <section class="bg-ink-panel border border-ink-panel2 rounded-xl p-6 space-y-4 mb-6">
        <h2 class="text-lg font-display font-semibold text-parchment">Get paid through M3Hungry</h2>
        <%= if is_nil(@profile.id) do %>
          <p class="text-parchment-dim text-sm">
            Set up your <a href="/nutritionist/profile" class="text-paprika hover:text-paprika-soft">public profile</a>
            first, then connect payouts here.
          </p>
        <% else %>
          <div class="flex items-center gap-3">
            <%= if @profile.stripe_charges_enabled do %>
              <span class="inline-flex items-center gap-1 text-basil text-sm">
                <.icon name="hero-check-circle" class="w-5 h-5" /> Accepting payments
              </span>
            <% else %>
              <button
                type="button"
                phx-click="connect_stripe"
                class="px-4 py-2 rounded-lg border border-paprika/40 text-paprika hover:bg-paprika/10 text-sm transition"
              >
                Connect payouts with Stripe
              </button>
            <% end %>
          </div>
          <p class="text-parchment-dim text-xs">
            Stripe handles identity verification and bank details securely — M3Hungry never sees them.
          </p>
        <% end %>
      </section>

      <!-- Free-intro obligation -->
      <section class="bg-basil/10 border border-basil/30 rounded-xl p-4 mb-6 flex gap-3">
        <.icon name="hero-information-circle" class="w-5 h-5 text-basil flex-shrink-0 mt-0.5" />
        <p class="text-parchment-dim text-sm">
          Every nutritionist on the platform offers a <strong class="text-parchment">free 15-minute intro</strong>.
          Clients can request one from your public profile; you accept or decline it like any booking.
          This can't be turned off.
        </p>
      </section>

      <!-- Services & pricing -->
      <section class="bg-ink-panel border border-ink-panel2 rounded-xl p-6 space-y-4">
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-display font-semibold text-parchment">Services &amp; pricing</h2>
          <div :if={is_nil(@service_form)} class="flex gap-2">
            <button
              type="button"
              phx-click="new_service"
              phx-value-kind="session"
              class="px-3 py-1.5 rounded-lg border border-paprika/40 text-paprika hover:bg-paprika/10 text-sm transition"
            >
              + Session
            </button>
            <button
              type="button"
              phx-click="new_service"
              phx-value-kind="package"
              class="px-3 py-1.5 rounded-lg border border-paprika/40 text-paprika hover:bg-paprika/10 text-sm transition"
            >
              + Package
            </button>
          </div>
        </div>

        <%= if @service_form do %>
          {service_form(assigns)}
        <% else %>
          <div class="space-y-3">
            <div
              :for={service <- @services}
              class="flex items-start justify-between gap-4 p-4 rounded-lg border border-ink-panel2"
            >
              <div class="min-w-0">
                <div class="flex items-center gap-2 flex-wrap">
                  <span class="text-parchment font-medium">{service.name}</span>
                  {kind_badge(service)}
                  <span :if={not service.active} class="text-parchment-dim text-xs">(hidden)</span>
                </div>
                <p :if={service.description} class="text-parchment-dim text-sm mt-1">
                  {service.description}
                </p>
                <p class="text-parchment-dim text-xs mt-1">
                  {service_meta(service)}
                </p>
              </div>
              <div class="flex items-center gap-2 flex-shrink-0">
                <button
                  type="button"
                  phx-click="edit_service"
                  phx-value-id={service.id}
                  class="text-paprika hover:text-paprika-soft text-sm"
                >
                  Edit
                </button>
                <%= if service.kind != "intro" do %>
                  <button
                    :if={service.active}
                    type="button"
                    phx-click="archive_service"
                    phx-value-id={service.id}
                    class="text-parchment-dim hover:text-parchment text-sm"
                  >
                    Hide
                  </button>
                  <button
                    type="button"
                    phx-click="delete_service"
                    phx-value-id={service.id}
                    data-confirm="Remove this service permanently?"
                    class="text-parchment-dim hover:text-paprika text-sm"
                  >
                    Delete
                  </button>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  # The add/edit form. Intro shows only name/description (price + duration are
  # locked); packages add a session count; sessions add a duration.
  defp service_form(assigns) do
    assigns = assign(assigns, :kind, Ecto.Changeset.get_field(assigns.service_form, :kind))

    ~H"""
    <.form
      :let={f}
      for={@service_form}
      id="service-form"
      phx-change="validate_service"
      phx-submit="save_service"
      class="space-y-4"
    >
      <p class="text-parchment-dim text-sm">
        {form_heading(@kind, @editing_id)}
      </p>

      <.labeled label="Name">
        <.input field={f[:name]} type="text" placeholder="e.g. Initial consultation" class="w-full" />
      </.labeled>

      <.labeled label="Description">
        <.input field={f[:description]} type="textarea" rows="2" class="w-full" />
      </.labeled>

      <div :if={@kind != "intro"} class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <.labeled label="Price (EUR)">
          <.input field={f[:price_eur]} type="number" min="0" step="0.01" class="w-full" />
        </.labeled>
        <.labeled :if={@kind == "session"} label="Duration (minutes)">
          <.input field={f[:duration_minutes]} type="number" min="1" step="5" class="w-full" />
        </.labeled>
        <.labeled :if={@kind == "package"} label="Sessions included">
          <.input field={f[:session_count]} type="number" min="1" step="1" class="w-full" />
        </.labeled>
      </div>

      <p :if={@kind == "intro"} class="text-parchment-dim text-xs">
        The intro is always free and 15 minutes — only its name and description can change.
      </p>

      <div class="flex justify-end gap-2">
        <button
          type="button"
          phx-click="cancel_service"
          class="px-4 py-2 rounded-lg border border-ink-panel2 text-parchment-dim hover:text-parchment text-sm transition"
        >
          Cancel
        </button>
        <button
          type="submit"
          class="px-5 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-medium text-sm transition"
        >
          Save
        </button>
      </div>
    </.form>
    """
  end

  defp form_heading("intro", _), do: "Free intro session"
  defp form_heading(kind, nil), do: "New #{kind}"
  defp form_heading(kind, _id), do: "Edit #{kind}"

  defp kind_badge(%{kind: "intro"}),
    do:
      Phoenix.HTML.raw(
        ~s(<span class="text-basil text-xs border border-basil/40 rounded px-1.5 py-0.5">Free intro — required</span>)
      )

  defp kind_badge(%{kind: "package"}),
    do:
      Phoenix.HTML.raw(
        ~s(<span class="text-paprika text-xs border border-paprika/40 rounded px-1.5 py-0.5">Package</span>)
      )

  defp kind_badge(_), do: Phoenix.HTML.raw("")

  defp service_meta(%{kind: "intro"}), do: "Free · 15 min"

  defp service_meta(%{kind: "package"} = s),
    do: "#{euros(s.price_cents)} · #{s.session_count} sessions"

  defp service_meta(%{kind: "session"} = s) do
    duration = if s.duration_minutes, do: " · #{s.duration_minutes} min", else: ""
    "#{euros(s.price_cents)}#{duration}"
  end

  defp euros(nil), do: "€0.00"

  defp euros(cents) when is_integer(cents) do
    "€" <> :erlang.float_to_binary(cents / 100, decimals: 2)
  end

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
