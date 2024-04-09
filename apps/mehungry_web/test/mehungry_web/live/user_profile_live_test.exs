defmodule MehungryWeb.UserProfileLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures

  @create_attrs %{alias: "some alias", intro: "some intro"}
  @update_attrs %{alias: "some updated alias", intro: "some updated intro"}
  @invalid_attrs %{alias: nil, intro: nil}

  defp create_user_profile(conn) do
    _rest = %{user: user, conn: conn} = register_and_log_in_user(conn)

    user_profile = user_profile_fixture(%{user_id: user.id})
    %{user_profile: user_profile, user: user, conn: conn}
  end

  describe "Index" do
    setup [:create_user_profile]

    test "lists all user_profiles", %{conn: conn, user_profile: user_profile, user: user} do
      {:ok, _index_live, html} = live(conn, ~p"/profile")

      assert html =~ "Edit Profile"
      assert html =~ "Share Profile"
      assert html =~ user_profile.alias
      assert html =~ user.email
    end

    test "profile page listing of created should appear when existing", %{conn: conn, user: user} do
      recipe1 = recipe_fixture(user)
      recipe2 = recipe_fixture(user)

      {:ok, _index_live, html} = live(conn, Routes.profile_index_path(conn, :index))
      assert html =~ recipe1.title
      assert html =~ recipe2.title
    end

    test "Edit User Profile", %{conn: conn, user_profile: user_profile} do
      {:ok, index_live, _html} = live(conn, ~p"/profile")

      assert index_live
             |> element("a", "Edit Profile")
             |> render_click() =~
               "Edit Profile"

      assert_patch(index_live, ~p"/profile/edit")

      # assert index_live
      # |> form("#user_profile-form", user_profile: @invalid_attrs)
      # |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#user_profile-form", user_profile: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/profile")

      html = render(index_live)
      assert html =~ "User profile updated successfully"
      assert html =~ "some updated alias"
    end
  end
end
