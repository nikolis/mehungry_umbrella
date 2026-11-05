defmodule MehungryWeb.MyNutritionistLive.Index do
  @moduledoc """
  The client's "My nutritionist" hub — the de-facto place a consumer connects
  with a nutritionist.

  Two states, driven by whether the client has a connected nutritionist
  (`Professionals.get_assignment_for_client/1`, one nutritionist max):

    * **Connected** — leads with a preview of the connected nutritionist's public
      profile (`get_professional_profile/1`) and CTAs to **book an appointment**
      (the shared `MehungryWeb.AppointmentBookingComponent`, so a connected client
      books without leaving this screen), view the full profile, jump to the
      embedded **message thread** (`MessagesComponent`) or the appointments
      section, or **disconnect** (`unlink_nutritionist` → `unassign_nutritionist/1`,
      confirm-gated — a client can end the link itself). Messaging has no
      standalone page: the thread is only meaningful once connected, so it is
      embedded here as a component (this LiveView owns its PubSub subscription).
    * **Unconnected** — a plain empty state (icon + "not connected yet") plus a
      link to the full `/nutritionists` directory. No inline search or list is
      shown here — discovery lives in the directory.

  Pending invitations from nutritionists surface as a banner (unconnected state)
  with inline accept/decline (handlers lifted from `NutritionistLive.UserInvitations`
  so the two surfaces can't drift).

  Appointments are a **secondary** section: the client's own consultations, where
  they can cancel an upcoming one — applying the **tiered client refund policy**
  (≥24h → full, 4–24h → 50%, <4h → none) via `Professionals.cancel_appointment/1`.
  Times are stored as canonical UTC and rendered in each appointment's
  **professional timezone** (with the zone abbreviation shown) — see `Mehungry.Time`.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Professionals
  alias Mehungry.ObanWorkers.AppointmentMailerWorker

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe for the embedded message thread (MessagesComponent). The thread
    # has no standalone page — it lives on this hub — so this LiveView owns the
    # PubSub subscription and forwards messages into the component. Subscribe for
    # every connected client (harmless without a thread) so a mid-session
    # accept_invitation also receives live messages.
    if connected?(socket) do
      Professionals.subscribe_to_messages(socket.assigns.current_user.id)
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("My nutritionist"))
     |> assign(:payments_enabled, Professionals.consultation_payments_enabled?())
     |> load_connection()
     |> load_appointments()}
  end

  # Flash on return from Stripe Checkout (paid booking authorise redirect).
  @impl true
  def handle_params(%{"booking" => "success"}, _uri, socket) do
    {:noreply,
     put_flash(
       socket,
       :info,
       gettext("Your card is on hold — your nutritionist will confirm by email. You're only charged once they accept.")
     )}
  end

  def handle_params(%{"booking" => "cancelled"}, _uri, socket) do
    {:noreply,
     put_flash(socket, :error, gettext("Payment was not completed, so no time was requested."))}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # The booking component fires this after a request-only booking succeeds.
  @impl true
  def handle_info({:appointment_booked, _appt}, socket) do
    {:noreply, load_appointments(socket)}
  end

  # A new message arrived on this client's thread — forward it into the embedded
  # MessagesComponent (LiveComponents can't receive PubSub info directly).
  def handle_info({:assignment_message, message}, socket) do
    if message.client_id == socket.assigns.current_user.id do
      send_update(MehungryWeb.MyNutritionistLive.MessagesComponent,
        id: "my-nutritionist-messages",
        new_message: message
      )
    end

    {:noreply, socket}
  end

  # The MessagesComponent asks the host to surface a flash (components can't).
  def handle_info({:put_flash, type, msg}, socket) do
    {:noreply, put_flash(socket, type, msg)}
  end

  # ── Loaders ──────────────────────────────────────────────────────────────────
  defp load_connection(socket) do
    user = socket.assigns.current_user
    assignment = Professionals.get_assignment_for_client(user.id)

    # get_assignment_for_client/1 preloads only :professional (a User); the public
    # profile fields (slug/photo/specialization/city) live on ProfessionalProfile.
    connected_profile =
      assignment && Professionals.get_professional_profile(assignment.professional_id)

    socket
    |> assign(:assignment, assignment)
    |> assign(:connected_profile, connected_profile)
    |> assign(:invitations, Professionals.list_pending_invitations_for_client(user.id))
  end

  defp load_appointments(socket) do
    appointments = Professionals.list_appointments_for_client(socket.assigns.current_user.id)
    assign(socket, :appointments, appointments)
  end

  # ── Events ─────────────────────────────────────────────────────────────────
  # Invitation handlers lifted from NutritionistLive.UserInvitations.
  @impl true
  def handle_event("accept_invitation", %{"id" => id}, socket) do
    client_id = socket.assigns.current_user.id

    case Professionals.accept_invitation(String.to_integer(id), client_id) do
      {:ok, _assignment} ->
        {:noreply,
         socket
         |> load_connection()
         |> load_appointments()
         |> put_flash(:info, gettext("You now have a nutritionist!"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not accept invitation."))}
    end
  end

  @impl true
  def handle_event("decline_invitation", %{"id" => id}, socket) do
    client_id = socket.assigns.current_user.id

    case Professionals.decline_invitation(String.to_integer(id), client_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_connection()
         |> put_flash(:info, gettext("Invitation declined."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not decline invitation."))}
    end
  end

  @impl true
  def handle_event("unlink_nutritionist", _params, socket) do
    case Professionals.unassign_nutritionist(socket.assigns.current_user.id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_connection()
         |> put_flash(:info, gettext("Nutritionist removed."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not remove nutritionist."))}
    end
  end

  @impl true
  def handle_event("cancel", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Professionals.get_appointment_for_client(user.id, id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Appointment not found."))}

      appt ->
        # Compute the refund *before* cancelling (the payment status changes after).
        refund = Professionals.client_cancellation_refund_cents(appt)

        case Professionals.cancel_appointment(appt) do
          {:ok, _} ->
            AppointmentMailerWorker.enqueue("cancelled_by_client", appt.id, %{
              client_name: user.name || user.email,
              cta_url: url(~p"/nutritionist/appointments")
            })

            {:noreply,
             socket
             |> load_appointments()
             |> put_flash(:info, cancel_message(refund))}

          _ ->
            {:noreply, put_flash(socket, :error, gettext("Could not cancel the appointment."))}
        end
    end
  end

  defp cancel_message(0),
    do: gettext("Appointment cancelled. No refund applies for this cancellation time.")

  defp cancel_message(cents),
    do: gettext("Appointment cancelled. A refund of %{amount} is on its way to your card.", amount: euros(cents))

  # ── Render ──────────────────────────────────────────────────────────────────
  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-display font-bold text-parchment mb-6">
        {if @assignment, do: gettext("Your nutritionist"), else: gettext("Find a nutritionist")}
      </h1>

      <%!-- Pending invitations — only when unconnected (a connected client has one
           nutritionist; invitations from others aren't surfaced on this hub). --%>
      <section
        :if={is_nil(@assignment) and @invitations != []}
        class="mb-8 space-y-3"
        aria-label={gettext("Invitations")}
      >
        <h2 class="text-sm font-semibold text-parchment-dim uppercase tracking-wide">
          {gettext("Invitations")}
        </h2>
        <div
          :for={inv <- @invitations}
          class="bg-ink-panel border border-paprika/30 rounded-xl p-4 flex items-center justify-between gap-3"
        >
          <div class="flex items-center gap-2 min-w-0">
            <.icon name="hero-envelope" class="h-5 w-5 text-paprika flex-shrink-0" />
            <p class="text-parchment text-sm min-w-0">
              {gettext("%{name} invited you to connect.", name: invitation_name(inv))}
            </p>
          </div>
          <div class="flex gap-2 flex-shrink-0">
            <button
              type="button"
              phx-click="accept_invitation"
              phx-value-id={inv.id}
              class="px-3 py-1.5 rounded-lg bg-basil text-ink text-sm font-medium hover:opacity-90 transition"
            >
              {gettext("Accept")}
            </button>
            <button
              type="button"
              phx-click="decline_invitation"
              phx-value-id={inv.id}
              class="px-3 py-1.5 rounded-lg border border-ink-panel2 text-parchment-dim hover:text-parchment text-sm transition"
            >
              {gettext("Decline")}
            </button>
          </div>
        </div>
      </section>

      <%= cond do %>
        <% @connected_profile -> %>
          <%!-- Connected: public-profile preview + CTAs --%>
          <section class="mb-10">
            <.nutritionist_card profile={@connected_profile} variant={:preview}>
            <:actions>
              <.live_component
                module={MehungryWeb.AppointmentBookingComponent}
                id="my-nutritionist-booking"
                variant={:button}
                profile={@connected_profile}
                current_user={@current_user}
                payments_enabled={@payments_enabled}
                return_path={~p"/my-nutritionist"}
              />
              <.link
                :if={@connected_profile.slug}
                navigate={~p"/nutritionists/#{@connected_profile.slug}"}
                class="px-3 py-1.5 rounded-lg border border-paprika/40 text-paprika hover:bg-paprika/10 text-sm transition"
              >
                {gettext("View full profile")}
              </.link>
              <a
                href="#messages"
                class="px-3 py-1.5 rounded-lg border border-paprika/40 text-paprika hover:bg-paprika/10 text-sm transition inline-flex items-center gap-1.5"
              >
                <.icon name="hero-chat-bubble-left-right" class="h-4 w-4" /> {gettext("Message")}
              </a>
              <a
                href="#appointments"
                class="px-3 py-1.5 rounded-lg border border-ink-panel2 text-parchment-dim hover:text-parchment text-sm transition"
              >
                {gettext("Appointments")}
              </a>
              <button
                type="button"
                phx-click="unlink_nutritionist"
                data-confirm={gettext("Disconnect from this nutritionist? Your appointments and messages stay, but they'll no longer be your nutritionist.")}
                class="px-3 py-1.5 rounded-lg border border-ink-panel2 text-parchment-dim hover:text-paprika hover:border-paprika/40 text-sm transition"
              >
                {gettext("Disconnect")}
              </button>
            </:actions>
          </.nutritionist_card>
          </section>
        <% @assignment -> %>
          <%!-- Connected, but the professional has no published public profile:
               show the connected nutritionist from the account (never the directory). --%>
          <section class="mb-10">
            <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
              <div class="flex items-center gap-3">
                <img
                  :if={@assignment.professional.profile_pic}
                  src={@assignment.professional.profile_pic}
                  alt={@assignment.professional.name}
                  class="w-14 h-14 rounded-full object-cover"
                />
                <div
                  :if={is_nil(@assignment.professional.profile_pic)}
                  class="w-14 h-14 rounded-full bg-paprika/10 text-paprika flex items-center justify-center font-bold text-lg"
                >
                  {String.first(@assignment.professional.name || "N")}
                </div>
                <p class="font-semibold text-parchment truncate">
                  {@assignment.professional.name || @assignment.professional.email}
                </p>
              </div>
              <div class="flex flex-wrap gap-2 mt-4">
                <a
                  href="#messages"
                  class="px-3 py-1.5 rounded-lg border border-paprika/40 text-paprika hover:bg-paprika/10 text-sm transition inline-flex items-center gap-1.5"
                >
                  <.icon name="hero-chat-bubble-left-right" class="h-4 w-4" /> {gettext("Message")}
                </a>
                <a
                  href="#appointments"
                  class="px-3 py-1.5 rounded-lg border border-ink-panel2 text-parchment-dim hover:text-parchment text-sm transition"
                >
                  {gettext("Appointments")}
                </a>
                <button
                  type="button"
                  phx-click="unlink_nutritionist"
                  data-confirm={gettext("Disconnect from this nutritionist? Your appointments and messages stay, but they'll no longer be your nutritionist.")}
                  class="px-3 py-1.5 rounded-lg border border-ink-panel2 text-parchment-dim hover:text-paprika hover:border-paprika/40 text-sm transition"
                >
                  {gettext("Disconnect")}
                </button>
              </div>
            </div>
          </section>
        <% true -> %>
          <%!-- Unconnected: no directory search/list — just an empty state. --%>
          <section class="mb-10 flex flex-col items-center text-center py-10">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="w-16 h-16 text-parchment-dim mb-4"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z"
              />
            </svg>
            <p class="text-parchment-dim text-sm mb-4">
              {gettext("You're not connected to a nutritionist yet.")}
            </p>
            <.link navigate={~p"/nutritionists"} class="text-paprika hover:text-paprika-soft text-sm">
              {gettext("Browse the full directory")} →
            </.link>
          </section>
      <% end %>

      <%!-- Messages — the client↔nutritionist thread, embedded here (no standalone
           page): messaging is only meaningful once a client is connected. --%>
      <section :if={@assignment} id="messages" class="mb-10">
        <h2 class="text-xl font-display font-bold text-parchment mb-4">{gettext("Messages")}</h2>
        <.live_component
          module={MehungryWeb.MyNutritionistLive.MessagesComponent}
          id="my-nutritionist-messages"
          assignment={@assignment}
          current_user={@current_user}
        />
      </section>

      <%!-- Appointments — secondary section --%>
      <section id="appointments">
        <h2 class="text-xl font-display font-bold text-parchment mb-4">{gettext("Appointments")}</h2>

        <%= if @appointments == [] do %>
          <p class="text-parchment-dim text-sm">{gettext("You have no appointments yet.")}</p>
        <% else %>
          <div class="space-y-3 max-h-96 overflow-y-auto pr-1">
            <div
              :for={appt <- @appointments}
              class="bg-ink-panel border border-ink-panel2 rounded-xl p-4 flex items-start justify-between gap-4"
            >
              <div class="min-w-0">
                <div class="flex items-center gap-2 flex-wrap">
                  <span class="text-parchment font-medium">{professional_name(appt)}</span>
                  {status_badge(appt.status)}
                </div>
                <p class="text-parchment-dim text-sm mt-1">
                  {scheduled_line(appt)}
                </p>
                <p :if={appt.payment} class="text-parchment-dim text-xs mt-1">
                  {payment_line(appt.payment)}
                </p>
              </div>
              <div :if={cancellable?(appt)} class="flex-shrink-0">
                <button
                  type="button"
                  phx-click="cancel"
                  phx-value-id={appt.id}
                  data-confirm={cancel_confirm(appt)}
                  class="px-3 py-1.5 rounded-lg border border-paprika/40 text-paprika hover:bg-paprika/10 text-sm transition"
                >
                  {gettext("Cancel")}
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  # ── View helpers ─────────────────────────────────────────────────────────────

  defp invitation_name(%{professional: %{user_profile: %{display_name: name}}})
       when is_binary(name) and name != "",
       do: name

  defp invitation_name(%{professional: %{name: name}}) when is_binary(name) and name != "",
    do: name

  defp invitation_name(%{professional: %{email: email}}) when is_binary(email), do: email
  defp invitation_name(_), do: gettext("A nutritionist")

  # A client can cancel a future appointment that hasn't already ended/been
  # declined or cancelled. scheduled_at is stored UTC — compared against UTC now.
  defp cancellable?(%{status: status, scheduled_at: at}) do
    status in ["requested", "accepted"] and
      NaiveDateTime.compare(at, NaiveDateTime.utc_now()) == :gt
  end

  defp cancel_confirm(appt) do
    refund = Professionals.client_cancellation_refund_cents(appt)

    case appt.payment do
      nil ->
        gettext("Cancel this appointment?")

      _ ->
        gettext("Cancel this appointment? You'll be refunded %{amount}.", amount: euros(refund))
    end
  end

  defp professional_name(%{professional: %{user_profile: %{display_name: name}}})
       when is_binary(name) and name != "",
       do: name

  defp professional_name(%{professional: %{name: name}}) when is_binary(name) and name != "",
    do: name

  defp professional_name(%{professional: %{email: email}}) when is_binary(email), do: email
  defp professional_name(_), do: gettext("Nutritionist")

  # Appointment times are stored as UTC; the authoritative wall-clock is the
  # professional's local timezone. Render in that zone and tag the abbreviation
  # so a client in a different timezone isn't misled by a bare time.
  defp scheduled_line(appt) do
    tz = professional_tz(appt)
    dt = Mehungry.Time.to_local_dt(appt.scheduled_at, tz)
    Calendar.strftime(dt, "%A %b %-d, %Y · %H:%M") <> " " <> dt.zone_abbr
  end

  defp professional_tz(%{professional: %{user_profile: profile}}), do: Mehungry.Time.tz(profile)
  defp professional_tz(_), do: Mehungry.Time.tz(nil)

  defp payment_line(%{status: "paid", amount_cents: amount}),
    do: gettext("Paid %{amount}", amount: euros(amount))

  defp payment_line(%{status: "authorized", amount_cents: amount}),
    do: gettext("%{amount} on hold (captured when accepted)", amount: euros(amount))

  defp payment_line(%{status: "partially_refunded", refunded_amount_cents: r}),
    do: gettext("Partially refunded %{amount}", amount: euros(r))

  defp payment_line(%{status: "refunded"}), do: gettext("Refunded")
  defp payment_line(%{status: "canceled"}), do: gettext("Hold released")
  defp payment_line(_), do: ""

  defp status_badge(status) do
    {label, classes} =
      case status do
        "requested" -> {gettext("Awaiting confirmation"), "text-amber-300 border-amber-400/40"}
        "accepted" -> {gettext("Confirmed"), "text-basil border-basil/40"}
        "declined" -> {gettext("Declined"), "text-parchment-dim border-ink-panel2"}
        "cancelled" -> {gettext("Cancelled"), "text-parchment-dim border-ink-panel2"}
        "no_show" -> {gettext("No-show"), "text-parchment-dim border-ink-panel2"}
        _ -> {status, "text-parchment-dim border-ink-panel2"}
      end

    assigns = %{label: label, classes: classes}

    ~H"""
    <span class={["text-xs border rounded px-1.5 py-0.5", @classes]}>{@label}</span>
    """
  end

  defp euros(nil), do: "€0.00"
  defp euros(cents) when is_integer(cents), do: "€" <> :erlang.float_to_binary(cents / 100, decimals: 2)
end
