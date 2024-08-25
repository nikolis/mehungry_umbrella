defmodule MehungryWeb.NuserLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.NewsLetterFixtures

  @create_attrs %{email: "some email"}
  @update_attrs %{email: "some updated email"}
  @invalid_attrs %{email: nil}

  defp create_nuser(_) do
    nuser = nuser_fixture()
    %{nuser: nuser}
  end

  describe "Index" do
    setup [:create_nuser]

    test "lists all nusers", %{conn: conn, nuser: nuser} do
      {:ok, _index_live, html} = live(conn, ~p"/nusers")

      assert html =~ "Listing Nusers"
      assert html =~ nuser.email
    end

    test "saves new nuser", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/nusers")

      assert index_live |> element("a", "New Nuser") |> render_click() =~
               "New Nuser"

      assert_patch(index_live, ~p"/nusers/new")

      assert index_live
             |> form("#nuser-form", nuser: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#nuser-form", nuser: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/nusers")

      html = render(index_live)
      assert html =~ "Nuser created successfully"
      assert html =~ "some email"
    end

    test "updates nuser in listing", %{conn: conn, nuser: nuser} do
      {:ok, index_live, _html} = live(conn, ~p"/nusers")

      assert index_live |> element("#nusers-#{nuser.id} a", "Edit") |> render_click() =~
               "Edit Nuser"

      assert_patch(index_live, ~p"/nusers/#{nuser}/edit")

      assert index_live
             |> form("#nuser-form", nuser: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#nuser-form", nuser: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/nusers")

      html = render(index_live)
      assert html =~ "Nuser updated successfully"
      assert html =~ "some updated email"
    end

    test "deletes nuser in listing", %{conn: conn, nuser: nuser} do
      {:ok, index_live, _html} = live(conn, ~p"/nusers")

      assert index_live |> element("#nusers-#{nuser.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#nusers-#{nuser.id}")
    end
  end

  describe "Show" do
    setup [:create_nuser]

    test "displays nuser", %{conn: conn, nuser: nuser} do
      {:ok, _show_live, html} = live(conn, ~p"/nusers/#{nuser}")

      assert html =~ "Show Nuser"
      assert html =~ nuser.email
    end

    test "updates nuser within modal", %{conn: conn, nuser: nuser} do
      {:ok, show_live, _html} = live(conn, ~p"/nusers/#{nuser}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Nuser"

      assert_patch(show_live, ~p"/nusers/#{nuser}/show/edit")

      assert show_live
             |> form("#nuser-form", nuser: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#nuser-form", nuser: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/nusers/#{nuser}")

      html = render(show_live)
      assert html =~ "Nuser updated successfully"
      assert html =~ "some updated email"
    end
  end
end
