defmodule MehungryWeb.ProfilePageLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures

  describe "Index Test" do
    setup [:register_and_log_in_user]

    test "profile page user created recipes appear properly", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, Routes.profile_index_path(conn, :index))
      assert html =~ "Saved recipes"
      assert html =~ "Created recipes"
      assert html =~ "Edit Profile"
      assert html =~ "Share Profile"
    end

    test "profile page listing of created should appear when existing", %{conn: conn, user: user} do
      recipe1 = recipe_fixture(user)
      recipe2 = recipe_fixture(user)

      {:ok, _index_live, html} = live(conn, Routes.profile_index_path(conn, :index))
      assert html =~ recipe1.title
      assert html =~ recipe2.title
    end
  end
end
