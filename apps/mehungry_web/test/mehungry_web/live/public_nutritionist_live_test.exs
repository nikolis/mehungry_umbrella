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
    rows = for dow <- 0..6, do: %{day_of_week: dow, start_time: ~T[09:00:00], end_time: ~T[11:00:00]}
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
      {:ok, view, html} = live(conn, ~p"/nutritionists/#{profile.slug}")

      assert html =~ "Request an appointment"
      # ("You'll be asked to log in to confirm." — apostrophe is HTML-escaped)
      assert html =~ "asked to log in to confirm"

      # Confirming without a session is refused and routed to the login page.
      assert {:error, {:redirect, %{to: "/users/log_in"}}} =
               render_click(view, "confirm_booking", %{"notes" => ""})
    end

    test "a logged-in visitor can request an open slot", %{conn: conn, profile: profile} do
      client = Mehungry.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, client)

      {:ok, view, _html} = live(conn, ~p"/nutritionists/#{profile.slug}")

      today = Date.utc_today()
      [slot | _] = Professionals.available_slots(profile.user_id, today, Date.add(today, 30))

      render_click(view, "select_booking_date", %{
        "date" => slot |> NaiveDateTime.to_date() |> Date.to_iso8601()
      })

      render_click(view, "select_booking_slot", %{"at" => NaiveDateTime.to_iso8601(slot)})
      html = render_submit(view, "confirm_booking", %{"notes" => "Looking forward to it"})

      assert html =~ "Request sent!"

      appt =
        Repo.get_by(Professionals.Appointment,
          professional_id: profile.user_id,
          client_id: client.id
        )

      assert appt.status == "requested"
      assert appt.scheduled_at == slot
    end

    test "a slot taken before confirm surfaces a friendly error", %{conn: conn, profile: profile} do
      client = Mehungry.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, client)

      {:ok, view, _html} = live(conn, ~p"/nutritionists/#{profile.slug}")

      today = Date.utc_today()
      [slot | _] = Professionals.available_slots(profile.user_id, today, Date.add(today, 30))

      render_click(view, "select_booking_date", %{
        "date" => slot |> NaiveDateTime.to_date() |> Date.to_iso8601()
      })

      render_click(view, "select_booking_slot", %{"at" => NaiveDateTime.to_iso8601(slot)})

      # A concurrent visitor grabs the same slot before this one confirms.
      other = Mehungry.AccountsFixtures.user_fixture()
      {:ok, _} = Professionals.request_appointment(profile.user_id, other.id, slot, title: "C")

      html = render_submit(view, "confirm_booking", %{"notes" => ""})

      assert html =~ "just taken"
    end
  end
end
