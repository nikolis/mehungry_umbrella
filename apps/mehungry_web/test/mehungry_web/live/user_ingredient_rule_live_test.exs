defmodule MehungryWeb.UserIngredientRuleLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  @create_attrs %{}
  @update_attrs %{}
  @invalid_attrs %{}

  defp create_user_ingredient_rule(_) do
    user_ingredient_rule = user_ingredient_rule_fixture()
    %{user_ingredient_rule: user_ingredient_rule}
  end

  describe "Index" do
    setup [:create_user_ingredient_rule]

    test "lists all user_ingredient_rules", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/user_ingredient_rules")

      assert html =~ "Listing User ingredient rules"
    end

    test "saves new user_ingredient_rule", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/user_ingredient_rules")

      assert index_live |> element("a", "New User ingredient rule") |> render_click() =~
               "New User ingredient rule"

      assert_patch(index_live, ~p"/user_ingredient_rules/new")

      assert index_live
             |> form("#user_ingredient_rule-form", user_ingredient_rule: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#user_ingredient_rule-form", user_ingredient_rule: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/user_ingredient_rules")

      html = render(index_live)
      assert html =~ "User ingredient rule created successfully"
    end

    test "updates user_ingredient_rule in listing", %{
      conn: conn,
      user_ingredient_rule: user_ingredient_rule
    } do
      {:ok, index_live, _html} = live(conn, ~p"/user_ingredient_rules")

      assert index_live
             |> element("#user_ingredient_rules-#{user_ingredient_rule.id} a", "Edit")
             |> render_click() =~
               "Edit User ingredient rule"

      assert_patch(index_live, ~p"/user_ingredient_rules/#{user_ingredient_rule}/edit")

      assert index_live
             |> form("#user_ingredient_rule-form", user_ingredient_rule: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#user_ingredient_rule-form", user_ingredient_rule: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/user_ingredient_rules")

      html = render(index_live)
      assert html =~ "User ingredient rule updated successfully"
    end

    test "deletes user_ingredient_rule in listing", %{
      conn: conn,
      user_ingredient_rule: user_ingredient_rule
    } do
      {:ok, index_live, _html} = live(conn, ~p"/user_ingredient_rules")

      assert index_live
             |> element("#user_ingredient_rules-#{user_ingredient_rule.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#user_ingredient_rules-#{user_ingredient_rule.id}")
    end
  end

  describe "Show" do
    setup [:create_user_ingredient_rule]

    test "displays user_ingredient_rule", %{
      conn: conn,
      user_ingredient_rule: user_ingredient_rule
    } do
      {:ok, _show_live, html} = live(conn, ~p"/user_ingredient_rules/#{user_ingredient_rule}")

      assert html =~ "Show User ingredient rule"
    end

    test "updates user_ingredient_rule within modal", %{
      conn: conn,
      user_ingredient_rule: user_ingredient_rule
    } do
      {:ok, show_live, _html} = live(conn, ~p"/user_ingredient_rules/#{user_ingredient_rule}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit User ingredient rule"

      assert_patch(show_live, ~p"/user_ingredient_rules/#{user_ingredient_rule}/show/edit")

      assert show_live
             |> form("#user_ingredient_rule-form", user_ingredient_rule: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#user_ingredient_rule-form", user_ingredient_rule: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/user_ingredient_rules/#{user_ingredient_rule}")

      html = render(show_live)
      assert html =~ "User ingredient rule updated successfully"
    end
  end
end
