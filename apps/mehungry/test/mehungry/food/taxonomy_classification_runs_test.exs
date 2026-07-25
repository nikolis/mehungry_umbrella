defmodule Mehungry.Food.TaxonomyClassificationRunsTest do
  use Mehungry.DataCase

  alias Mehungry.Food.{Taxonomies, TaxonomyClassificationRun, TaxonomyClassificationRuns}
  alias Mehungry.Repo

  setup do
    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Bio Nutritional", slug: "bio-nutritional"})

    %{taxonomy: taxonomy}
  end

  describe "start_run/1" do
    test "inserts a pending row seeded with a progress snapshot and broadcasts it", %{
      taxonomy: taxonomy
    } do
      Phoenix.PubSub.subscribe(Mehungry.PubSub, TaxonomyClassificationRuns.topic(taxonomy.id))

      run = TaxonomyClassificationRuns.start_run(taxonomy.id)

      assert %TaxonomyClassificationRun{status: "pending", taxonomy_id: tid} = run
      assert tid == taxonomy.id
      assert run.started_at
      assert is_integer(run.total)
      assert is_integer(run.classified)

      assert_received {:classification_run, %TaxonomyClassificationRun{status: "pending"}}
    end
  end

  describe "mark_* transitions broadcast the row" do
    test "processing -> completed", %{taxonomy: taxonomy} do
      Phoenix.PubSub.subscribe(Mehungry.PubSub, TaxonomyClassificationRuns.topic(taxonomy.id))
      run = TaxonomyClassificationRuns.start_run(taxonomy.id)
      assert_received {:classification_run, %TaxonomyClassificationRun{status: "pending"}}

      TaxonomyClassificationRuns.mark_processing(run.id)
      assert_received {:classification_run, %TaxonomyClassificationRun{status: "processing"}}

      TaxonomyClassificationRuns.update_progress(run.id, %{classified: 3, total: 10})
      assert_received {:classification_run, %TaxonomyClassificationRun{classified: 3, total: 10}}

      TaxonomyClassificationRuns.mark_completed(run.id, %{classified: 10, total: 10})

      assert_received {:classification_run,
                       %TaxonomyClassificationRun{status: "completed", classified: 10}}

      reloaded = Repo.get!(TaxonomyClassificationRun, run.id)
      assert reloaded.completed_at
    end

    test "mark_failed records the inspected reason", %{taxonomy: taxonomy} do
      run = TaxonomyClassificationRuns.start_run(taxonomy.id)

      TaxonomyClassificationRuns.mark_failed(run.id, {:api_error, :overloaded})

      reloaded = Repo.get!(TaxonomyClassificationRun, run.id)
      assert reloaded.status == "failed"
      assert reloaded.error =~ "api_error"
    end
  end

  describe "latest_run/1" do
    test "returns the most recent run for the taxonomy", %{taxonomy: taxonomy} do
      _first = TaxonomyClassificationRuns.start_run(taxonomy.id)
      second = TaxonomyClassificationRuns.start_run(taxonomy.id)

      assert TaxonomyClassificationRuns.latest_run(taxonomy.id).id == second.id
    end

    test "returns nil when there is no run", %{taxonomy: taxonomy} do
      assert TaxonomyClassificationRuns.latest_run(taxonomy.id) == nil
    end
  end

  describe "missing-row tolerance" do
    test "update on a deleted run is a no-op, not a crash", %{taxonomy: taxonomy} do
      run = TaxonomyClassificationRuns.start_run(taxonomy.id)
      Repo.delete!(run)

      assert TaxonomyClassificationRuns.mark_processing(run.id) == nil
      assert TaxonomyClassificationRuns.mark_completed(run.id, %{classified: 1, total: 1}) == nil
    end

    test "nil run_id is a no-op" do
      assert TaxonomyClassificationRuns.mark_processing(nil) == nil
    end
  end
end
