defmodule MehungryWeb.AppointmentsLive.Index do
  @moduledoc """
  A client's own appointments ("My appointments"). Lists the consultations the
  logged-in user has requested/booked with nutritionists, and lets them cancel an
  upcoming one — which applies the **tiered client refund policy** (≥24h → full,
  4–24h → 50%, <4h → none) via `Professionals.cancel_appointment/1`.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Professionals
  alias Mehungry.ObanWorkers.AppointmentMailerWorker

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "My appointments")
     |> load_appointments()}
  end

  defp load_appointments(socket) do
    appointments = Professionals.list_appointments_for_client(socket.assigns.current_user.id)
    assign(socket, :appointments, appointments)
  end

  @impl true
  def handle_event("cancel", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Professionals.get_appointment_for_client(user.id, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Appointment not found.")}

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
            {:noreply, put_flash(socket, :error, "Could not cancel the appointment.")}
        end
    end
  end

  defp cancel_message(0), do: "Appointment cancelled. No refund applies for this cancellation time."

  defp cancel_message(cents),
    do: "Appointment cancelled. A refund of #{euros(cents)} is on its way to your card."

  # ── Render ──────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-display font-bold text-parchment mb-6">My appointments</h1>

      <%= if @appointments == [] do %>
        <p class="text-parchment-dim text-sm">
          You have no appointments yet. Find a nutritionist in the
          <.link navigate={~p"/nutritionists"} class="text-paprika hover:text-paprika-soft">directory</.link>.
        </p>
      <% else %>
        <div class="space-y-3">
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
                {Calendar.strftime(appt.scheduled_at, "%A %b %-d, %Y · %H:%M")}
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
                Cancel
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # A client can cancel a future appointment that hasn't already ended/been
  # declined or cancelled.
  defp cancellable?(%{status: status, scheduled_at: at}) do
    status in ["requested", "accepted"] and
      NaiveDateTime.compare(at, NaiveDateTime.utc_now()) == :gt
  end

  defp cancel_confirm(appt) do
    refund = Professionals.client_cancellation_refund_cents(appt)

    base =
      case appt.payment do
        nil -> "Cancel this appointment?"
        _ -> "Cancel this appointment? You'll be refunded #{euros(refund)}."
      end

    base
  end

  defp professional_name(%{professional: %{user_profile: %{display_name: name}}})
       when is_binary(name) and name != "",
       do: name

  defp professional_name(%{professional: %{name: name}}) when is_binary(name) and name != "",
    do: name

  defp professional_name(%{professional: %{email: email}}) when is_binary(email), do: email
  defp professional_name(_), do: "Nutritionist"

  defp payment_line(%{status: "paid", amount_cents: amount}), do: "Paid #{euros(amount)}"

  defp payment_line(%{status: "authorized", amount_cents: amount}),
    do: "#{euros(amount)} on hold (captured when accepted)"

  defp payment_line(%{status: "partially_refunded", refunded_amount_cents: r}),
    do: "Partially refunded #{euros(r)}"

  defp payment_line(%{status: "refunded"}), do: "Refunded"
  defp payment_line(%{status: "canceled"}), do: "Hold released"
  defp payment_line(_), do: ""

  defp status_badge(status) do
    {label, classes} =
      case status do
        "requested" -> {"Awaiting confirmation", "text-amber-300 border-amber-400/40"}
        "accepted" -> {"Confirmed", "text-basil border-basil/40"}
        "declined" -> {"Declined", "text-parchment-dim border-ink-panel2"}
        "cancelled" -> {"Cancelled", "text-parchment-dim border-ink-panel2"}
        "no_show" -> {"No-show", "text-parchment-dim border-ink-panel2"}
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
