defmodule MehungryWeb.BlueprintLiveTest do
  @moduledoc """
  The public blueprint surface: preview page (OG + content), the browse toggle,
  saving to the profile, and nutritionist-only gating of the authoring section.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.MealBlueprints
  alias Mehungry.Subscriptions

  defp public_blueprint(name \\ "Mediterranean Reset") do
    owner = Mehungry.AccountsFixtures.user_fixture(%{name: "Dr. Nutri"})
    {:ok, _} = Subscriptions.upsert_subscription(owner.id, %{tier: "pro", status: "active"})

    {:ok, bp} =
      MealBlueprints.create_blueprint(MealBlueprints.default_blueprint_attrs(owner.id, name))

    {:ok, public} =
      MealBlueprints.update_blueprint(MealBlueprints.get_blueprint!(owner.id, bp.id), %{
        visibility: "public",
        description: "A calming 7-day reset."
      })

    %{owner: owner, blueprint: public}
  end

  describe "public preview /blueprints/:slug" do
    test "renders a public blueprint with OG meta for anonymous visitors", %{conn: conn} do
      %{blueprint: bp} = public_blueprint()

      conn = get(conn, ~p"/blueprints/#{bp.slug}")
      html = html_response(conn, 200)

      assert html =~ "Mediterranean Reset"
      assert html =~ "A calming 7-day reset."
      # Open Graph card content is in the dead render for Facebook.
      assert html =~ ~s(property="og:title")
      assert html =~ "Mediterranean Reset — Meal Blueprint"
      # Share-to-Facebook link is present and well-formed.
      assert html =~ "facebook.com/sharer/sharer.php"
    end

    test "a private blueprint 404s", %{conn: conn} do
      owner = Mehungry.AccountsFixtures.user_fixture()

      {:ok, bp} =
        MealBlueprints.create_blueprint(
          MealBlueprints.default_blueprint_attrs(owner.id, "Secret")
        )

      # give it a slug without publishing
      {:ok, bp} =
        MealBlueprints.update_blueprint(MealBlueprints.get_blueprint!(owner.id, bp.id), %{
          description: "x"
        })

      assert_raise Ecto.NoResultsError, fn ->
        get(conn, ~p"/blueprints/#{bp.slug || "missing"}")
      end
    end

    test "a logged-in visitor can save the blueprint", %{conn: conn} do
      %{blueprint: bp} = public_blueprint("Save Me")
      user = Mehungry.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      {:ok, live, _html} = live(conn, ~p"/blueprints/#{bp.slug}")
      render_click(element(live, "button[phx-click='toggle_save']"))

      assert MealBlueprints.blueprint_saved?(user.id, bp.id)
    end
  end

  describe "browse toggle" do
    test "switching to blueprints shows public blueprint cards and title search", %{conn: conn} do
      %{blueprint: _bp} = public_blueprint("Keto Kickstart")

      {:ok, live, _html} = live(conn, ~p"/browse")

      html = render_click(element(live, "button[phx-value-mode='blueprints']"))
      assert html =~ "Keto Kickstart"

      # Title search filters.
      html =
        render_submit(element(live, "form[phx-submit='search_blueprints']"), %{
          "query" => "nomatch"
        })

      refute html =~ "Keto Kickstart"
    end
  end

  describe "profile saved-blueprints tab" do
    test "lists saved blueprints and can unsave", %{conn: conn} do
      %{blueprint: bp} = public_blueprint("Profile Saved")
      user = Mehungry.AccountsFixtures.user_fixture()
      {:ok, _} = MealBlueprints.save_blueprint_for_user(user.id, bp.id)
      conn = log_in_user(conn, user)

      {:ok, live, html} = live(conn, ~p"/profile?#{[tab: "saved_blueprints"]}")
      assert html =~ "Profile Saved"

      render_click(element(live, "button[phx-click='unsave-blueprint'][phx-value-id='#{bp.id}']"))
      refute MealBlueprints.blueprint_saved?(user.id, bp.id)
    end
  end

  describe "nutritionist gating" do
    test "a non-nutritionist is redirected away from authoring", %{conn: conn} do
      user = Mehungry.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/nutritionist/blueprints")
      refute to =~ "/nutritionist/blueprints"
    end
  end
end
