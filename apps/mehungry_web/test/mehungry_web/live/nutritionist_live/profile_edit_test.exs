defmodule MehungryWeb.NutritionistLive.ProfileEditTest do
  @moduledoc """
  Tests for the nutritionist profile editor (`/nutritionist/profile`), focused on
  the professional-photo picker: it renders the uploader, shows the current
  photo, and the Remove-photo flow clears `photo_url` on save.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.{Professionals, Subscriptions}

  setup %{conn: conn} do
    nutritionist = Mehungry.AccountsFixtures.user_fixture()
    {:ok, _} = Subscriptions.grant_nutritionist(nutritionist.id)
    %{conn: log_in_user(conn, nutritionist), nutritionist: nutritionist}
  end

  defp create_profile(user_id, attrs \\ %{}) do
    {:ok, profile} =
      Professionals.create_professional_profile(
        Map.merge(
          %{
            user_id: user_id,
            display_name: "Dr. Test",
            specialization: "Clinical",
            city: "Athens",
            bio: "Experienced clinical dietitian helping clients eat well."
          },
          attrs
        )
      )

    profile
  end

  test "the editor renders the photo uploader", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/nutritionist/profile")

    assert html =~ "Profile photo"
    # the live_file_input is present
    assert html =~ ~s(type="file")
  end

  test "an existing photo is shown and offers removal", %{conn: conn, nutritionist: nutritionist} do
    create_profile(nutritionist.id, %{photo_url: "https://example.com/storage/profile_photos/a.jpg"})

    {:ok, _view, html} = live(conn, "/nutritionist/profile")

    assert html =~ "https://example.com/storage/profile_photos/a.jpg"
    assert html =~ "Remove photo"
  end

  test "no photo falls back to the display-name initial, no Remove action", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/nutritionist/profile")

    refute html =~ "Remove photo"
  end

  test "Remove photo then save clears photo_url", %{conn: conn, nutritionist: nutritionist} do
    create_profile(nutritionist.id, %{photo_url: "https://example.com/storage/profile_photos/a.jpg"})

    {:ok, view, _html} = live(conn, "/nutritionist/profile")

    # Arm removal, then confirm the pending-removal notice appears.
    html = view |> element("button", "Remove photo") |> render_click()
    assert html =~ "removed when you save"

    view
    |> form("form.profile-form",
      professional_profile: %{"display_name" => "Dr. Test", "specialization" => "Clinical"}
    )
    |> render_submit()

    assert Professionals.get_professional_profile(nutritionist.id).photo_url == nil
  end

  test "Remove photo can be undone before saving", %{conn: conn, nutritionist: nutritionist} do
    create_profile(nutritionist.id, %{photo_url: "https://example.com/storage/profile_photos/a.jpg"})

    {:ok, view, _html} = live(conn, "/nutritionist/profile")

    view |> element("button", "Remove photo") |> render_click()
    html = view |> element("button", "Keep current photo") |> render_click()

    # Back to showing the photo + the Remove action, no pending-removal notice.
    assert html =~ "https://example.com/storage/profile_photos/a.jpg"
    refute html =~ "removed when you save"
  end
end
