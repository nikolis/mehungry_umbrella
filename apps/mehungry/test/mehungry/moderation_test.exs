defmodule Mehungry.ModerationTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.Accounts
  alias Mehungry.Accounts.UserContent
  alias Mehungry.AccountsFixtures
  alias Mehungry.FoodFixtures
  alias Mehungry.Moderation
  alias Mehungry.Moderation.ContentReport
  alias Mehungry.Posts
  alias Mehungry.Repo

  defp user, do: AccountsFixtures.user_fixture()

  defp comment_on(recipe, author, text \\ "A rude comment") do
    {:ok, comment} =
      Posts.create_comment(%{"text" => text, "recipe_id" => recipe.id, "user_id" => author.id})

    comment
  end

  defp report(reporter, type, id, reason \\ "spam") do
    Moderation.create_report(reporter, %{
      "target_type" => type,
      "target_id" => id,
      "reason" => reason
    })
  end

  describe "create_report/2" do
    test "stores the author and a snapshot of a recipe" do
      author = user()
      recipe = FoodFixtures.recipe_fixture(author)

      assert {:ok, report, :created} = report(user(), "recipe", recipe.id)
      assert report.status == "open"
      assert report.target_user_id == author.id
      assert report.snapshot =~ recipe.title
    end

    test "snapshots a comment's text and survives the comment being deleted" do
      author = user()
      recipe = FoodFixtures.recipe_fixture(user())
      comment = comment_on(recipe, author, "Buy cheap pills here")

      assert {:ok, report, :created} = report(user(), "comment", comment.id, "spam")
      assert report.target_user_id == author.id

      {:ok, _} = Posts.delete_comment(comment)
      assert Repo.get!(ContentReport, report.id).snapshot == "Buy cheap pills here"
    end

    test "reports a user" do
      target = user()
      assert {:ok, report, :created} = report(user(), "user", target.id, "harassment")
      assert report.target_user_id == target.id
    end

    test "returns the existing open report instead of a duplicate" do
      reporter = user()
      recipe = FoodFixtures.recipe_fixture(user())

      assert {:ok, first, :created} = report(reporter, "recipe", recipe.id)
      assert {:ok, again, :existing} = report(reporter, "recipe", recipe.id, "other")
      assert again.id == first.id
      assert Repo.aggregate(ContentReport, :count) == 1
    end

    test "a dismissed report can be filed again" do
      reporter = user()
      recipe = FoodFixtures.recipe_fixture(user())

      {:ok, first, :created} = report(reporter, "recipe", recipe.id)
      {:ok, _} = Moderation.dismiss_report(first)

      assert {:ok, second, :created} = report(reporter, "recipe", recipe.id)
      assert second.id != first.id
    end

    test "rejects reporting your own content and yourself" do
      me = user()
      recipe = FoodFixtures.recipe_fixture(me)

      assert {:error, :cannot_report_yourself} = report(me, "recipe", recipe.id)
      assert {:error, :cannot_report_yourself} = report(me, "user", me.id)
    end

    test "rejects an unknown target, type or reason and an over-long note" do
      reporter = user()
      recipe = FoodFixtures.recipe_fixture(user())

      assert {:error, :not_found} = report(reporter, "recipe", -1)
      assert {:error, %Ecto.Changeset{}} = report(reporter, "post", recipe.id)
      assert {:error, %Ecto.Changeset{}} = report(reporter, "recipe", recipe.id, "boring")

      assert {:error, %Ecto.Changeset{}} =
               Moderation.create_report(reporter, %{
                 "target_type" => "recipe",
                 "target_id" => recipe.id,
                 "reason" => "other",
                 "note" => String.duplicate("x", 1001)
               })
    end
  end

  describe "admin email" do
    alias Mehungry.ObanWorkers.ModerationReportMailerWorker, as: MailerWorker

    test "a new report enqueues one email job; a repeat does not" do
      reporter = user()
      recipe = FoodFixtures.recipe_fixture(user())

      {:ok, first, :created} = report(reporter, "recipe", recipe.id)
      {:ok, _, :existing} = report(reporter, "recipe", recipe.id)

      assert [%Oban.Job{args: %{"report_id" => id}}] =
               Repo.all(from j in Oban.Job, where: j.worker == ^inspect(MailerWorker))

      assert id == first.id
    end

    test "the email goes to the admin and never names the reporter" do
      reporter = user()
      comment = comment_on(FoodFixtures.recipe_fixture(user()), user(), "Buy cheap pills")
      {:ok, report, _} = report(reporter, "comment", comment.id)

      email = MailerWorker.build_email(report)

      assert [{_, to}] = email.to
      assert to == Application.get_env(:mehungry, :admin_email)
      assert email.text_body =~ "Buy cheap pills"
      assert email.text_body =~ "/professional/moderation"
      refute email.text_body =~ reporter.email
    end

    test "a job for an already-resolved report sends nothing" do
      recipe = FoodFixtures.recipe_fixture(user())
      {:ok, report, _} = report(user(), "recipe", recipe.id)
      {:ok, _} = Moderation.dismiss_report(report)

      assert :ok = MailerWorker.perform(%Oban.Job{args: %{"report_id" => report.id}})
      assert :ok = MailerWorker.perform(%Oban.Job{args: %{"report_id" => -1}})
    end
  end

  describe "admin actions" do
    test "dismiss closes the report and leaves the content" do
      recipe = FoodFixtures.recipe_fixture(user())
      {:ok, report, _} = report(user(), "recipe", recipe.id)

      assert {:ok, resolved} = Moderation.dismiss_report(report, "Looks fine")
      assert resolved.status == "dismissed"
      assert resolved.resolution == "none"
      assert resolved.admin_note == "Looks fine"
      assert resolved.resolved_at
      assert Moderation.target_exists?(resolved)
      assert Moderation.open_report_count() == 0
    end

    test "remove_content deletes a comment (with its answers) and closes every report on it" do
      recipe = FoodFixtures.recipe_fixture(user())
      comment = comment_on(recipe, user())

      {:ok, _} =
        Posts.create_comment_answer(%{
          "text" => "reply",
          "comment_id" => comment.id,
          "user_id" => user().id
        })

      {:ok, one, _} = report(user(), "comment", comment.id)
      {:ok, two, _} = report(user(), "comment", comment.id)

      assert {:ok, resolved} = Moderation.remove_content(one)
      assert resolved.status == "actioned"
      assert resolved.resolution == "content_removed"
      refute Moderation.target_exists?(resolved)
      assert Moderation.get_report!(two.id).status == "actioned"
    end

    test "remove_content deletes a recipe and closes reports on its comments too" do
      recipe = FoodFixtures.recipe_fixture(user())
      comment = comment_on(recipe, user())

      {:ok, on_recipe, _} = report(user(), "recipe", recipe.id)
      {:ok, on_comment, _} = report(user(), "comment", comment.id)

      assert {:ok, resolved} = Moderation.remove_content(on_recipe)
      refute Moderation.target_exists?(resolved)
      assert Moderation.get_report!(on_comment.id).status == "actioned"
    end

    test "remove_content does not apply to a report against a user" do
      {:ok, report, _} = report(user(), "user", user().id)
      assert {:error, :not_removable} = Moderation.remove_content(report)
    end

    test "remove_account deletes the author and closes every report against them" do
      author = user()
      recipe = FoodFixtures.recipe_fixture(author)

      {:ok, on_recipe, _} = report(user(), "recipe", recipe.id)
      {:ok, on_user, _} = report(user(), "user", author.id)

      assert {:ok, resolved} = Moderation.remove_account(on_recipe, "Repeat offender")
      assert resolved.status == "actioned"
      assert resolved.resolution == "account_removed"
      assert resolved.target_user_id == nil
      refute Repo.get(Accounts.User, author.id)

      other = Moderation.get_report!(on_user.id)
      assert other.status == "actioned"
      assert other.resolution == "account_removed"
    end
  end

  describe "account deletion" do
    test "closes open reports against the deleted user and un-attributes the ones they filed" do
      leaving = user()
      other = user()
      mine = FoodFixtures.recipe_fixture(leaving)
      theirs = FoodFixtures.recipe_fixture(other)

      {:ok, against, _} = report(other, "recipe", mine.id)
      {:ok, filed, _} = report(leaving, "recipe", theirs.id)
      :ok = Moderation.block_user(leaving, other.id)
      :ok = Moderation.block_user(other, leaving.id)

      {:ok, _} = Accounts.delete_user(leaving)

      against = Moderation.get_report!(against.id)
      assert against.status == "dismissed"
      assert against.target_user_id == nil

      filed = Moderation.get_report!(filed.id)
      assert filed.status == "open"
      assert filed.reporter_id == nil

      assert Moderation.blocked_ids(other) == []
      assert Moderation.blocks_received() == []
    end
  end

  describe "purge_resolved_reports/1" do
    test "deletes only reports resolved before the cutoff" do
      recipe = FoodFixtures.recipe_fixture(user())
      {:ok, old, _} = report(user(), "recipe", recipe.id)
      {:ok, recent, _} = report(user(), "recipe", recipe.id)
      {:ok, open, _} = report(user(), "recipe", recipe.id)

      {:ok, _} = Moderation.dismiss_report(old)
      {:ok, _} = Moderation.dismiss_report(recent)

      long_ago = NaiveDateTime.utc_now() |> NaiveDateTime.add(-400 * 24 * 3600, :second)

      Repo.update_all(from(r in ContentReport, where: r.id == ^old.id),
        set: [resolved_at: NaiveDateTime.truncate(long_ago, :second)]
      )

      assert Moderation.purge_resolved_reports() == 1
      refute Repo.get(ContentReport, old.id)
      assert Repo.get(ContentReport, recent.id)
      assert Repo.get(ContentReport, open.id)
    end
  end

  describe "blocks" do
    test "block is idempotent, one-way and removes follows in both directions" do
      me = user()
      them = user()
      {:ok, _} = UserContent.save_user_follow(me.id, them.id)
      {:ok, _} = UserContent.save_user_follow(them.id, me.id)

      assert :ok = Moderation.block_user(me, them.id)
      assert :ok = Moderation.block_user(me, them.id)

      assert Moderation.blocked_ids(me) == [them.id]
      assert Moderation.blocked?(me, them.id)
      refute Moderation.blocked?(them, me.id)
      refute Moderation.blocked?(nil, them.id)
      refute UserContent.following?(me.id, them.id)
      refute UserContent.following?(them.id, me.id)
    end

    test "cannot block yourself or a missing user" do
      me = user()
      assert {:error, :cannot_block_yourself} = Moderation.block_user(me, me.id)
      assert {:error, :not_found} = Moderation.block_user(me, -1)
    end

    test "unblock and list_blocks" do
      me = user()
      them = user()
      :ok = Moderation.block_user(me, them.id)

      assert [%{user: %{id: id}, alias: name, blocked_at: %NaiveDateTime{}}] =
               Moderation.list_blocks(me)

      assert id == them.id
      assert is_binary(name)

      assert :ok = Moderation.unblock_user(me, them.id)
      assert Moderation.list_blocks(me) == []
    end

    test "reject_blocked drops only the blocked authors' items" do
      me = user()
      them = user()
      other = user()
      :ok = Moderation.block_user(me, them.id)

      items = [%{user_id: them.id}, %{user_id: other.id}, %{user_id: nil}]

      assert Moderation.reject_blocked(items, me, & &1.user_id) ==
               [%{user_id: other.id}, %{user_id: nil}]

      assert Moderation.reject_blocked(items, nil, & &1.user_id) == items
      assert Moderation.reject_blocked(items, other, & &1.user_id) == items
    end

    test "the feed leaves out posts by blocked users" do
      me = user()
      them = user()
      other = user()
      blocked_recipe = FoodFixtures.recipe_fixture(them)
      kept_recipe = FoodFixtures.recipe_fixture(other)
      {:ok, _} = Posts.create_post(blocked_recipe)
      {:ok, _} = Posts.create_post(kept_recipe)

      :ok = Moderation.block_user(me, them.id)

      ids = me |> Posts.list_posts() |> Enum.map(& &1.reference_id)
      assert kept_recipe.id in ids
      refute blocked_recipe.id in ids

      # The blocked user (and everyone else) still sees both.
      assert blocked_recipe.id in (other |> Posts.list_posts() |> Enum.map(& &1.reference_id))
    end

    test "blocks_received ranks by count and blockers_of lists who blocked" do
      popular = user()
      once = user()
      a = user()
      b = user()

      :ok = Moderation.block_user(a, popular.id)
      :ok = Moderation.block_user(b, popular.id)
      :ok = Moderation.block_user(a, once.id)
      {:ok, _, _} = report(a, "user", popular.id)

      assert [
               %{user: %{id: first}, blocks_received: 2, open_reports: 1},
               %{user: %{id: second}, blocks_received: 1, open_reports: 0}
             ] = Moderation.blocks_received()

      assert first == popular.id
      assert second == once.id

      assert Moderation.blockers_of(popular.id) |> Enum.map(& &1.user.id) |> Enum.sort() ==
               Enum.sort([a.id, b.id])

      assert Moderation.user_stats(popular.id) == %{open_reports: 1, blocks_received: 2}
    end
  end
end
