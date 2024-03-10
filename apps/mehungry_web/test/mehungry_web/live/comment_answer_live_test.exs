defmodule MehungryWeb.CommentAnswerLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.PostsFixtures

  @create_attrs %{text: "some text"}
  @update_attrs %{text: "some updated text"}
  @invalid_attrs %{text: nil}

  defp create_comment_answer(_) do
    comment_answer = comment_answer_fixture()
    %{comment_answer: comment_answer}
  end

  describe "Index" do
    setup [:create_comment_answer]

    test "lists all comment_answers", %{conn: conn, comment_answer: comment_answer} do
      {:ok, _index_live, html} = live(conn, ~p"/comment_answers")

      assert html =~ "Listing Comment answers"
      assert html =~ comment_answer.text
    end

    test "saves new comment_answer", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/comment_answers")

      assert index_live |> element("a", "New Comment answer") |> render_click() =~
               "New Comment answer"

      assert_patch(index_live, ~p"/comment_answers/new")

      assert index_live
             |> form("#comment_answer-form", comment_answer: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#comment_answer-form", comment_answer: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/comment_answers")

      html = render(index_live)
      assert html =~ "Comment answer created successfully"
      assert html =~ "some text"
    end

    test "updates comment_answer in listing", %{conn: conn, comment_answer: comment_answer} do
      {:ok, index_live, _html} = live(conn, ~p"/comment_answers")

      assert index_live
             |> element("#comment_answers-#{comment_answer.id} a", "Edit")
             |> render_click() =~
               "Edit Comment answer"

      assert_patch(index_live, ~p"/comment_answers/#{comment_answer}/edit")

      assert index_live
             |> form("#comment_answer-form", comment_answer: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#comment_answer-form", comment_answer: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/comment_answers")

      html = render(index_live)
      assert html =~ "Comment answer updated successfully"
      assert html =~ "some updated text"
    end

    test "deletes comment_answer in listing", %{conn: conn, comment_answer: comment_answer} do
      {:ok, index_live, _html} = live(conn, ~p"/comment_answers")

      assert index_live
             |> element("#comment_answers-#{comment_answer.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#comment_answers-#{comment_answer.id}")
    end
  end

  describe "Show" do
    setup [:create_comment_answer]

    test "displays comment_answer", %{conn: conn, comment_answer: comment_answer} do
      {:ok, _show_live, html} = live(conn, ~p"/comment_answers/#{comment_answer}")

      assert html =~ "Show Comment answer"
      assert html =~ comment_answer.text
    end

    test "updates comment_answer within modal", %{conn: conn, comment_answer: comment_answer} do
      {:ok, show_live, _html} = live(conn, ~p"/comment_answers/#{comment_answer}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Comment answer"

      assert_patch(show_live, ~p"/comment_answers/#{comment_answer}/show/edit")

      assert show_live
             |> form("#comment_answer-form", comment_answer: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#comment_answer-form", comment_answer: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/comment_answers/#{comment_answer}")

      html = render(show_live)
      assert html =~ "Comment answer updated successfully"
      assert html =~ "some updated text"
    end
  end
end
