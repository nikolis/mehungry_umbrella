defmodule Mehungry.NotificationsTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.Notifications
  import Mehungry.AccountsFixtures, only: [user_fixture: 0]

  describe "emit/3 from the context (shared by LiveView + REST)" do
    test "creating a comment via Posts notifies the recipe author" do
      author = user_fixture()
      commenter = user_fixture()
      recipe = Mehungry.FoodFixtures.recipe_fixture(author)

      {:ok, _comment} =
        Mehungry.Posts.create_comment(%{
          "text" => "Looks great!",
          "recipe_id" => recipe.id,
          "user_id" => commenter.id
        })

      assert [notif] = Notifications.list(author.id)
      assert notif.type == "comment"
      assert notif.actor_id == commenter.id
      assert notif.subject_type == "recipe"
      assert notif.subject_id == recipe.id
      assert notif.data["preview"] == "Looks great!"
    end

    test "commenting on your own recipe notifies no one" do
      author = user_fixture()
      recipe = Mehungry.FoodFixtures.recipe_fixture(author)

      {:ok, _} =
        Mehungry.Posts.create_comment(%{
          "text" => "mine",
          "recipe_id" => recipe.id,
          "user_id" => author.id
        })

      assert Notifications.unread_count(author.id) == 0
    end

    test "following a user via the context notifies the target" do
      follower = user_fixture()
      target = user_fixture()

      {:ok, _} = Mehungry.Accounts.UserContent.save_user_follow(follower.id, target.id)

      assert [notif] = Notifications.list(target.id)
      assert notif.type == "follow"
      assert notif.actor_id == follower.id
    end
  end

  describe "create/3" do
    test "inserts a notification for the recipient" do
      recipient = user_fixture()
      actor = user_fixture()

      assert {:ok, notif} =
               Notifications.create(recipient.id, "comment",
                 actor_id: actor.id,
                 subject_type: "recipe",
                 subject_id: 7,
                 data: %{"recipe_title" => "Soup"}
               )

      assert notif.recipient_id == recipient.id
      assert notif.actor_id == actor.id
      assert notif.subject_type == "recipe"
      assert notif.data == %{"recipe_title" => "Soup"}
      assert is_nil(notif.read_at)
    end

    test "suppresses a self-notification" do
      user = user_fixture()
      assert :ignored = Notifications.create(user.id, "comment", actor_id: user.id)
      assert Notifications.unread_count(user.id) == 0
    end

    test "de-dupes an unread follow from the same actor" do
      recipient = user_fixture()
      actor = user_fixture()

      assert {:ok, _} = Notifications.create(recipient.id, "follow", actor_id: actor.id)
      assert :ignored = Notifications.create(recipient.id, "follow", actor_id: actor.id)
      assert Notifications.unread_count(recipient.id) == 1

      # Once read, a fresh follow is allowed again.
      :ok = Notifications.mark_all_read(recipient.id)
      assert {:ok, _} = Notifications.create(recipient.id, "follow", actor_id: actor.id)
    end

    test "rejects an unknown type" do
      recipient = user_fixture()
      assert {:error, changeset} = Notifications.create(recipient.id, "nope")
      assert %{type: _} = errors_on(changeset)
    end
  end

  describe "list/2 + read state" do
    test "returns newest first with the actor preloaded" do
      recipient = user_fixture()
      actor = user_fixture()

      {:ok, _} = Notifications.create(recipient.id, "comment", actor_id: actor.id, subject_id: 1)
      {:ok, second} = Notifications.create(recipient.id, "comment", actor_id: actor.id, subject_id: 2)

      [first | _] = Notifications.list(recipient.id)
      assert first.id == second.id
      assert first.actor.id == actor.id
    end

    test "limit caps the page" do
      recipient = user_fixture()
      actor = user_fixture()

      for i <- 1..3,
          do: Notifications.create(recipient.id, "comment", actor_id: actor.id, subject_id: i)

      assert length(Notifications.list(recipient.id, limit: 2)) == 2
    end

    test "unread_count, mark_read, mark_all_read" do
      recipient = user_fixture()
      actor = user_fixture()

      {:ok, a} = Notifications.create(recipient.id, "comment", actor_id: actor.id, subject_id: 1)
      {:ok, _b} = Notifications.create(recipient.id, "comment", actor_id: actor.id, subject_id: 2)
      assert Notifications.unread_count(recipient.id) == 2

      :ok = Notifications.mark_read(recipient.id, a.id)
      assert Notifications.unread_count(recipient.id) == 1

      :ok = Notifications.mark_all_read(recipient.id)
      assert Notifications.unread_count(recipient.id) == 0
    end

    test "mark_read is scoped to the recipient" do
      owner = user_fixture()
      other = user_fixture()
      actor = user_fixture()
      {:ok, n} = Notifications.create(owner.id, "comment", actor_id: actor.id, subject_id: 1)

      :ok = Notifications.mark_read(other.id, n.id)
      # Not the owner → still unread.
      assert Notifications.unread_count(owner.id) == 1
    end
  end
end
