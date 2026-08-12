defmodule MehungryWeb.S3BrowserLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  alias Mehungry.FoodData.Usda.SeedFiles

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    %{conn: log_in_user(conn, admin)}
  end

  test "renders the browser with the empty prompt for an admin", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/professional/files")

    assert html =~ "AWS S3 Browser"
    assert html =~ "Enter a bucket name"
  end

  test "a seed_file broadcast for another bucket is ignored without crashing", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/professional/files")

    # Simulate a live status update arriving from a running import job for a
    # bucket the view is not currently browsing (nothing listed yet). handle_info
    # must accept the message and leave the (empty) status summary untouched.
    seed_file = SeedFiles.upsert_pending("some-bucket", "foods/a.json")
    send(view.pid, {:seed_file, seed_file})

    html = render(view)
    # Still alive, and the seed-status summary stays hidden for the empty bucket.
    assert html =~ "AWS S3 Browser"
    refute html =~ "Seed status:"
  end

  test "a processing signal for an unlisted key is buffered-and-ignored without crashing",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/professional/files")

    # The lightweight processing signal must be tolerated even when the key isn't
    # on the current page (nothing listed): the guard drops it, and a manual flush
    # must not crash on the empty buffer either.
    send(view.pid, {:seed_file_processing, "some-bucket", "foods/a.json"})
    send(view.pid, :flush_processing)

    assert render(view) =~ "AWS S3 Browser"
  end
end
