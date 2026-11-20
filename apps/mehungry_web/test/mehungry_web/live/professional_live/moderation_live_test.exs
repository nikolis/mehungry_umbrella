defmodule MehungryWeb.ProfessionalLive.ModerationLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  alias Mehungry.FoodFixtures
  alias Mehungry.Moderation
  alias Mehungry.Posts

  @admin_email Application.compile_env(:mehungry, :admin_email)

  defp report(reporter, type, id, attrs \\ %{}) do
    {:ok, report, :created} =
      Moderation.create_report(
        reporter,
        Map.merge(%{"target_type" => type, "target_id" => id, "reason" => "spam"}, attrs)
      )

    report
  end

  describe "access" do
    test "a non-admin is redirected away", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:error, {:redirect, %{to: "/home"}}} = live(conn, ~p"/professional/moderation")
    end
  end

  describe "as admin" do
    setup %{conn: conn} do
      admin = user_fixture(%{email: @admin_email})
      author = user_fixture()
      reporter = user_fixture()
      recipe = FoodFixtures.recipe_fixture(author)

      {:ok, comment} =
        Posts.create_comment(%{
          "text" => "Buy cheap pills here",
          "recipe_id" => recipe.id,
          "user_id" => author.id
        })

      %{
        conn: log_in_user(conn, admin),
        author: author,
        reporter: reporter,
        recipe: recipe,
        comment: comment
      }
    end

    test "shows the open queue with snapshot, reason, reporter and note", ctx do
      report(ctx.reporter, "comment", ctx.comment.id, %{"note" => "obvious ad"})

      {:ok, _view, html} = live(ctx.conn, ~p"/professional/moderation")

      assert html =~ "1 open report"
      assert html =~ "Buy cheap pills here"
      assert html =~ "Spam"
      assert html =~ "obvious ad"
      assert html =~ ctx.reporter.email
      assert html =~ "/show_recipe/#{ctx.recipe.id}"
    end

    test "dismiss moves the report out of the open queue", ctx do
      r = report(ctx.reporter, "recipe", ctx.recipe.id)
      {:ok, view, _html} = live(ctx.conn, ~p"/professional/moderation")

      view
      |> form("#resolve-#{r.id}", %{admin_note: "fine"})
      |> render_submit(%{action: "dismiss"})

      refute has_element?(view, "#report-#{r.id}")
      assert %{status: "dismissed", admin_note: "fine"} = Moderation.get_report!(r.id)

      html = view |> element("#status-dismissed") |> render_click()
      assert html =~ "fine"
    end

    test "remove content deletes the comment and notifies its author", ctx do
      r = report(ctx.reporter, "comment", ctx.comment.id)
      {:ok, view, _html} = live(ctx.conn, ~p"/professional/moderation")

      view |> form("#resolve-#{r.id}") |> render_submit(%{action: "remove_content"})

      assert %{status: "actioned", resolution: "content_removed"} = Moderation.get_report!(r.id)
      refute Mehungry.Repo.get(Posts.Comment, ctx.comment.id)

      assert [%{type: "content_removed", actor_id: nil, data: data}] =
               Mehungry.Notifications.list(ctx.author.id)

      assert data["target_type"] == "comment"
      assert data["reason"] == "spam"
    end

    test "remove account deletes the author", ctx do
      r = report(ctx.reporter, "user", ctx.author.id)
      {:ok, view, html} = live(ctx.conn, ~p"/professional/moderation")

      # A report against a user offers no "Remove content".
      refute html =~ "Remove content"

      view |> form("#resolve-#{r.id}") |> render_submit(%{action: "remove_account"})

      assert %{status: "actioned", resolution: "account_removed"} = Moderation.get_report!(r.id)
      refute Mehungry.Repo.get(Mehungry.Accounts.User, ctx.author.id)
    end

    test "blocks tab ranks blocked users and drills into who blocked them", ctx do
      :ok = Moderation.block_user(ctx.reporter, ctx.author.id)
      {:ok, view, _html} = live(ctx.conn, ~p"/professional/moderation")

      html = view |> element("#tab-blocks") |> render_click()
      assert html =~ ctx.author.email
      assert html =~ "blocked by 1"
      refute html =~ ctx.reporter.email

      html =
        view |> element("#blocked-#{ctx.author.id} button") |> render_click()

      assert html =~ ctx.reporter.email
    end
  end
end
