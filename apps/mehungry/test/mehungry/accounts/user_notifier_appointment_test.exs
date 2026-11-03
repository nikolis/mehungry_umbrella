defmodule Mehungry.Accounts.UserNotifierAppointmentTest do
  @moduledoc """
  The appointment emails are localized to the recipient's language via an
  explicit `locale` arg (the core app has no Gettext backend). These assert the
  subject + body switch between English and Greek, and that the `.ics` calendar
  summary follows suit.
  """
  use ExUnit.Case, async: true

  alias Mehungry.Accounts.UserNotifier
  alias Mehungry.Accounts.User
  alias Mehungry.Professionals.Appointment

  defp appointment do
    %Appointment{
      id: 1,
      scheduled_at: ~N[2026-01-05 14:00:00],
      ends_at: ~N[2026-01-05 15:00:00],
      notes: nil,
      meeting_url: nil,
      title: "Consultation",
      client: %User{id: 1, email: "client@example.com"},
      professional: %User{id: 2, email: "pro@example.com"}
    }
  end

  describe "deliver_appointment_accepted/4" do
    test "English by default" do
      {:ok, email} =
        UserNotifier.deliver_appointment_accepted(appointment(), "Dr Smith", "https://x", "en")

      assert email.subject == "Your Mehungry appointment is confirmed"
      assert email.html_body =~ "Your appointment with"
      assert email.html_body =~ "Monday 5 January 2026"
    end

    test "Greek when locale is el (subject, body, date, and .ics summary)" do
      {:ok, email} =
        UserNotifier.deliver_appointment_accepted(appointment(), "Dr Smith", "https://x", "el")

      assert email.subject == "Το ραντεβού σας στο Mehungry επιβεβαιώθηκε"
      assert email.html_body =~ "Το ραντεβού σας με τον/την"
      assert email.html_body =~ "Δευτέρα 5 Ιανουαρίου 2026"

      ics = Enum.find(email.attachments, &(&1.filename == "appointment.ics"))
      assert ics
      assert ics.data =~ "SUMMARY:Συνεδρία με Dr Smith"
    end
  end

  describe "deliver_appointment_requested/4" do
    test "localizes subject to Greek" do
      {:ok, email} =
        UserNotifier.deliver_appointment_requested(appointment(), "Maria", "https://x", "el")

      assert email.subject == "Νέο αίτημα ραντεβού στο Mehungry"
      assert email.html_body =~ "ζήτησε ραντεβού"
    end
  end
end
