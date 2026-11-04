defmodule MehungryWeb.PublicNutritionistLiveTest do
  @moduledoc """
  The public, SEO-indexed nutritionist directory + profile + booking flow — the
  product's primary-audience discovery surface (`/nutritionists`,
  `/nutritionists/:slug`). Guards:

    * the directory lists public profiles, hides private ones, filters by city;
    * the profile's **synchronous dead render** carries the bio/city + the
      `LocalBusiness`/`Person` JSON-LD Googlebot indexes (the local-intent SEO
      the feature exists for — see `professional_profiles.md`);
    * the request → accept booking wizard: logged-out visitors are sent to log
      in, logged-in visitors can request an open slot, and a slot taken out from
      under them surfaces a friendly error instead of a crash.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.{Professionals, Repo}

  defp public_profile(attrs) do
    user = Mehungry.AccountsFixtures.user_fixture()

    {:ok, profile} =
      %{
        user_id: user.id,
        specialization: "Clinical Dietitian",
        display_name: "Maria Papadaki",
        city: "Rethymno",
        bio: "Twenty years helping families in Crete eat well.",
        is_public: true
      }
      |> Map.merge(attrs)
      |> Professionals.create_professional_profile()

    {user, profile}
  end

  # A full week of 09:00–11:00 availability → future 60-min slots every day.
  defp with_availability(user) do
    rows =
      for dow <- 0..6, do: %{day_of_week: dow, start_time: ~T[09:00:00], end_time: ~T[11:00:00]}

    {:ok, _} = Professionals.replace_availabilities(user.id, rows)
    user
  end

  describe "/nutritionists directory" do
    test "lists public profiles and hides private ones", %{conn: conn} do
      public_profile(%{display_name: "Public Maria", city: "Rethymno"})
      public_profile(%{display_name: "Hidden Nikos", city: "Rethymno", is_public: false})

      {:ok, _view, html} = live(conn, ~p"/nutritionists")

      assert html =~ "Public Maria"
      refute html =~ "Hidden Nikos"
    end

    test "filters by city (local-intent query)", %{conn: conn} do
      public_profile(%{display_name: "Rethymno Person", city: "Rethymno"})
      public_profile(%{display_name: "Athens Person", city: "Athens"})

      {:ok, _view, html} = live(conn, ~p"/nutritionists?city=Athens")

      assert html =~ "Athens Person"
      refute html =~ "Rethymno Person"
      assert html =~ "Nutritionists in Athens"
    end

    test "the filter form patches the URL and re-queries", %{conn: conn} do
      public_profile(%{display_name: "Rethymno Person", city: "Rethymno"})
      public_profile(%{display_name: "Athens Person", city: "Athens"})

      {:ok, view, _html} = live(conn, ~p"/nutritionists")

      html =
        view
        |> element("form[phx-change=filter]")
        |> render_change(%{"city" => "Athens", "q" => ""})

      assert_patched(view, ~p"/nutritionists?city=Athens")
      assert html =~ "Athens Person"
      refute html =~ "Rethymno Person"
    end

    test "shows an empty state when nothing matches", %{conn: conn} do
      public_profile(%{display_name: "Someone", city: "Rethymno"})

      {:ok, _view, html} = live(conn, ~p"/nutritionists?city=Nowhere")

      assert html =~ "No nutritionists found"
    end

    test "dead render carries ItemList JSON-LD for crawlers", %{conn: conn} do
      public_profile(%{display_name: "SEO Maria"})

      body = conn |> get(~p"/nutritionists") |> html_response(200)

      assert body =~ ~s("@type":"ItemList")
      assert body =~ "SEO Maria"
    end
  end

  describe "/nutritionists/:slug profile" do
    test "synchronous dead render carries bio/city + LocalBusiness & Person JSON-LD",
         %{conn: conn} do
      {_user, profile} =
        public_profile(%{
          display_name: "Maria Papadaki",
          specialization: "Clinical Dietitian",
          city: "Rethymno",
          bio: "Caring dietitian in Crete."
        })

      body = conn |> get(~p"/nutritionists/#{profile.slug}") |> html_response(200)

      assert body =~ "Maria Papadaki"
      assert body =~ "Caring dietitian in Crete."
      assert body =~ "Rethymno"
      assert body =~ ~s("@type":"LocalBusiness")
      assert body =~ ~s("@type":"Person")
    end

    test "an unknown slug redirects to the directory", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/nutritionists"}}} =
               live(conn, ~p"/nutritionists/no-such-nutritionist")
    end
  end

  describe "booking wizard" do
    setup do
      {user, profile} = public_profile(%{})
      with_availability(user)
      %{profile: profile}
    end

    test "a logged-out visitor is prompted to log in", %{conn: conn, profile: profile} do
      {:ok, _view, html} = live(conn, ~p"/nutritionists/#{profile.slug}")

      assert html =~ "Request an appointment"
      # ("You'll be asked to log in to confirm." — apostrophe is HTML-escaped)
      assert html =~ "asked to log in to confirm"

      # The booking wizard offers a log-in CTA rather than a confirm form.
      assert html =~ "Log in to continue"
      assert html =~ ~r/href="[^"]*\/users\/log_in"/
    end

    test "a logged-in visitor can request an open slot", %{conn: conn, profile: profile} do
      client = Mehungry.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, client)

      {:ok, view, _html} = live(conn, ~p"/nutritionists/#{profile.slug}")

      today = Date.utc_today()
      [slot | _] = Professionals.available_slots(profile.user_id, today, Date.add(today, 30))

      select_date(view, slot)
      select_slot(view, slot)
      html = confirm_booking(view, "Looking forward to it")

      assert html =~ "Request sent!"

      appt =
        Repo.get_by(Professionals.Appointment,
          professional_id: profile.user_id,
          client_id: client.id
        )

      assert appt.status == "requested"
      assert appt.scheduled_at == slot
    end

    test "the cancellation-policy notice shows at the paid-booking confirm step", %{
      conn: conn,
      profile: profile
    } do
      # Payments live + a priced service → the policy notice must appear before Confirm.
      prev = Application.get_env(:mehungry, :consultation_payments_enabled)
      Application.put_env(:mehungry, :consultation_payments_enabled, true)

      on_exit(fn ->
        if is_nil(prev),
          do: Application.delete_env(:mehungry, :consultation_payments_enabled),
          else: Application.put_env(:mehungry, :consultation_payments_enabled, prev)
      end)

      {:ok, _service} =
        Professionals.create_service(%{
          professional_id: profile.user_id,
          kind: "session",
          name: "Initial consultation",
          price_cents: 5000,
          currency: "eur",
          duration_minutes: 60
        })

      client = Mehungry.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, client)

      {:ok, view, _html} = live(conn, ~p"/nutritionists/#{profile.slug}")

      service = hd(Professionals.list_active_services(profile.user_id))

      view
      |> element(
        ~s|button[phx-click="select_booking_service"][phx-value-id="#{service.id}"]|
      )
      |> render_click()

      today = Date.utc_today()
      [slot | _] = Professionals.available_slots(profile.user_id, today, Date.add(today, 30))

      select_date(view, slot)
      html = select_slot(view, slot)

      assert html =~ "authorised now"
      assert html =~ "cancellation"
      # Thresholds interpolated from config (24h / 4h) so copy can't drift.
      assert html =~ "full refund 24h+ before"
      assert html =~ ~r/href="[^"]*\/terms"/
    end

    test "a slot taken before confirm surfaces a friendly error", %{conn: conn, profile: profile} do
      client = Mehungry.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, client)

      {:ok, view, _html} = live(conn, ~p"/nutritionists/#{profile.slug}")

      today = Date.utc_today()
      [slot | _] = Professionals.available_slots(profile.user_id, today, Date.add(today, 30))

      select_date(view, slot)
      select_slot(view, slot)

      # A concurrent visitor grabs the same slot before this one confirms.
      other = Mehungry.AccountsFixtures.user_fixture()
      {:ok, _} = Professionals.request_appointment(profile.user_id, other.id, slot, title: "C")

      html = confirm_booking(view, "")

      assert html =~ "just taken"
    end

    # The booking wizard is a LiveComponent, so events must be driven through the
    # DOM (so `phx-target` routes them to the component, not the root LiveView).
    defp select_date(view, slot) do
      date = slot |> NaiveDateTime.to_date() |> Date.to_iso8601()

      view
      |> element(~s|button[phx-click="select_booking_date"][phx-value-date="#{date}"]|)
      |> render_click()
    end

    defp select_slot(view, slot) do
      at = NaiveDateTime.to_iso8601(slot)

      view
      |> element(~s|button[phx-click="select_booking_slot"][phx-value-at="#{at}"]|)
      |> render_click()
    end

    defp confirm_booking(view, notes) do
      view
      |> element(~s|form[phx-submit="confirm_booking"]|)
      |> render_submit(%{"notes" => notes})
    end
  end
end
