defmodule MehungryWeb.NutritionistLive.AppointmentCalendar do
  use MehungryWeb, :live_view

  alias Mehungry.Accounts
  alias Mehungry.Professionals
  alias Mehungry.Professionals.Appointment
  alias Mehungry.Professionals.ConsultationNote
  alias Mehungry.ObanWorkers.AppointmentMailerWorker

  # Vertical day-agenda bounds (wall-clock hours) and pixel height per hour.
  @agenda_start_hour 6
  @agenda_end_hour 22
  @hour_px 52

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user
    professional_id = user.id

    # Appointment times are stored as UTC; this view works in the professional's
    # local wall-clock, so everything is localized on load and converted back to
    # UTC on save.
    profile = Professionals.get_professional_profile(professional_id)
    tz = Mehungry.Time.tz(profile)
    today = Mehungry.Time.local_today(tz)

    appointments = month_appointments(professional_id, today, tz)

    clients = Professionals.list_clients(professional_id)
    pending = localize_appts(Professionals.list_pending_requests(professional_id), tz)
    availabilities = Professionals.list_availabilities(professional_id)
    google_connected = Professionals.google_calendar_connected?(professional_id)

    preselected_client_id =
      case params do
        %{"client_id" => id} -> String.to_integer(id)
        _ -> nil
      end

    socket =
      socket
      |> assign(:appointments, appointments)
      |> assign(:clients, clients)
      |> assign(:pending_requests, pending)
      |> assign(:availabilities, availabilities)
      |> assign(:google_connected, google_connected)
      |> assign(:professional_name, professional_name(profile, user))
      |> assign(:public_url, public_url(profile))
      |> assign(:page_title, gettext("Appointments"))
      |> assign(:tz, tz)
      |> assign(:today, today)
      |> assign(:current_month, today)
      |> assign(:selected_date, today)
      |> assign(:show_modal, not is_nil(preselected_client_id))
      |> assign(:show_day_modal, false)
      |> assign(:day_busy, [])
      |> assign(:show_measurement_modal, false)
      |> assign(:measurement_form, nil)
      |> assign(:measurement_record_id, nil)
      |> assign(:measurement_appointment_id, nil)
      |> assign(:editing_appointment, nil)
      |> assign(:modal_client_id, preselected_client_id)
      |> assign(
        :appointment_changeset,
        new_appointment_changeset(professional_id, preselected_client_id)
      )
      |> assign(:form_date, Date.to_iso8601(today))
      |> assign(:form_start_hour, 9)
      |> assign(:form_start_minute, 0)
      |> assign(:form_end_hour, 10)
      |> assign(:form_end_minute, 0)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_date", %{"date" => date_str}, socket) do
    date = Date.from_iso8601!(date_str)
    professional_id = socket.assigns.current_user.id

    day_busy =
      if socket.assigns.google_connected do
        # The selected date is local; query the Google busy cache (stored UTC)
        # over the matching UTC window.
        tz = socket.assigns.tz
        day_start = Mehungry.Time.to_utc(NaiveDateTime.new!(date, ~T[00:00:00]), tz)
        day_end = Mehungry.Time.to_utc(NaiveDateTime.new!(date, ~T[23:59:59]), tz)
        Professionals.list_calendar_busy(professional_id, day_start, day_end)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:selected_date, date)
     |> assign(:form_date, date_str)
     |> assign(:day_busy, day_busy)
     |> assign(:show_day_modal, true)
     |> assign(:show_modal, false)}
  end

  @impl true
  def handle_event("close_day_modal", _params, socket) do
    {:noreply, assign(socket, :show_day_modal, false)}
  end

  # "+ New" in the day modal, or a click on an empty hour row — open the create
  # form pre-filled for the selected date (and hour, when supplied).
  @impl true
  def handle_event("new_appointment", params, socket) do
    professional_id = socket.assigns.current_user.id
    date_str = socket.assigns.form_date

    start_hour =
      case Integer.parse(to_string(params["hour"] || "")) do
        {h, ""} when h in 6..21 -> h
        _ -> 9
      end

    changeset =
      Professionals.change_appointment(%Appointment{}, %{professional_id: professional_id})

    {:noreply,
     socket
     |> assign(:form_date, date_str)
     |> assign(:form_start_hour, start_hour)
     |> assign(:form_start_minute, 0)
     |> assign(:form_end_hour, start_hour + 1)
     |> assign(:form_end_minute, 0)
     |> assign(:show_day_modal, false)
     |> assign(:show_modal, true)
     |> assign(:editing_appointment, nil)
     |> assign(:appointment_changeset, changeset)}
  end

  @impl true
  def handle_event("edit_appointment", %{"id" => id}, socket) do
    case fetch_owned(socket, id) do
      nil ->
        {:noreply, appointment_not_found(socket)}

      appt ->
        changeset = Professionals.change_appointment(appt)

        {form_date, start_h, start_m, end_h, end_m} =
          decompose_appointment(appt, socket.assigns.tz)

        {:noreply,
         socket
         |> assign(:show_modal, true)
         |> assign(:show_day_modal, false)
         |> assign(:editing_appointment, appt)
         |> assign(:appointment_changeset, changeset)
         |> assign(:form_date, form_date)
         |> assign(:form_start_hour, start_h)
         |> assign(:form_start_minute, start_m)
         |> assign(:form_end_hour, end_h)
         |> assign(:form_end_minute, end_m)}
    end
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, show_modal: false, editing_appointment: nil)}
  end

  @impl true
  def handle_event("log_measurement", %{"id" => id}, socket) do
    professional_id = socket.assigns.current_user.id

    with appt when not is_nil(appt) <- fetch_owned(socket, id),
         client_id when not is_nil(client_id) <- appt.client_id,
         user <- Accounts.get_user!(client_id),
         {:ok, record} <- Professionals.ensure_client_record(professional_id, user) do
      # If progress was already logged for this meeting, pre-fill the form with
      # the existing note so saving updates it instead of inserting a duplicate.
      note =
        Professionals.get_consultation_note_by_appointment(appt.id) ||
          %ConsultationNote{
            visit_date: NaiveDateTime.to_date(appt.scheduled_at),
            appointment_id: appt.id,
            modality: "in_person"
          }

      {:noreply,
       socket
       |> assign(:show_modal, false)
       |> assign(:show_measurement_modal, true)
       |> assign(:measurement_record_id, record.id)
       |> assign(:measurement_appointment_id, appt.id)
       |> assign(:measurement_form, to_form(Professionals.change_consultation_note(note)))}
    else
      _ -> {:noreply, appointment_not_found(socket)}
    end
  end

  @impl true
  def handle_event("close_measurement_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_measurement_modal: false,
       measurement_form: nil,
       measurement_record_id: nil,
       measurement_appointment_id: nil
     )}
  end

  @impl true
  def handle_event("save_measurement", %{"consultation_note" => params}, socket) do
    params =
      Map.merge(params, %{
        "professional_client_id" => socket.assigns.measurement_record_id,
        "appointment_id" => socket.assigns.measurement_appointment_id
      })

    # One note per meeting: creates when none exists, otherwise updates the
    # latest and deletes any duplicates left for this appointment.
    case Professionals.upsert_consultation_note_for_appointment(params) do
      {:ok, _note} ->
        {:noreply,
         socket
         |> assign(
           show_measurement_modal: false,
           measurement_form: nil,
           measurement_record_id: nil,
           measurement_appointment_id: nil
         )
         |> put_flash(:info, gettext("Measurement logged."))}

      {:error, changeset} ->
        {:noreply, assign(socket, :measurement_form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("save_appointment", %{"appointment" => params}, socket) do
    professional_id = socket.assigns.current_user.id

    attrs =
      params
      |> Map.put("professional_id", professional_id)
      |> build_datetimes(socket.assigns.tz)

    # Keep the raw date/time inputs in sync so a validation error re-renders the
    # form with what the user actually submitted. These fields are bound to
    # form_* assigns, not the changeset, so without this they snap back to the
    # stale modal-open values (title/notes survive via the changeset).
    socket = sync_form_fields(socket, params)

    if manual_client_allowed?(socket, attrs) do
      persist_appointment(socket, attrs)
    else
      {:noreply, put_flash(socket, :error, gettext("Select one of your own clients."))}
    end
  end

  @impl true
  def handle_event("delete_appointment", %{"id" => id}, socket) do
    case fetch_owned(socket, id) do
      nil ->
        {:noreply, appointment_not_found(socket)}

      appt ->
        Professionals.delete_appointment(appt)
        appointments = reload_appointments(socket)

        {:noreply,
         socket
         |> assign(:appointments, appointments)
         |> assign(:show_modal, false)
         |> put_flash(:info, gettext("Appointment deleted."))}
    end
  end

  @impl true
  def handle_event("accept_appointment", %{"appointment_id" => id} = params, socket) do
    case fetch_owned(socket, id) do
      nil ->
        {:noreply, appointment_not_found(socket)}

      appt ->
        meeting_url = params["meeting_url"]
        opts = if meeting_url && meeting_url != "", do: [meeting_url: meeting_url], else: []

        case Professionals.accept_appointment(appt, opts) do
          {:ok, updated} ->
            AppointmentMailerWorker.enqueue("accepted", updated.id, %{
              professional_name: socket.assigns.professional_name,
              client_name: client_display(updated.client),
              cta_url: socket.assigns.public_url
            })

            {:noreply,
             socket
             |> refresh()
             |> put_flash(
               :info,
               gettext("Appointment accepted — the client has been emailed a calendar invite.")
             )}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Could not accept the appointment."))}
        end
    end
  end

  @impl true
  def handle_event("decline_appointment", %{"id" => id}, socket) do
    case fetch_owned(socket, id) do
      nil ->
        {:noreply, appointment_not_found(socket)}

      appt ->
        case Professionals.decline_appointment(appt) do
          {:ok, declined} ->
            AppointmentMailerWorker.enqueue("declined", declined.id, %{
              professional_name: socket.assigns.professional_name,
              cta_url: socket.assigns.public_url
            })

            {:noreply,
             socket
             |> refresh()
             |> put_flash(:info, gettext("Request declined — the client has been notified."))}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Could not decline the request."))}
        end
    end
  end

  @impl true
  def handle_event("cancel_appointment_professional", %{"id" => id}, socket) do
    case fetch_owned(socket, id) do
      nil ->
        {:noreply, appointment_not_found(socket)}

      appt ->
        case Professionals.cancel_appointment_by_professional(appt) do
          {:ok, _cancelled} ->
            AppointmentMailerWorker.enqueue("cancelled_by_professional", appt.id, %{
              professional_name: socket.assigns.professional_name,
              cta_url: socket.assigns.public_url
            })

            {:noreply,
             socket
             |> assign(:show_modal, false)
             |> assign(:editing_appointment, nil)
             |> refresh()
             |> put_flash(:info, gettext("Appointment cancelled — the client has been fully refunded."))}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Could not cancel the appointment."))}
        end
    end
  end

  @impl true
  def handle_event("prev_month", _params, socket) do
    new_month = first_of_prev_month(socket.assigns.current_month)
    {:noreply, socket |> assign(:current_month, new_month) |> load_month_appointments(new_month)}
  end

  @impl true
  def handle_event("next_month", _params, socket) do
    new_month = first_of_next_month(socket.assigns.current_month)
    {:noreply, socket |> assign(:current_month, new_month) |> load_month_appointments(new_month)}
  end

  # Month stepping pinned to the first of the target month. Date.add/2 by a fixed
  # 28/32 days drifts: -28 from a late-month date can land back in the same month
  # (so "previous" appears to do nothing), and +32 can then skip a month.
  defp first_of_prev_month(date) do
    last_of_prev = Date.add(%{date | day: 1}, -1)
    %{last_of_prev | day: 1}
  end

  defp first_of_next_month(date) do
    %{date | day: 1} |> Date.end_of_month() |> Date.add(1)
  end

  defp load_month_appointments(socket, month_date) do
    appts = month_appointments(socket.assigns.current_user.id, month_date, socket.assigns.tz)
    assign(socket, :appointments, appts)
  end

  defp reload_appointments(socket) do
    month_appointments(socket.assigns.current_user.id, socket.assigns.current_month, socket.assigns.tz)
  end

  # Appointments for the local month, localized to the professional's tz. The
  # query window is padded ±1 day because a local-month appointment near midnight
  # can be stored on the adjacent UTC date; the month grid then buckets by local
  # date, so the extra edge rows land in the right cells.
  defp month_appointments(professional_id, month, tz) do
    first = %{month | day: 1}
    start_dt = NaiveDateTime.new!(Date.add(first, -1), ~T[00:00:00])
    end_dt = NaiveDateTime.new!(Date.add(Date.end_of_month(first), 1), ~T[23:59:59])

    professional_id
    |> Professionals.list_appointments_for_professional(start_dt, end_dt)
    |> localize_appts(tz)
  end

  defp localize_appts(appts, tz), do: Enum.map(appts, &localize_appt(&1, tz))

  # Shift an appointment's stored UTC times into the professional's local
  # wall-clock so the whole view can reason in local time.
  defp localize_appt(%Appointment{} = appt, tz) do
    %{
      appt
      | scheduled_at: Mehungry.Time.to_local(appt.scheduled_at, tz),
        ends_at: appt.ends_at && Mehungry.Time.to_local(appt.ends_at, tz)
    }
  end

  # Reload both the month grid and the pending-requests panel after a change.
  defp refresh(socket) do
    professional_id = socket.assigns.current_user.id

    socket
    |> assign(:appointments, reload_appointments(socket))
    |> assign(
      :pending_requests,
      localize_appts(Professionals.list_pending_requests(professional_id), socket.assigns.tz)
    )
  end

  # Fetch an appointment by a client-supplied id, scoped to the current
  # professional. Returns nil for junk ids or appointments owned by someone else
  # so a nutritionist can never mutate another nutritionist's appointments.
  defp fetch_owned(socket, id) do
    case Integer.parse(to_string(id)) do
      {int, ""} ->
        Professionals.get_appointment_for_professional(socket.assigns.current_user.id, int)

      _ ->
        nil
    end
  end

  defp appointment_not_found(socket) do
    socket
    |> assign(:show_modal, false)
    |> assign(:editing_appointment, nil)
    |> put_flash(:error, gettext("Appointment not found."))
  end

  defp persist_appointment(socket, attrs) do
    result =
      case socket.assigns.editing_appointment do
        nil -> Professionals.create_appointment(attrs)
        appt -> Professionals.update_appointment(appt, attrs)
      end

    case result do
      {:ok, _appointment} ->
        appointments = reload_appointments(socket)

        {:noreply,
         socket
         |> assign(:appointments, appointments)
         |> assign(:show_modal, false)
         |> assign(:editing_appointment, nil)
         |> put_flash(:info, gettext("Appointment saved."))}

      {:error, changeset} ->
        {:noreply, assign(socket, :appointment_changeset, changeset)}
    end
  end

  # A manually-created/edited appointment may use an external client name (no
  # client_id) or one of the professional's *own* assigned clients — never an
  # arbitrary platform user id a crafted form submit could inject.
  defp manual_client_allowed?(socket, attrs) do
    case attrs["client_id"] do
      blank when blank in [nil, ""] ->
        true

      id ->
        case Integer.parse(to_string(id)) do
          {cid, ""} -> Enum.any?(socket.assigns.clients, &(&1.client_id == cid))
          _ -> false
        end
    end
  end

  defp client_display(%{name: name}) when is_binary(name) and name != "", do: name
  defp client_display(%{email: email}), do: email
  defp client_display(_), do: gettext("Client")

  # Party label for an appointment: a linked client, else the external name.
  defp appt_party_label(%Appointment{client: %{} = client}), do: client_display(client)

  defp appt_party_label(%Appointment{external_client_name: name})
       when is_binary(name) and name != "",
       do: name

  defp appt_party_label(_), do: gettext("Client")

  defp professional_name(%{display_name: name}, _user) when is_binary(name) and name != "",
    do: name

  defp professional_name(_, %{name: name}) when is_binary(name) and name != "", do: name
  defp professional_name(_, _), do: gettext("Your nutritionist")

  defp public_url(%{is_public: true, slug: slug}) when is_binary(slug),
    do: url(~p"/nutritionists/#{slug}")

  defp public_url(_), do: url(~p"/home")

  defp new_appointment_changeset(professional_id, client_id) do
    attrs =
      if client_id,
        do: %{professional_id: professional_id, client_id: client_id},
        else: %{professional_id: professional_id}

    Professionals.change_appointment(%Appointment{}, attrs)
  end

  # Assemble the form's local date + hour/minute selects into UTC scheduled_at /
  # ends_at for storage (times are entered in the professional's local tz).
  defp build_datetimes(params, tz) do
    date_str = Map.get(params, "date", Date.to_iso8601(Date.utc_today()))

    with {:ok, date} <- Date.from_iso8601(date_str),
         {start_h, ""} <- Integer.parse(Map.get(params, "start_hour", "9")),
         {start_m, ""} <- Integer.parse(Map.get(params, "start_minute", "0")),
         {end_h, ""} <- Integer.parse(Map.get(params, "end_hour", "10")),
         {end_m, ""} <- Integer.parse(Map.get(params, "end_minute", "0")),
         {:ok, scheduled_at} <- NaiveDateTime.new(date, Time.new!(start_h, start_m, 0)),
         {:ok, ends_at} <- NaiveDateTime.new(date, Time.new!(end_h, end_m, 0)) do
      params
      |> Map.put("scheduled_at", Mehungry.Time.to_utc(scheduled_at, tz))
      |> Map.put("ends_at", Mehungry.Time.to_utc(ends_at, tz))
      |> Map.drop(["date", "start_hour", "start_minute", "end_hour", "end_minute"])
    else
      _ -> params
    end
  end

  # Mirror the submitted raw date/time inputs back into the form_* assigns so a
  # rejected save keeps the user's picks. Falls back to the current assign when a
  # field is missing or unparseable.
  defp sync_form_fields(socket, params) do
    socket
    |> assign(:form_date, Map.get(params, "date", socket.assigns.form_date))
    |> assign(:form_start_hour, parse_int(params["start_hour"], socket.assigns.form_start_hour))
    |> assign(:form_start_minute, parse_int(params["start_minute"], socket.assigns.form_start_minute))
    |> assign(:form_end_hour, parse_int(params["end_hour"], socket.assigns.form_end_hour))
    |> assign(:form_end_minute, parse_int(params["end_minute"], socket.assigns.form_end_minute))
  end

  defp parse_int(value, fallback) do
    case Integer.parse(to_string(value)) do
      {n, _} -> n
      _ -> fallback
    end
  end

  # The stored appointment is UTC; the edit form shows the professional's local
  # time, so convert before splitting into date + hour/minute.
  defp decompose_appointment(%Appointment{scheduled_at: s, ends_at: e}, tz) do
    start_local = Mehungry.Time.to_local(s, tz)
    end_local = Mehungry.Time.to_local(e || NaiveDateTime.add(s, 3600), tz)
    date_str = start_local |> NaiveDateTime.to_date() |> Date.to_iso8601()
    {date_str, start_local.hour, start_local.minute, end_local.hour, end_local.minute}
  end

  defp calendar_days(month_date) do
    first = %{month_date | day: 1}
    last = Date.end_of_month(first)
    day_of_week = Date.day_of_week(first)
    pad_before = rem(day_of_week - 1, 7)
    start_date = Date.add(first, -pad_before)
    total_days = pad_before + last.day
    num_weeks = ceil(total_days / 7)

    for week <- 0..(num_weeks - 1) do
      for day <- 0..6 do
        Date.add(start_date, week * 7 + day)
      end
    end
  end

  defp hour_options do
    for h <- 6..22, do: {format_time(h, 0), h}
  end

  defp minute_options do
    [{":00", 0}, {":15", 15}, {":30", 30}, {":45", 45}]
  end

  defp format_time(h, m) do
    "#{String.pad_leading(Integer.to_string(h), 2, "0")}:#{String.pad_leading(Integer.to_string(m), 2, "0")}"
  end

  defp initial_client_type(%{external_client_name: name}) when is_binary(name) and name != "",
    do: "external"

  defp initial_client_type(_), do: "internal"

  defp appt_chip_class("requested"),
    do: "bg-amber-600/50 border border-amber-500/40 text-amber-100 hover:bg-amber-500/60"

  defp appt_chip_class("declined"),
    do: "bg-ink-panel2 border border-ink-panel2 text-parchment-dim line-through hover:bg-ink"

  defp appt_chip_class("cancelled"),
    do: "bg-ink-panel2 border border-ink-panel2 text-parchment-dim line-through hover:bg-ink"

  defp appt_chip_class(_accepted),
    do: "bg-basil/20 border border-basil/40 text-basil hover:bg-basil/30"

  # --- Day agenda helpers -------------------------------------------------

  # Appointments on a given date, soonest first. Derived from the already-loaded
  # month window (no extra query); cancelled/declined fall to the bottom visually
  # via their chip class but are still shown so the day reads honestly.
  defp day_appointments(appointments, date) do
    appointments
    |> Enum.filter(fn a -> NaiveDateTime.to_date(a.scheduled_at) == date end)
    |> Enum.sort_by(& &1.scheduled_at, NaiveDateTime)
  end

  defp agenda_hours, do: @agenda_start_hour..(@agenda_end_hour - 1)

  defp agenda_height_px, do: (@agenda_end_hour - @agenda_start_hour) * @hour_px

  # Top/height for an hour gridline row (module attributes aren't reachable as
  # `@...` inside the HEEx template, so compute here).
  defp hour_line_style(hour) do
    "top: #{(hour - @agenda_start_hour) * @hour_px}px; height: #{@hour_px}px;"
  end

  # Absolute top/height/left/width for an appointment block in the agenda column.
  # Vertical position clamps to the visible 06:00–22:00 window; horizontal position
  # divides the column into `lanes` equal tracks so overlapping appointments sit
  # side by side instead of stacking opaquely on top of one another.
  defp appointment_block_style(%Appointment{scheduled_at: s} = appt, lane, lanes) do
    ends_at = appt.ends_at || NaiveDateTime.add(s, 3600)

    top = minutes_from_start(s.hour, s.minute)
    bottom = minutes_from_start(ends_at.hour, ends_at.minute)
    bottom = if bottom <= top, do: top + 30, else: bottom

    top_px = top / 60 * @hour_px
    height_px = max((bottom - top) / 60 * @hour_px, 22)

    lanes = max(lanes, 1)
    width_pct = 100 / lanes
    left_pct = width_pct * lane

    "top: #{Float.round(top_px, 1)}px; height: #{Float.round(height_px, 1)}px; " <>
      "left: calc(#{Float.round(left_pct, 2)}% + 1px); width: calc(#{Float.round(width_pct, 2)}% - 2px);"
  end

  # Lay out a day's appointments into columns ("lanes") so overlapping meetings
  # render side by side. Greedy: each appointment takes the first lane whose last
  # block has already ended; its rendered width is divided by the widest lane
  # count among everything it overlaps. Returns {appointment, lane, lane_count}.
  defp day_appointment_layout(appts) do
    sorted = Enum.sort_by(appts, & &1.scheduled_at, NaiveDateTime)

    {placed, _lane_ends} =
      Enum.reduce(sorted, {[], []}, fn appt, {acc, lane_ends} ->
        s = appt.scheduled_at
        e = appt.ends_at || NaiveDateTime.add(s, 3600)

        free = Enum.find_index(lane_ends, fn le -> NaiveDateTime.compare(le, s) != :gt end)

        {lane, lane_ends} =
          case free do
            nil -> {length(lane_ends), lane_ends ++ [e]}
            i -> {i, List.replace_at(lane_ends, i, e)}
          end

        {acc ++ [{appt, s, e, lane}], lane_ends}
      end)

    Enum.map(placed, fn {appt, s, e, lane} ->
      lane_count =
        placed
        |> Enum.filter(fn {_a, s2, e2, _l} -> intervals_overlap?(s, e, s2, e2) end)
        |> Enum.map(fn {_a, _s, _e, l} -> l end)
        |> Enum.max()
        |> Kernel.+(1)

      {appt, lane, lane_count}
    end)
  end

  defp intervals_overlap?(s1, e1, s2, e2) do
    NaiveDateTime.compare(s1, e2) == :lt and NaiveDateTime.compare(s2, e1) == :lt
  end

  # Weekly availability windows that fall on the selected date, as {start, end}
  # Time tuples. The schema stores day_of_week 0=Sun..6=Sat; Date.day_of_week/1
  # returns 1=Mon..7=Sun, so rem(_, 7) maps Sun(7)->0, Mon(1)->1 … Sat(6)->6.
  defp availability_windows_for(availabilities, date) do
    schema_dow = rem(Date.day_of_week(date), 7)

    availabilities
    |> Enum.filter(&(&1.day_of_week == schema_dow))
    |> Enum.map(&{&1.start_time, &1.end_time})
  end

  # Google busy intervals clipped to the selected date, as {start, end} Time
  # tuples. An interval that spills over the day boundary is clamped to the day.
  defp busy_windows_for(day_busy, date, tz) do
    day_start = NaiveDateTime.new!(date, ~T[00:00:00])
    day_end = NaiveDateTime.new!(date, ~T[23:59:59])

    Enum.map(day_busy, fn b ->
      # Busy intervals are stored UTC; render them on the local agenda.
      starts = b.starts_at |> DateTime.to_naive() |> Mehungry.Time.to_local(tz) |> clamp_naive(day_start, day_end)
      ends = b.ends_at |> DateTime.to_naive() |> Mehungry.Time.to_local(tz) |> clamp_naive(day_start, day_end)
      {NaiveDateTime.to_time(starts), NaiveDateTime.to_time(ends)}
    end)
  end

  defp clamp_naive(naive, min_naive, max_naive) do
    cond do
      NaiveDateTime.compare(naive, min_naive) == :lt -> min_naive
      NaiveDateTime.compare(naive, max_naive) == :gt -> max_naive
      true -> naive
    end
  end

  defp availability_block_style({start_time, end_time}) do
    top = minutes_from_start(start_time.hour, start_time.minute)
    bottom = minutes_from_start(end_time.hour, end_time.minute)

    top_px = top / 60 * @hour_px
    height_px = max((bottom - top) / 60 * @hour_px, 0)

    "top: #{Float.round(top_px, 1)}px; height: #{Float.round(height_px, 1)}px;"
  end

  # Minutes below the agenda's start hour, clamped to the visible window.
  defp minutes_from_start(hour, minute) do
    (hour - @agenda_start_hour) * 60 + minute
    |> max(0)
    |> min((@agenda_end_hour - @agenda_start_hour) * 60)
  end

  # Solid block variant (vs the translucent month chip) for the agenda column.
  defp appt_block_class("requested"),
    do: "bg-amber-600/80 border border-amber-500/60 text-amber-50 hover:bg-amber-500"

  defp appt_block_class(status) when status in ["declined", "cancelled", "no_show"],
    do: "bg-ink-panel2 border border-ink-panel2 text-parchment-dim line-through hover:bg-ink"

  defp appt_block_class(_accepted),
    do: "bg-basil/80 border border-basil text-ink hover:bg-basil"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="profile-form max-w-5xl mx-auto">
      <h1 class="text-2xl font-display font-bold text-parchment mb-6">{gettext("Appointment Calendar")}</h1>

      <!-- Google Calendar connection -->
      <div class="flex items-center justify-between gap-3 bg-ink-panel border border-ink-panel2 rounded-xl px-4 py-3 mb-6">
        <div class="flex items-center gap-2 min-w-0">
          <svg class="w-5 h-5 flex-shrink-0 text-parchment-dim" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
          </svg>
          <%= if @google_connected do %>
            <p class="text-sm text-parchment truncate">
              <span class="text-basil font-medium">{gettext("Google Calendar connected")}</span>
              {gettext("— accepted appointments sync and your busy times block new bookings.")}
            </p>
          <% else %>
            <p class="text-sm text-parchment-dim truncate">
              {gettext("Connect your Google Calendar to auto-add accepted appointments (with a Meet link) and block your busy times.")}
            </p>
          <% end %>
        </div>
        <%= if @google_connected do %>
          <.link
            href={~p"/nutritionist/google-calendar/disconnect"}
            method="delete"
            data-confirm={gettext("Disconnect Google Calendar? Accepted appointments will stop syncing.")}
            class="flex-shrink-0 px-3 py-1.5 rounded-lg bg-ink-panel2 hover:bg-red-700/60 text-parchment-dim hover:text-red-200 text-xs transition"
          >
            {gettext("Disconnect")}
          </.link>
        <% else %>
          <.link
            href={~p"/nutritionist/google-calendar/connect"}
            class="flex-shrink-0 px-3 py-1.5 rounded-lg bg-paprika hover:bg-paprika-soft text-ink text-xs font-medium"
          >
            {gettext("Connect Google Calendar")}
          </.link>
        <% end %>
      </div>

      <!-- Pending requests -->
      <%= if @pending_requests != [] do %>
        <div class="bg-amber-500/10 border border-amber-500/30 rounded-xl p-5 mb-6">
          <h2 class="text-amber-200 font-semibold mb-3">
            {gettext("Pending requests (%{count})", count: length(@pending_requests))}
          </h2>
          <div class="space-y-3">
            <%= for req <- @pending_requests do %>
              <form
                phx-submit="accept_appointment"
                class="flex flex-col sm:flex-row sm:items-center gap-3 bg-ink-panel border border-ink-panel2 rounded-lg p-3"
              >
                <input type="hidden" name="appointment_id" value={req.id} />
                <div class="flex-1 min-w-0">
                  <p class="text-parchment text-sm font-medium truncate">
                    {client_display(req.client)} · {req.title}
                  </p>
                  <p class="text-parchment-dim text-xs">
                    {Calendar.strftime(req.scheduled_at, "%a %b %d, %Y %H:%M")}
                    <%= if req.notes && req.notes != "" do %>
                      · “{req.notes}”
                    <% end %>
                  </p>
                </div>
                <input
                  type="url"
                  name="meeting_url"
                  placeholder={gettext("Video call link (optional)")}
                  class="bg-ink-panel2 border border-ink-panel2 rounded px-2 py-1.5 text-xs text-parchment sm:w-48 focus:outline-none focus:border-paprika"
                />
                <div class="flex gap-2">
                  <button
                    type="submit"
                    class="px-3 py-1.5 rounded-lg bg-paprika hover:bg-paprika-soft text-ink text-xs font-medium"
                  >
                    {gettext("Accept")}
                  </button>
                  <button
                    type="button"
                    phx-click="decline_appointment"
                    phx-value-id={req.id}
                    data-confirm={gettext("Decline this request?")}
                    class="px-3 py-1.5 rounded-lg bg-ink-panel2 hover:bg-red-700/60 text-parchment-dim hover:text-red-200 text-xs transition"
                  >
                    {gettext("Decline")}
                  </button>
                </div>
              </form>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- Month navigation -->
      <div class="flex items-center justify-between mb-4">
        <button
          phx-click="prev_month"
          class="text-parchment-dim hover:text-parchment p-2 rounded-lg hover:bg-ink-panel2 transition"
        >
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
          </svg>
        </button>
        <h2 class="text-parchment font-display font-semibold text-lg">
          {Calendar.strftime(@current_month, "%B %Y")}
        </h2>
        <button
          phx-click="next_month"
          class="text-parchment-dim hover:text-parchment p-2 rounded-lg hover:bg-ink-panel2 transition"
        >
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
          </svg>
        </button>
      </div>

      <!-- Calendar grid -->
      <div class="bg-ink-panel border border-ink-panel2 rounded-xl overflow-hidden">
        <div class="grid grid-cols-7 border-b border-ink-panel2">
          <%= for day <- [gettext("Mon"), gettext("Tue"), gettext("Wed"), gettext("Thu"), gettext("Fri"), gettext("Sat"), gettext("Sun")] do %>
            <div class="py-2 text-center text-xs font-medium text-parchment-dim">{day}</div>
          <% end %>
        </div>

        <%= for week <- calendar_days(@current_month) do %>
          <div class="grid grid-cols-7 border-b border-ink-panel2 last:border-0">
            <%= for day <- week do %>
              <% is_current_month = day.month == @current_month.month

              day_appointments =
                Enum.filter(@appointments, fn a ->
                  NaiveDateTime.to_date(a.scheduled_at) == day
                end) %>
              <div
                class={[
                  "min-h-20 p-2 border-r border-ink-panel2 last:border-0 cursor-pointer hover:bg-ink-panel2/50 transition",
                  not is_current_month && "opacity-40",
                  day == @today && "bg-basil/10"
                ]}
                phx-click="select_date"
                phx-value-date={Date.to_iso8601(day)}
              >
                <p class={[
                  "text-xs font-medium mb-1",
                  day == @today && "text-basil",
                  day != @today && is_current_month && "text-parchment",
                  not is_current_month && "text-parchment-dim"
                ]}>
                  {day.day}
                </p>
                <%= for appt <- day_appointments do %>
                  <div
                    class={[
                      "text-xs rounded px-1.5 py-0.5 mb-0.5 truncate cursor-pointer",
                      appt_chip_class(appt.status)
                    ]}
                    phx-click="edit_appointment"
                    phx-value-id={appt.id}
                    phx-stop-propagation
                  >
                    {appt.title}
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <!-- Day-agenda modal -->
      <.modal :if={@show_day_modal} id="day-agenda-modal" show on_cancel={JS.push("close_day_modal")}>
        <% appts = day_appointments(@appointments, @selected_date)
        windows = availability_windows_for(@availabilities, @selected_date)
        busy_windows = busy_windows_for(@day_busy, @selected_date, @tz) %>
        <!-- Header -->
        <div class="flex items-start justify-between gap-3 mb-4">
          <div>
            <h3 id="day-agenda-modal-title" class="text-parchment font-display font-semibold">
              {Calendar.strftime(@selected_date, "%A, %b %-d, %Y")}
            </h3>
            <p class="text-parchment-dim text-xs mt-0.5">
              {ngettext("%{count} appointment", "%{count} appointments", length(appts), count: length(appts))}
            </p>
          </div>
          <.action type="button" variant={:primary} size={:sm} phx-click="new_appointment" class="mr-6 shrink-0">
            {gettext("+ New")}
          </.action>
        </div>

        <!-- Hourly agenda -->
        <div class="overflow-y-auto" style="max-height: 70vh;">
          <div class="relative" style={"height: #{agenda_height_px()}px;"}>
                <!-- Hour gridlines + labels + clickable empty slots -->
                <%= for hour <- agenda_hours() do %>
                  <div
                    class="absolute left-0 right-0 border-t border-ink-panel2/60 group cursor-pointer hover:bg-ink-panel2/30 transition"
                    style={hour_line_style(hour)}
                    phx-click="new_appointment"
                    phx-value-hour={hour}
                  >
                    <span class="absolute -top-2 left-0 w-12 text-right pr-2 text-[10px] text-parchment-dim select-none">
                      {format_time(hour, 0)}
                    </span>
                  </div>
                <% end %>

                <!-- Availability shading -->
                <%= for window <- windows do %>
                  <div
                    class="absolute left-14 right-2 bg-basil/5 border-l-2 border-basil/40 pointer-events-none rounded-sm"
                    style={availability_block_style(window)}
                  >
                  </div>
                <% end %>

                <!-- Google Calendar busy shading (personal, non-bookable) -->
                <%= for window <- busy_windows do %>
                  <div
                    class="absolute left-14 right-2 bg-ink-panel2/70 border-l-2 border-parchment-dim/40 pointer-events-none rounded-sm overflow-hidden"
                    style={availability_block_style(window)}
                    title={gettext("Busy (Google Calendar)")}
                  >
                    <span class="text-[9px] text-parchment-dim pl-1 select-none">{gettext("Busy")}</span>
                  </div>
                <% end %>

                <!-- Appointment blocks (overlapping ones split into side-by-side lanes) -->
                <div class="absolute left-14 right-2 top-0 bottom-0 pointer-events-none">
                  <%= for {appt, lane, lanes} <- day_appointment_layout(appts) do %>
                    <div
                      class={[
                        "absolute rounded-md px-2 py-1 overflow-hidden cursor-pointer shadow-sm pointer-events-auto",
                        appt_block_class(appt.status)
                      ]}
                      style={appointment_block_style(appt, lane, lanes)}
                      phx-click="edit_appointment"
                      phx-value-id={appt.id}
                      phx-stop-propagation
                    >
                      <p class="text-[11px] font-semibold leading-tight truncate">
                        {Calendar.strftime(appt.scheduled_at, "%H:%M")} · {appt.title}
                      </p>
                      <p class="text-[10px] leading-tight truncate opacity-90">
                        {appt_party_label(appt)}
                      </p>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
      </.modal>

      <!-- Appointment modal -->
      <.modal :if={@show_modal} id="appointment-modal" show on_cancel={JS.push("close_modal")}>
        <h3 id="appointment-modal-title" class="text-parchment font-display font-semibold mb-4">
          {if @editing_appointment, do: gettext("Edit Appointment"), else: gettext("New Appointment")}
        </h3>

        <.form
          :let={f}
          for={@appointment_changeset}
          id="appointment-form"
          phx-submit="save_appointment"
          class="space-y-4"
        >
          <!-- Client selector (internal or external) -->
          <div x-data={"{ clientType: '#{initial_client_type(@editing_appointment)}' }"}>
            <label class="block text-sm text-parchment-dim mb-1">{gettext("Client")}</label>

            <!-- Toggle -->
            <div class="flex gap-1 mb-2 p-0.5 bg-ink rounded-lg w-fit">
              <button
                type="button"
                x-on:click="clientType = 'internal'"
                x-bind:class="clientType === 'internal' ? 'bg-paprika text-ink' : 'text-parchment-dim hover:text-parchment'"
                class="px-3 py-1 rounded-md text-xs font-medium transition"
              >{gettext("M3Hungry Client")}</button>
              <button
                type="button"
                x-on:click="clientType = 'external'"
                x-bind:class="clientType === 'external' ? 'bg-paprika text-ink' : 'text-parchment-dim hover:text-parchment'"
                class="px-3 py-1 rounded-md text-xs font-medium transition"
              >{gettext("External Client")}</button>
            </div>

            <!-- Internal: dropdown of assigned clients -->
            <div x-show="clientType === 'internal'" x-cloak>
              <select
                id="appointment_client_id"
                name="appointment[client_id]"
                x-bind:disabled="clientType !== 'internal'"
                class="w-full bg-ink-panel2 border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm focus:outline-none focus:border-paprika"
              >
                <option value="">{gettext("Select client...")}</option>
                <%= for assignment <- @clients do %>
                  <option
                    value={assignment.client.id}
                    selected={
                      (@editing_appointment &&
                         @editing_appointment.client_id == assignment.client.id) ||
                        @modal_client_id == assignment.client.id
                    }
                  >
                    {assignment.client.name || assignment.client.email}
                  </option>
                <% end %>
              </select>
            </div>

            <!-- External: free-text name -->
            <div x-show="clientType === 'external'" x-cloak>
              <input
                type="text"
                name="appointment[external_client_name]"
                aria-label={gettext("External client name")}
                x-bind:disabled="clientType !== 'external'"
                value={@editing_appointment && @editing_appointment.external_client_name}
                placeholder={gettext("Client name (external)")}
                class="w-full bg-ink-panel2 border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm focus:outline-none focus:border-paprika"
              />
            </div>
          </div>

          <!-- Title -->
          <div>
            <label for="appointment_title" class="block text-sm text-parchment-dim mb-1">{gettext("Title")}</label>
            <.input
              field={f[:title]}
              type="text"
              placeholder={gettext("Initial consultation")}
              class="w-full"
            />
          </div>

          <!-- Date -->
          <div>
            <label for="appointment_date" class="block text-sm text-parchment-dim mb-1">{gettext("Date")}</label>
            <input
              id="appointment_date"
              type="date"
              name="appointment[date]"
              value={@form_date}
              class="w-full bg-ink-panel2 border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm focus:outline-none focus:border-paprika"
            />
          </div>

          <!-- From / Until time row -->
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label for="appointment_start_hour" class="block text-sm text-parchment-dim mb-1">{gettext("From")}</label>
              <div class="flex gap-1">
                <select
                  id="appointment_start_hour"
                  name="appointment[start_hour]"
                  class="flex-1 bg-ink-panel2 border border-ink-panel2 rounded-lg px-2 py-2 text-parchment text-sm focus:outline-none focus:border-paprika"
                >
                  <%= for {label, h} <- hour_options() do %>
                    <option value={h} selected={h == @form_start_hour}>{label}</option>
                  <% end %>
                </select>
                <select
                  name="appointment[start_minute]"
                  aria-label={gettext("Start minute")}
                  class="w-16 bg-ink-panel2 border border-ink-panel2 rounded-lg px-2 py-2 text-parchment text-sm focus:outline-none focus:border-paprika"
                >
                  <%= for {label, m} <- minute_options() do %>
                    <option value={m} selected={m == @form_start_minute}>{label}</option>
                  <% end %>
                </select>
              </div>
            </div>
            <div>
              <label for="appointment_end_hour" class="block text-sm text-parchment-dim mb-1">{gettext("Until")}</label>
              <div class="flex gap-1">
                <select
                  id="appointment_end_hour"
                  name="appointment[end_hour]"
                  class="flex-1 bg-ink-panel2 border border-ink-panel2 rounded-lg px-2 py-2 text-parchment text-sm focus:outline-none focus:border-paprika"
                >
                  <%= for {label, h} <- hour_options() do %>
                    <option value={h} selected={h == @form_end_hour}>{label}</option>
                  <% end %>
                </select>
                <select
                  name="appointment[end_minute]"
                  aria-label={gettext("End minute")}
                  class="w-16 bg-ink-panel2 border border-ink-panel2 rounded-lg px-2 py-2 text-parchment text-sm focus:outline-none focus:border-paprika"
                >
                  <%= for {label, m} <- minute_options() do %>
                    <option value={m} selected={m == @form_end_minute}>{label}</option>
                  <% end %>
                </select>
              </div>
            </div>
          </div>

          <!-- Notes -->
          <div>
            <label for="appointment_notes" class="block text-sm text-parchment-dim mb-1">{gettext("Session notes (optional)")}</label>
            <.input
              field={f[:notes]}
              type="textarea"
              rows="3"
              placeholder={gettext("Notes from the session...")}
              class="w-full"
            />
          </div>

          <!-- Footer actions -->
          <div class="pt-2 flex flex-wrap gap-3">
            <.action
              type="submit"
              variant={:primary}
              phx-disable-with={gettext("Saving...")}
              class="flex-1"
            >
              {gettext("Save Appointment")}
            </.action>
            <%= if @editing_appointment && @editing_appointment.status == "accepted" do %>
              <.action
                type="button"
                variant={:danger}
                phx-click="cancel_appointment_professional"
                phx-value-id={@editing_appointment.id}
                data-confirm={gettext("Cancel this appointment and fully refund the client?")}
              >
                {gettext("Cancel & refund")}
              </.action>
            <% else %>
              <%= if @editing_appointment do %>
                <.action
                  type="button"
                  variant={:danger}
                  phx-click="delete_appointment"
                  phx-value-id={@editing_appointment.id}
                  data-confirm={gettext("Delete this appointment?")}
                >
                  {gettext("Delete")}
                </.action>
              <% end %>
            <% end %>
            <%= if @editing_appointment && @editing_appointment.client_id do %>
              <.action
                type="button"
                variant={:secondary}
                phx-click="log_measurement"
                phx-value-id={@editing_appointment.id}
              >
                {gettext("Log measurement")}
              </.action>
            <% end %>
            <.action type="button" variant={:ghost} phx-click="close_modal">
              {gettext("Close")}
            </.action>
          </div>
        </.form>
      </.modal>

      <.modal
        :if={@show_measurement_modal}
        id="measurement-modal"
        show
        on_cancel={JS.push("close_measurement_modal")}
      >
        <h3 id="measurement-modal-title" class="text-parchment font-display font-semibold mb-4">
          {gettext("Log measurement")}
        </h3>

        <.form
          for={@measurement_form}
          id="measurement-form"
          phx-submit="save_measurement"
          class="space-y-4"
        >
          <p class="text-parchment-dim text-xs">
            {gettext("BMI and BMR are computed automatically from the client's latest intake.")}
          </p>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label for="consultation_note_visit_date" class="block text-sm text-parchment-dim mb-1">{gettext("Visit date")}</label>
              <.input field={@measurement_form[:visit_date]} type="date" />
            </div>
            <div>
              <label for="consultation_note_weight_kg" class="block text-sm text-parchment-dim mb-1">{gettext("Weight (kg)")}</label>
              <.input field={@measurement_form[:weight_kg]} type="number" step="any" />
            </div>
            <div>
              <label for="consultation_note_body_fat_percentage" class="block text-sm text-parchment-dim mb-1">{gettext("Body fat (%)")}</label>
              <.input field={@measurement_form[:body_fat_percentage]} type="number" step="any" />
            </div>
            <div>
              <label for="consultation_note_waist_cm" class="block text-sm text-parchment-dim mb-1">{gettext("Waist (cm)")}</label>
              <.input field={@measurement_form[:waist_cm]} type="number" step="any" />
            </div>
            <div>
              <label for="consultation_note_muscle_mass_kg" class="block text-sm text-parchment-dim mb-1">{gettext("Muscle mass (kg)")}</label>
              <.input field={@measurement_form[:muscle_mass_kg]} type="number" step="any" />
            </div>
          </div>
          <div>
            <label for="consultation_note_body" class="block text-sm text-parchment-dim mb-1">{gettext("Notes (optional)")}</label>
            <.input field={@measurement_form[:body]} type="textarea" rows="2" />
          </div>

          <div class="pt-2 flex gap-3">
            <.action
              type="submit"
              variant={:primary}
              phx-disable-with={gettext("Saving...")}
              class="flex-1"
            >
              {gettext("Save measurement")}
            </.action>
            <.action type="button" variant={:ghost} phx-click="close_measurement_modal">
              {gettext("Close")}
            </.action>
          </div>
        </.form>
      </.modal>
    </div>
    """
  end
end
