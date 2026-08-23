defmodule Mehungry.ObanWorkers.HashtagReconciliationWorkerTest do
  use Mehungry.DataCase
  use Oban.Testing, repo: Mehungry.Repo

  import Mehungry.{FoodFixtures, AccountsFixtures}

  alias Mehungry.Food
  alias Mehungry.Food.{HashtagReconciliation, HashtagReconciliations, RecipeHashtag}
  alias Mehungry.ObanWorkers.HashtagReconciliationWorker
  alias Mehungry.Repo

  import Ecto.Query

  defp join_count(recipe_id) do
    Repo.aggregate(from(rh in RecipeHashtag, where: rh.recipe_id == ^recipe_id), :count)
  end

  test "reconciles a recipe missing its description tag and marks it completed" do
    user = user_fixture()
    recipe = recipe_fixture(user, %{description: "look a #stray tag"})

    # Simulate the production drift: recipe exists but its #stray link is gone.
    Repo.delete_all(from rh in RecipeHashtag, where: rh.recipe_id == ^recipe.id)
    assert join_count(recipe.id) == 0

    reconciliation = HashtagReconciliations.upsert_pending(recipe.id)

    assert :ok =
             perform_job(HashtagReconciliationWorker, %{
               "reconciliation_id" => reconciliation.id,
               "recipe_id" => recipe.id
             })

    row = Repo.get!(HashtagReconciliation, reconciliation.id)
    assert row.status == "completed"
    assert row.completed_at
    assert row.tags_added >= 1

    # The #stray link is re-created and the tag is searchable again.
    assert Mehungry.Hashtag.get_hashtag_by_title("stray")
    {_q, {found, _cursor}} = Food.search_hashtag1("#stray")
    assert length(found) == 1
  end

  test "a completed reconciliation is idempotent (no new links on a second run)" do
    user = user_fixture()
    recipe = recipe_fixture(user, %{description: "already #done"})

    reconciliation = HashtagReconciliations.upsert_pending(recipe.id)

    assert :ok =
             perform_job(HashtagReconciliationWorker, %{
               "reconciliation_id" => reconciliation.id,
               "recipe_id" => recipe.id
             })

    count_after_first = join_count(recipe.id)

    reconciliation2 = HashtagReconciliations.upsert_pending(recipe.id)

    assert :ok =
             perform_job(HashtagReconciliationWorker, %{
               "reconciliation_id" => reconciliation2.id,
               "recipe_id" => recipe.id
             })

    assert join_count(recipe.id) == count_after_first
    assert Repo.get!(HashtagReconciliation, reconciliation2.id).tags_added == 0
  end

  test "enqueue/1 upserts a pending row and inserts a unique job" do
    user = user_fixture()
    recipe = recipe_fixture(user)

    assert {:ok, _job} = HashtagReconciliationWorker.enqueue(recipe.id)

    assert %HashtagReconciliation{status: "pending"} =
             Repo.get_by(HashtagReconciliation, recipe_id: recipe.id)

    assert_enqueued(worker: HashtagReconciliationWorker, args: %{recipe_id: recipe.id})

    assert {:ok, job2} = HashtagReconciliationWorker.enqueue(recipe.id)
    assert job2.conflict?
  end
end
