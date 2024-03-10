defmodule MehungryWeb.RecipePostLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.PostsFixtures

  @create_attrs %{
    bg_media_url: "some bg_media_url",
    description: "some description",
    md_media_url: "some md_media_url",
    reference_url: "some reference_url",
    sm_media_url: "some sm_media_url",
    title: "some title"
  }
  @update_attrs %{
    bg_media_url: "some updated bg_media_url",
    description: "some updated description",
    md_media_url: "some updated md_media_url",
    reference_url: "some updated reference_url",
    sm_media_url: "some updated sm_media_url",
    title: "some updated title"
  }
  @invalid_attrs %{
    bg_media_url: nil,
    description: nil,
    md_media_url: nil,
    reference_url: nil,
    sm_media_url: nil,
    title: nil
  }

  defp create_recipe_post(_) do
    recipe_post = recipe_post_fixture()
    %{recipe_post: recipe_post}
  end

  describe "Index" do
    setup [:create_recipe_post]

    test "lists all recipe_posts", %{conn: conn, recipe_post: recipe_post} do
      {:ok, _index_live, html} = live(conn, ~p"/recipe_posts")

      assert html =~ "Listing Recipe posts"
      assert html =~ recipe_post.bg_media_url
    end

    test "saves new recipe_post", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/recipe_posts")

      assert index_live |> element("a", "New Recipe post") |> render_click() =~
               "New Recipe post"

      assert_patch(index_live, ~p"/recipe_posts/new")

      assert index_live
             |> form("#recipe_post-form", recipe_post: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#recipe_post-form", recipe_post: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/recipe_posts")

      html = render(index_live)
      assert html =~ "Recipe post created successfully"
      assert html =~ "some bg_media_url"
    end

    test "updates recipe_post in listing", %{conn: conn, recipe_post: recipe_post} do
      {:ok, index_live, _html} = live(conn, ~p"/recipe_posts")

      assert index_live |> element("#recipe_posts-#{recipe_post.id} a", "Edit") |> render_click() =~
               "Edit Recipe post"

      assert_patch(index_live, ~p"/recipe_posts/#{recipe_post}/edit")

      assert index_live
             |> form("#recipe_post-form", recipe_post: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#recipe_post-form", recipe_post: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/recipe_posts")

      html = render(index_live)
      assert html =~ "Recipe post updated successfully"
      assert html =~ "some updated bg_media_url"
    end

    test "deletes recipe_post in listing", %{conn: conn, recipe_post: recipe_post} do
      {:ok, index_live, _html} = live(conn, ~p"/recipe_posts")

      assert index_live
             |> element("#recipe_posts-#{recipe_post.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#recipe_posts-#{recipe_post.id}")
    end
  end

  describe "Show" do
    setup [:create_recipe_post]

    test "displays recipe_post", %{conn: conn, recipe_post: recipe_post} do
      {:ok, _show_live, html} = live(conn, ~p"/recipe_posts/#{recipe_post}")

      assert html =~ "Show Recipe post"
      assert html =~ recipe_post.bg_media_url
    end

    test "updates recipe_post within modal", %{conn: conn, recipe_post: recipe_post} do
      {:ok, show_live, _html} = live(conn, ~p"/recipe_posts/#{recipe_post}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Recipe post"

      assert_patch(show_live, ~p"/recipe_posts/#{recipe_post}/show/edit")

      assert show_live
             |> form("#recipe_post-form", recipe_post: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#recipe_post-form", recipe_post: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/recipe_posts/#{recipe_post}")

      html = render(show_live)
      assert html =~ "Recipe post updated successfully"
      assert html =~ "some updated bg_media_url"
    end
  end
end
