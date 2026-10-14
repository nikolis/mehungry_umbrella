defmodule MehungryWeb.PinterestComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MehungryWeb.PinterestComponents

  describe "board_card/1" do
    test "renders name, pin count, privacy badge and cover image" do
      board = %{
        "id" => "b1",
        "name" => "Weeknight Dinners",
        "pin_count" => 12,
        "privacy" => "PUBLIC",
        "media" => %{"image_cover_url" => "https://example.test/cover.jpg"}
      }

      html = render_component(&PinterestComponents.board_card/1, board: board, selected: false)

      assert html =~ "Weeknight Dinners"
      assert html =~ "12 pins"
      assert html =~ "Public"
      assert html =~ "https://example.test/cover.jpg"
    end

    test "falls back to an icon when there is no cover and marks selection" do
      board = %{"id" => "b1", "name" => "Secrets", "pin_count" => 1, "privacy" => "SECRET"}

      html = render_component(&PinterestComponents.board_card/1, board: board, selected: true)

      assert html =~ "Secrets"
      assert html =~ "1 pin"
      assert html =~ "Secret"
      # selected highlight ring
      assert html =~ "ring-paprika"
      refute html =~ "<img"
    end
  end

  describe "board_form/1" do
    test "renders the create form with an in-flight state and surfaces errors" do
      html = render_component(&PinterestComponents.board_form/1, target: nil, error: "Name taken")

      assert html =~ ~s(phx-submit="create_pinterest_board")
      assert html =~ ~s(name="board[name]")
      assert html =~ "phx-disable-with"
      assert html =~ "Name taken"
    end
  end
end
