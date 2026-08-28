defmodule Mehungry.Professionals.ICS do
  @moduledoc """
  Minimal RFC-5545 VCALENDAR/VEVENT builder for appointment invitations.

  Appointment datetimes are stored as naive UTC, so events are emitted in UTC
  (`...Z`). The generated string is attached to the acceptance email as
  `text/calendar` so the recipient can add it to Google/Apple/Outlook calendars.
  """

  alias Mehungry.Professionals.Appointment

  @doc """
  Build an `.ics` string for an appointment. Options:

    * `:organizer_email` — defaults to the noreply address
    * `:attendee_email` — the client's email (adds an ATTENDEE line)
    * `:summary` — event title (defaults to the appointment title)
    * `:description` — extra body text
  """
  def build(%Appointment{} = appointment, opts \\ []) do
    organizer_email = Keyword.get(opts, :organizer_email, "noreply@m3hungry.com")
    summary = Keyword.get(opts, :summary) || appointment.title || "Nutrition Consultation"

    lines =
      [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Mehungry//Appointments//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:REQUEST",
        "BEGIN:VEVENT",
        "UID:appointment-#{appointment.id}@m3hungry.com",
        "DTSTAMP:#{to_ics_utc(NaiveDateTime.utc_now())}",
        "DTSTART:#{to_ics_utc(appointment.scheduled_at)}",
        "DTEND:#{to_ics_utc(appointment.ends_at || default_end(appointment))}",
        "SUMMARY:#{escape(summary)}",
        description_line(appointment, opts),
        location_line(appointment),
        url_line(appointment),
        "ORGANIZER:mailto:#{organizer_email}",
        attendee_line(Keyword.get(opts, :attendee_email)),
        "STATUS:CONFIRMED",
        "END:VEVENT",
        "END:VCALENDAR"
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(lines, "\r\n")
  end

  defp default_end(%Appointment{scheduled_at: scheduled_at}),
    do: NaiveDateTime.add(scheduled_at, 60 * 60, :second)

  defp to_ics_utc(%NaiveDateTime{} = ndt) do
    ndt
    |> NaiveDateTime.truncate(:second)
    |> Calendar.strftime("%Y%m%dT%H%M%SZ")
  end

  defp description_line(appointment, opts) do
    parts =
      [Keyword.get(opts, :description), appointment.notes, appointment.meeting_url]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))

    case parts do
      [] -> nil
      _ -> "DESCRIPTION:#{escape(Enum.join(parts, "\\n"))}"
    end
  end

  defp location_line(%Appointment{meeting_url: url}) when is_binary(url) and url != "",
    do: "LOCATION:#{escape(url)}"

  defp location_line(_), do: nil

  defp url_line(%Appointment{meeting_url: url}) when is_binary(url) and url != "",
    do: "URL:#{escape(url)}"

  defp url_line(_), do: nil

  defp attendee_line(nil), do: nil
  defp attendee_line(""), do: nil

  defp attendee_line(email),
    do: "ATTENDEE;RSVP=TRUE;CN=#{escape(email)}:mailto:#{email}"

  # RFC-5545 text escaping.
  defp escape(text) do
    text
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace(";", "\\;")
    |> String.replace(",", "\\,")
    |> String.replace("\n", "\\n")
  end
end
