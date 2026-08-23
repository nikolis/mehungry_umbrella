defmodule Mehungry.Food.HashtagReconciliationsTest do
  use Mehungry.DataCase

  import Mehungry.{FoodFixtures, AccountsFixtures}

  alias Mehungry.Food.{HashtagReconciliation, HashtagReconciliations}
  alias Mehungry.Repo

  setup do
    user = user_fixture()
    %{recipe: recipe_fixture(user)}
  end

  test "upsert_pending inserts a pending row and is idempotent", %{recipe: recipe} do
    row = HashtagReconciliations.upsert_pending(recipe.id)
    assert row.status == "pending"

    # Re-upsert resets rather than duplicating.
    row2 = HashtagReconciliations.upsert_pending(recipe.id)
    assert row2.id == row.id
    assert Repo.aggregate(HashtagReconciliation, :count) == 1
  end

  test "state machine: processing -> completed", %{recipe: recipe} do
    row = HashtagReconciliations.upsert_pending(recipe.id)

    assert %{status: "processing"} = HashtagReconciliations.mark_processing(row.id)
    completed = HashtagReconciliations.mark_completed(row.id, 3)
    assert completed.status == "completed"
    assert completed.tags_added == 3
    assert completed.completed_at
  end

  test "mark_failed records the reason", %{recipe: recipe} do
    row = HashtagReconciliations.upsert_pending(recipe.id)
    failed = HashtagReconciliations.mark_failed(row.id, :boom)
    assert failed.status == "failed"
    assert failed.error =~ "boom"
  end

  test "the terminal transition broadcasts the full row on the topic", %{recipe: recipe} do
    Phoenix.PubSub.subscribe(Mehungry.PubSub, HashtagReconciliations.topic())
    row = HashtagReconciliations.upsert_pending(recipe.id)
    assert_receive {:hashtag_recon, %HashtagReconciliation{status: "pending"}}

    HashtagReconciliations.mark_processing(row.id)
    assert_receive {:hashtag_recon_processing, recipe_id}
    assert recipe_id == recipe.id

    HashtagReconciliations.mark_completed(row.id, 1)
    assert_receive {:hashtag_recon, %HashtagReconciliation{status: "completed"}}
  end

  test "update_status is a no-op when the row is gone", %{recipe: recipe} do
    row = HashtagReconciliations.upsert_pending(recipe.id)
    Repo.delete_all(HashtagReconciliation)
    assert HashtagReconciliations.mark_completed(row.id, 1) == nil
  end

  test "pending_or_failed drops completed recipe ids", %{recipe: recipe} do
    other = recipe_fixture(user_fixture())
    row = HashtagReconciliations.upsert_pending(recipe.id)
    HashtagReconciliations.mark_completed(row.id, 0)

    result = HashtagReconciliations.pending_or_failed([recipe.id, other.id])
    refute recipe.id in result
    assert other.id in result
  end

  test "reset deletes all rows", %{recipe: recipe} do
    HashtagReconciliations.upsert_pending(recipe.id)
    assert HashtagReconciliations.reset() == 1
    assert Repo.aggregate(HashtagReconciliation, :count) == 0
  end
end
