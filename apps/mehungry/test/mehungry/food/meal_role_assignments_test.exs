defmodule Mehungry.Food.MealRoleAssignmentsTest do
  use Mehungry.DataCase, async: false
  use Oban.Testing, repo: Mehungry.Repo

  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures, only: [recipe_fixture: 2]

  alias Mehungry.Food
  alias Mehungry.Food.{MealRoleAssignments, Recipe, RecipeMealRole}
  alias Mehungry.ObanWorkers.RecipeMealRoleClassificationWorker
  alias Mehungry.Repo

  setup do
    user = user_fixture()
    %{user: user, recipe: recipe_fixture(user, %{title: "Patlıcan Salatası"})}
  end

  defp ai(role, confidence), do: %{role: role, confidence: confidence}

  defp rows(recipe_id) do
    recipe_id
    |> MealRoleAssignments.list_recipe_roles()
    |> Enum.map(&{&1.role, &1.source, &1.reviewed})
  end

  describe "the save hook" do
    test "creating a recipe enqueues a single-recipe classification", %{recipe: recipe} do
      assert_enqueued(
        worker: RecipeMealRoleClassificationWorker,
        args: %{"recipe_id" => recipe.id},
        queue: :default
      )
    end
  end

  describe "apply_ai_roles/2" do
    test "writes several roles, unreviewed when any is low-confidence", %{recipe: r} do
      assert {:ok, :applied} =
               MealRoleAssignments.apply_ai_roles(r.id, [ai("meze", 0.95), ai("side", 0.6)])

      assert rows(r.id) == [{"side", "ai", false}, {"meze", "ai", false}]
      assert Repo.get!(Recipe, r.id).meal_roles_classified_at
    end

    test "auto-confirms when every role is high-confidence", %{recipe: r} do
      MealRoleAssignments.apply_ai_roles(r.id, [ai("main", 0.97)])
      assert rows(r.id) == [{"main", "ai", true}]
    end

    test "drops roles outside the vocabulary", %{recipe: r} do
      MealRoleAssignments.apply_ai_roles(r.id, [ai("appetizer", 0.9), ai("meze", 0.5)])
      assert rows(r.id) == [{"meze", "ai", false}]
    end

    test "replaces earlier unreviewed AI rows", %{recipe: r} do
      MealRoleAssignments.apply_ai_roles(r.id, [ai("main", 0.5)])
      MealRoleAssignments.apply_ai_roles(r.id, [ai("meze", 0.5)])
      assert rows(r.id) == [{"meze", "ai", false}]
    end

    test "never touches a recipe a human reviewed", %{recipe: r, user: user} do
      {:ok, _} = MealRoleAssignments.set_recipe_roles(r.id, ["meze"], user.id)

      assert {:ok, :skipped_reviewed} =
               MealRoleAssignments.apply_ai_roles(r.id, [ai("main", 0.99)])

      assert rows(r.id) == [{"meze", "manual", true}]
    end

    test "an empty result keeps rows but stamps the recipe as attempted", %{recipe: r} do
      MealRoleAssignments.apply_ai_roles(r.id, [ai("side", 0.5)])
      assert {:ok, :empty} = MealRoleAssignments.apply_ai_roles(r.id, [])
      assert rows(r.id) == [{"side", "ai", false}]
    end
  end

  describe "set_recipe_roles/3 and confirm" do
    test "adds, removes and marks everything reviewed", %{recipe: r, user: user} do
      MealRoleAssignments.apply_ai_roles(r.id, [ai("main", 0.5), ai("meze", 0.7)])

      {:ok, _} = MealRoleAssignments.set_recipe_roles(r.id, ["side", "meze"], user.id)

      assert rows(r.id) == [{"side", "manual", true}, {"meze", "ai", true}]

      assert Enum.all?(
               MealRoleAssignments.list_recipe_roles(r.id),
               &(&1.reviewed_by_id == user.id)
             )
    end

    test "rejects roles outside the vocabulary", %{recipe: r, user: user} do
      assert {:error, {:invalid_roles, ["entree"]}} =
               MealRoleAssignments.set_recipe_roles(r.id, ["main", "entree"], user.id)
    end

    test "confirm_many marks the current AI set reviewed", %{recipe: r, user: user} do
      MealRoleAssignments.apply_ai_roles(r.id, [ai("meze", 0.5)])
      assert {:ok, 1} = Food.confirm_many_recipe_meal_roles([r.id], user.id)
      assert rows(r.id) == [{"meze", "ai", true}]
    end

    test "maybe_classify_on_save skips reviewed recipes", %{recipe: r, user: user} do
      {:ok, _} = MealRoleAssignments.set_recipe_roles(r.id, ["main"], user.id)
      assert MealRoleAssignments.maybe_classify_on_save(r.id) == :skipped
    end
  end

  describe "reads" do
    test "roles_for/1 returns roles in vocabulary order; unclassified are absent", %{
      recipe: r,
      user: user
    } do
      other = recipe_fixture(user, %{})
      MealRoleAssignments.apply_ai_roles(r.id, [ai("side", 0.5), ai("main", 0.5)])
      assert MealRoleAssignments.roles_for([r.id, other.id]) == %{r.id => ["main", "side"]}
    end

    test "list_for_review/2 filters by status and role", %{recipe: r, user: user} do
      unclassified = recipe_fixture(user, %{})
      reviewed = recipe_fixture(user, %{})
      MealRoleAssignments.apply_ai_roles(r.id, [ai("meze", 0.5)])
      {:ok, _} = MealRoleAssignments.set_recipe_roles(reviewed.id, ["main"], user.id)

      ids = fn filters ->
        filters |> MealRoleAssignments.list_for_review() |> Enum.map(& &1.id)
      end

      assert ids.(%{status: "needs_review"}) == [r.id]
      assert ids.(%{status: "unclassified"}) == [unclassified.id]
      assert ids.(%{status: "reviewed"}) == [reviewed.id]
      assert ids.(%{status: "all", role: "main"}) == [reviewed.id]
      assert ids.(%{status: "all", search: "patlıcan"}) == [r.id]

      [row] = MealRoleAssignments.list_for_review(%{status: "needs_review"})
      assert [%RecipeMealRole{role: "meze"}] = row.meal_roles
      assert is_nil(row.embedding)
    end

    test "coverage/0 counts recipes per state and role", %{recipe: r, user: user} do
      reviewed = recipe_fixture(user, %{})
      MealRoleAssignments.apply_ai_roles(r.id, [ai("meze", 0.5), ai("side", 0.5)])
      {:ok, _} = MealRoleAssignments.set_recipe_roles(reviewed.id, ["main", "side"], user.id)

      cov = MealRoleAssignments.coverage()
      assert cov.classified == 2
      assert cov.needs_review == 1
      assert cov.reviewed == 1
      assert cov.unclassified == cov.total - 2
      assert cov.per_role["side"] == 2
      assert cov.per_role["main"] == 1
      assert cov.per_role["dessert"] == 0
    end
  end

  describe "classification runs" do
    test "pending ids: unclassified vs unreviewed-since-start", %{recipe: r, user: user} do
      reviewed = recipe_fixture(user, %{})
      {:ok, _} = MealRoleAssignments.set_recipe_roles(reviewed.id, ["main"], user.id)

      assert r.id in MealRoleAssignments.pending_classification_ids("unclassified")
      refute reviewed.id in MealRoleAssignments.pending_classification_ids("unclassified")

      MealRoleAssignments.apply_ai_roles(r.id, [ai("meze", 0.5)])
      later = DateTime.utc_now() |> DateTime.add(5) |> DateTime.truncate(:second)
      ids = MealRoleAssignments.pending_classification_ids("unreviewed", since: later)
      assert r.id in ids
      refute reviewed.id in ids
    end

    test "enqueue_classification refuses a second concurrent run" do
      assert {:ok, run} = MealRoleAssignments.enqueue_classification("unclassified")
      assert run.total >= 1
      assert {:error, :already_running} = MealRoleAssignments.enqueue_classification("unreviewed")
    end

    test "reset_and_classify drops even reviewed roles and re-enqueues", %{recipe: r, user: user} do
      {:ok, _} = MealRoleAssignments.set_recipe_roles(r.id, ["main"], user.id)
      {:ok, _job} = MealRoleAssignments.reset_and_classify(r.id)
      assert rows(r.id) == []
    end
  end
end
