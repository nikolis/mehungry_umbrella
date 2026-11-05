defmodule MehungryWeb.AppointmentBookingComponent do
  @moduledoc """
  Self-contained appointment-booking wizard (pick a day → time → service →
  confirm), reused wherever a client can request a consultation with a
  nutritionist — the public profile (`PublicNutritionistLive.Show`) and the
  client's "My nutritionist" hub (`MyNutritionistLive.Index`).

  The component owns its own slot/service loading and all booking events, so the
  flow — including the Stripe-authorise redirect for paid services and the
  "requested" mailer — lives in exactly one place. It reuses the same domain
  calls both surfaces already depend on: `Professionals.available_slots/3` and
  `Professionals.request_appointment/4`.

  On a successful request-only booking it notifies the parent LiveView with
  `{:appointment_booked, appointment}` so the parent can refresh any dependent
  view (e.g. the client's appointment list). Paid bookings redirect to Stripe
  Checkout and return via `:return_path` with a `?booking=success|cancelled`
  query the parent handles.

  ## Attributes
    * `:profile` — the nutritionist's `ProfessionalProfile` (carries `user_id`)
    * `:current_user` — the viewer (nil → the wizard prompts to log in)
    * `:return_path` — path Stripe returns to (without the `?booking=…` query)
    * `:payments_enabled` — whether paid bookings are live
    * `:variant` — `:card` (default, a "Book a consultation" panel) or `:button`
  """
  use MehungryWeb, :live_component

  alias Mehungry.Professionals
  alias Mehungry.ObanWorkers.AppointmentMailerWorker

  @booking_window_days 30

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if socket.assigns[:loaded] do
        socket
      else
        socket
        |> assign(:booking_window_days, @booking_window_days)
        |> assign_new(:variant, fn -> :card end)
        |> reset_booking_state()
        |> load_slots()
        |> load_services()
        |> assign(:loaded, true)
      end

    {:ok, socket}
  end

  # ── Events ───────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("select_booking_date", %{"date" => iso}, socket) do
    case Date.from_iso8601(iso) do
      {:ok, date} ->
        {:noreply,
         socket
         |> assign(:booking_date, date)
         |> assign(:booking_slot, nil)
         |> assign(:booking_error, nil)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_booking_slot", %{"at" => iso}, socket) do
    case NaiveDateTime.from_iso8601(iso) do
      {:ok, at} -> {:noreply, socket |> assign(:booking_slot, at) |> assign(:booking_error, nil)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("select_booking_service", %{"id" => id}, socket) do
    case Integer.parse(id) do
      {service_id, ""} -> {:noreply, assign(socket, :booking_service_id, service_id)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("reset_booking", _params, socket) do
    {:noreply, reset_booking_state(socket)}
  end

  def handle_event("confirm_booking", params, socket) do
    profile = socket.assigns.profile
    user = socket.assigns.current_user
    slot = socket.assigns.booking_slot

    cond do
      is_nil(user) ->
        {:noreply, redirect(socket, to: ~p"/users/log_in")}

      is_nil(slot) ->
        {:noreply, socket}

      true ->
        opts = [
          professional_service_id: socket.assigns.booking_service_id,
          title: gettext("Consultation with %{name}", name: display_name(profile)),
          notes: params["notes"],
          success_url: unverified_url(socket, socket.assigns.return_path <> "?booking=success"),
          cancel_url: unverified_url(socket, socket.assigns.return_path <> "?booking=cancelled")
        ]

        case Professionals.request_appointment(profile.user_id, user.id, slot, opts) do
          # Paid booking: redirect the client to Stripe Checkout to authorize their card.
          {:ok, _appt, checkout_url} ->
            {:noreply, redirect(socket, external: checkout_url)}

          {:ok, appt} ->
            AppointmentMailerWorker.enqueue("requested", appt.id, %{
              professional_name: display_name(profile),
              client_name: user.name || user.email,
              cta_url: url(~p"/nutritionist/appointments")
            })

            send(self(), {:appointment_booked, appt})

            {:noreply,
             socket
             |> assign(:booking_status, :done)
             |> assign(:booked_slot, slot)
             |> assign(:booking_date, nil)
             |> assign(:booking_slot, nil)
             |> assign(:booking_error, nil)
             |> load_slots()}

          {:error, :slot_unavailable} ->
            {:noreply,
             socket
             |> assign(:booking_slot, nil)
             |> load_slots()
             |> assign(:booking_error, gettext("That slot was just taken — please pick another."))}

          _ ->
            {:noreply,
             assign(
               socket,
               :booking_error,
               gettext("Could not send your request. Please try again.")
             )}
        end
    end
  end

  # ── State / loaders ────────────────────────────────────────────────────────────

  defp reset_booking_state(socket) do
    socket
    |> assign(:booking_date, nil)
    |> assign(:booking_slot, nil)
    |> assign(:booking_status, :idle)
    |> assign(:booked_slot, nil)
    |> assign(:booking_error, nil)
  end

  defp load_services(socket) do
    services = Professionals.list_active_services(socket.assigns.profile.user_id)

    socket
    |> assign(:services, services)
    |> assign(:booking_service_id, default_service_id(services))
  end

  defp default_service_id([]), do: nil

  defp default_service_id([first | _] = services) do
    intro = Enum.find(services, &(&1.kind == "intro"))
    (intro || first).id
  end

  defp load_slots(socket) do
    profile = socket.assigns.profile
    today = Date.utc_today()

    slots_by_date =
      profile.user_id
      |> Professionals.available_slots(today, Date.add(today, @booking_window_days))
      |> Enum.group_by(&NaiveDateTime.to_date/1)
      |> Enum.sort_by(fn {date, _} -> date end, Date)

    assign(socket, :slots_by_date, slots_by_date)
  end

  defp slots_for(_slots_by_date, nil), do: []

  defp slots_for(slots_by_date, date) do
    case List.keyfind(slots_by_date, date, 0) do
      {_date, slots} -> slots
      nil -> []
    end
  end

  # ── Render ─────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:modal_id, "book-appointment-modal-#{assigns.id}")
      |> assign(:day_slots, slots_for(assigns.slots_by_date, assigns.booking_date))

    ~H"""
    <div>
      <%= case @variant do %>
        <% :button -> %>
          <button
            :if={@slots_by_date != []}
            type="button"
            phx-click={show_modal(@modal_id)}
            class="px-3 py-1.5 rounded-lg bg-paprika text-ink text-sm font-medium hover:opacity-90 transition inline-flex items-center gap-1.5"
          >
            <.icon name="hero-calendar-days" class="w-4 h-4 flex-none" />
            {gettext("Book an appointment")}
          </button>
          <p :if={@slots_by_date == []} class="text-xs text-parchment-dim">
            {gettext("No open times in the next %{days} days — check back soon.",
              days: @booking_window_days
            )}
          </p>
        <% _ -> %>
          <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 sticky top-4">
            <h2 class="font-display font-semibold text-parchment mb-1">
              {gettext("Book a consultation")}
            </h2>
            <%= if @slots_by_date == [] do %>
              <p class="text-sm text-parchment-dim mt-2">
                {gettext("No open times in the next %{days} days. Please check back soon.",
                  days: @booking_window_days
                )}
              </p>
            <% else %>
              <p class="text-xs text-parchment-dim mb-4">
                {gettext("%{name} will confirm by email before it's booked.",
                  name: display_name(@profile)
                )}
              </p>
              <button
                type="button"
                phx-click={show_modal(@modal_id)}
                class="w-full inline-flex items-center justify-center gap-1.5 py-2.5 px-4 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-medium text-sm transition"
              >
                <.icon name="hero-calendar-days" class="w-4 h-4 flex-none" />
                {gettext("Request an appointment")}
              </button>
              <p :if={is_nil(@current_user)} class="text-xs text-parchment-dim mt-3">
                {gettext("You'll be asked to log in to confirm.")}
              </p>
            <% end %>
          </div>
      <% end %>

      <.modal id={@modal_id} show={false} on_cancel={JS.push("reset_booking", target: @myself)}>
        <div class="sm:min-w-[26rem]">
          <%= cond do %>
            <% @booking_status == :done -> %>
              <div class="text-center py-4">
                <div class="mx-auto w-14 h-14 rounded-full bg-basil/15 text-basil flex items-center justify-center mb-4">
                  <.icon name="hero-check-circle" class="w-8 h-8" />
                </div>
                <h3 class="text-lg font-display font-semibold text-parchment mb-1">
                  {gettext("Request sent!")}
                </h3>
                <p class="text-sm text-parchment-dim">
                  {gettext(
                    "You asked to meet on %{when}. %{name} will confirm by email — nothing is charged or final until they accept.",
                    when: Calendar.strftime(@booked_slot, "%A %b %-d at %H:%M"),
                    name: display_name(@profile)
                  )}
                </p>
                <div class="flex items-center justify-center gap-3 mt-6">
                  <button
                    type="button"
                    phx-click="reset_booking"
                    phx-target={@myself}
                    class="px-4 py-2 rounded-lg border border-ink-panel2 text-parchment-dim hover:text-parchment text-sm transition"
                  >
                    {gettext("Book another time")}
                  </button>
                  <button
                    type="button"
                    phx-click={hide_modal(@modal_id) |> JS.push("reset_booking", target: @myself)}
                    class="px-4 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-medium text-sm transition"
                  >
                    {gettext("Done")}
                  </button>
                </div>
              </div>
            <% is_nil(@current_user) -> %>
              <h3 class="text-lg font-display font-semibold text-parchment mb-2">
                {gettext("Request an appointment")}
              </h3>
              <p class="text-sm text-parchment-dim mb-5">
                {gettext("Log in to request a time with %{name}.", name: display_name(@profile))}
              </p>
              <.link
                navigate={~p"/users/log_in"}
                class="inline-flex px-4 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-medium text-sm transition"
              >
                {gettext("Log in to continue")}
              </.link>
            <% true -> %>
              <h3 class="text-lg font-display font-semibold text-parchment mb-1">
                {gettext("Request an appointment")}
              </h3>
              <p class="text-sm text-parchment-dim mb-5">
                {gettext("%{name} will confirm by email before it's booked.",
                  name: display_name(@profile)
                )}
              </p>

              <p
                :if={@booking_error}
                class="text-sm text-paprika bg-paprika/10 border border-paprika/30 rounded-lg px-3 py-2 mb-5"
                role="alert"
              >
                {@booking_error}
              </p>

              <!-- Step 1 · service -->
              <div :if={@services != []} class="mb-5">
                <p class="text-[11px] font-semibold text-parchment-dim uppercase tracking-wide mb-2">
                  {gettext("1 · Choose a service")}
                </p>
                <div class="space-y-2">
                  <button
                    :for={service <- @services}
                    type="button"
                    phx-click="select_booking_service"
                    phx-value-id={service.id}
                    phx-target={@myself}
                    class={[
                      "w-full flex items-center justify-between gap-3 px-3 py-2 rounded-lg border text-left transition",
                      if(@booking_service_id == service.id,
                        do: "border-paprika bg-paprika/10",
                        else: "border-ink-panel2 hover:border-paprika/50"
                      )
                    ]}
                  >
                    <span class="min-w-0">
                      <span class="block text-sm text-parchment font-medium truncate">
                        {service.name}
                      </span>
                      <span :if={service.description} class="block text-xs text-parchment-dim truncate">
                        {service.description}
                      </span>
                    </span>
                    <span class="flex-none text-sm text-paprika font-medium">
                      {service_price_label(service)}
                    </span>
                  </button>
                </div>
              </div>

              <!-- Step · day -->
              <p class="text-[11px] font-semibold text-parchment-dim uppercase tracking-wide mb-2">
                {gettext("%{n} · Choose a day", n: if(@services != [], do: "2", else: "1"))}
              </p>
              <div class="flex gap-2 overflow-x-auto pb-2 m3-scrollbar mb-5">
                <button
                  :for={{date, _slots} <- @slots_by_date}
                  type="button"
                  phx-click="select_booking_date"
                  phx-value-date={Date.to_iso8601(date)}
                  phx-target={@myself}
                  class={[
                    "flex-none w-16 py-2 rounded-lg border text-center transition",
                    if(@booking_date == date,
                      do: "border-paprika bg-paprika/10 text-paprika",
                      else:
                        "border-ink-panel2 text-parchment-dim hover:border-paprika/50 hover:text-parchment"
                    )
                  ]}
                >
                  <span class="block text-[10px] uppercase tracking-wide">
                    {Calendar.strftime(date, "%a")}
                  </span>
                  <span class="block text-sm font-semibold">{Calendar.strftime(date, "%-d")}</span>
                  <span class="block text-[10px] text-parchment-dim">
                    {Calendar.strftime(date, "%b")}
                  </span>
                </button>
              </div>

              <!-- Step · time -->
              <div :if={@booking_date}>
                <p class="text-[11px] font-semibold text-parchment-dim uppercase tracking-wide mb-2">
                  {gettext("%{n} · Choose a time", n: if(@services != [], do: "3", else: "2"))}
                </p>
                <div class="flex flex-wrap gap-2 mb-5 max-h-40 overflow-y-auto m3-scrollbar">
                  <button
                    :for={slot <- @day_slots}
                    type="button"
                    phx-click="select_booking_slot"
                    phx-value-at={NaiveDateTime.to_iso8601(slot)}
                    phx-target={@myself}
                    class={[
                      "px-3 py-1.5 rounded-md border text-sm transition",
                      if(@booking_slot == slot,
                        do: "border-paprika bg-paprika text-ink font-medium",
                        else: "border-paprika/40 text-paprika hover:bg-paprika/10"
                      )
                    ]}
                  >
                    {Calendar.strftime(slot, "%H:%M")}
                  </button>
                </div>
              </div>

              <!-- Step · note + confirm -->
              <form
                :if={@booking_slot}
                phx-submit="confirm_booking"
                phx-target={@myself}
                class="border-t border-ink-panel2 pt-4"
              >
                <label class="block text-[11px] font-semibold text-parchment-dim uppercase tracking-wide mb-2">
                  {gettext("%{n} · Add a note (optional)", n: if(@services != [], do: "4", else: "3"))}
                </label>
                <textarea
                  name="notes"
                  rows="2"
                  class="w-full border border-ink-panel2 bg-ink-panel2 text-parchment rounded-lg px-2 py-1.5 text-sm mb-4 placeholder-parchment-dim focus:outline-none focus:border-paprika"
                  placeholder={gettext("What would you like to discuss?")}
                ></textarea>
                <p
                  :if={@payments_enabled and selected_paid_service(@services, @booking_service_id)}
                  class="text-xs text-parchment-dim mb-4 leading-relaxed"
                >
                  {gettext(
                    "Your card is only authorised now — you're charged once %{name} accepts. Paid bookings follow our cancellation policy: full refund %{full}h+ before, 50%% between %{partial} and %{full}h before, none under %{partial}h or for a no-show.",
                    name: display_name(@profile),
                    full: Professionals.free_cancel_hours(),
                    partial: Professionals.partial_refund_hours()
                  )}
                  <.link navigate={~p"/terms"} class="text-paprika hover:underline">
                    {gettext("See our Terms")}
                  </.link>.
                </p>
                <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                  <p class="text-sm text-parchment flex items-center gap-1.5">
                    <.icon name="hero-calendar-days" class="w-4 h-4 text-paprika flex-none" />
                    {Calendar.strftime(@booking_slot, "%A %b %-d, %H:%M")}
                  </p>
                  <button
                    type="submit"
                    class="px-5 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-medium text-sm transition"
                  >
                    {gettext("Confirm request")}
                  </button>
                </div>
              </form>
          <% end %>
        </div>
      </.modal>
    </div>
    """
  end

  # ── View helpers ───────────────────────────────────────────────────────────────

  defp service_price_label(%{kind: "intro"}), do: gettext("Free · 15 min")

  defp service_price_label(%{price_cents: cents} = service)
       when is_integer(cents) and cents > 0 do
    euros = :erlang.float_to_binary(cents / 100, decimals: 2)

    if service.kind == "package" do
      gettext("€%{euros} · %{count} sessions", euros: euros, count: service.session_count)
    else
      "€#{euros}"
    end
  end

  defp service_price_label(_), do: gettext("Free")

  # The selected service if it carries a real price (drives the paid-booking
  # cancellation-policy notice). nil for the free intro or when none is selected.
  defp selected_paid_service(services, id) do
    Enum.find(services, fn s ->
      s.id == id and is_integer(s.price_cents) and s.price_cents > 0
    end)
  end

  defp display_name(profile),
    do: profile.display_name || profile.specialization || gettext("Nutritionist")
end
