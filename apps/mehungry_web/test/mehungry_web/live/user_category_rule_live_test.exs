defmodule MehungryWeb.UserCategoryRuleLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  @create_attrs %{}
  @update_attrs %{}
  @invalid_attrs %{}

  defp create_user_category_rule(_) do
    user_category_rule = user_category_rule_fixture()
    %{user_category_rule: user_category_rule}
  end

  describe "Index" do
    setup [:create_user_category_rule]

    test "lists all user_category_rules", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/user_category_rules")

      assert html =~ "Listing User category rules"
    end

    test "saves new user_category_rule", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/user_category_rules")

      assert index_live |> element("a", "New User category rule") |> render_click() =~
               "New User category rule"

      assert_patch(index_live, ~p"/user_category_rules/new")

      assert index_live
             |> form("#user_category_rule-form", user_category_rule: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#user_category_rule-form", user_category_rule: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/user_category_rules")

      html = render(index_live)
      assert html =~ "User category rule created successfully"
    end

    test "updates user_category_rule in listing", %{
      conn: conn,
      user_category_rule: user_category_rule
    } do
      {:ok, index_live, _html} = live(conn, ~p"/user_category_rules")

      assert index_live
             |> element("#user_category_rules-#{user_category_rule.id} a", "Edit")
             |> render_click() =~
               "Edit User category rule"

      assert_patch(index_live, ~p"/user_category_rules/#{user_category_rule}/edit")

      assert index_live
             |> form("#user_category_rule-form", user_category_rule: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#user_category_rule-form", user_category_rule: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/user_category_rules")

      html = render(index_live)
      assert html =~ "User category rule updated successfully"
    end

    test "deletes user_category_rule in listing", %{
      conn: conn,
      user_category_rule: user_category_rule
    } do
      {:ok, index_live, _html} = live(conn, ~p"/user_category_rules")

      assert index_live
             |> element("#user_category_rules-#{user_category_rule.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#user_category_rules-#{user_category_rule.id}")
    end
  end

  describe "Show" do
    setup [:create_user_category_rule]

    test "displays user_category_rule", %{conn: conn, user_category_rule: user_category_rule} do
      {:ok, _show_live, html} = live(conn, ~p"/user_category_rules/#{user_category_rule}")

      assert html =~ "Show User category rule"
    end

    test "updates user_category_rule within modal", %{
      conn: conn,
      user_category_rule: user_category_rule
    } do
      {:ok, show_live, _html} = live(conn, ~p"/user_category_rules/#{user_category_rule}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit User category rule"

      assert_patch(show_live, ~p"/user_category_rules/#{user_category_rule}/show/edit")

      assert show_live
             |> form("#user_category_rule-form", user_category_rule: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#user_category_rule-form", user_category_rule: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/user_category_rules/#{user_category_rule}")

      html = render(show_live)
      assert html =~ "User category rule updated successfully"
    end
  end
end
