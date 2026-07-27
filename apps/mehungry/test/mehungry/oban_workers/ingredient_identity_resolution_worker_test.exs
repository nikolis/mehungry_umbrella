defmodule Mehungry.ObanWorkers.IngredientIdentityResolutionWorkerTest do
  use Mehungry.DataCase
  use Oban.Testing, repo: Mehungry.Repo

  import Mehungry.FoodFixtures

  alias Mehungry.Food.IdentityResolution
  alias Mehungry.Food.IdentityResolutionRuns
  alias Mehungry.Food.Ingredient
  alias Mehungry.Food.IngredientIdentityResolutionAttempt, as: Attempt
  alias Mehungry.Food.IngredientIdentityResolutionRun, as: Run
  alias Mehungry.ObanWorkers.IngredientIdentityResolutionWorker, as: Worker
  alias Mehungry.Repo

  defmodule SpinachUsdaStub do
    def fetch_scientific_name(999_001),
      do: {:ok, %{scientific_name: "Spinacia oleracea", description: "Spinach, raw", data_type: "Foundation"}, %{remaining: 100}}

    def fetch_scientific_name(_other),
      do: {:ok, %{scientific_name: nil, description: nil, data_type: nil}, %{remaining: 100}}
  end

  defmodule RateLimitedUsdaStub do
    def fetch_scientific_name(_fdc_id), do: {:error, {:rate_limited, 30}}
  end

  defmodule SpinachIdStub do
    @behaviour Mehungry.Food.IdentityResolution.ScientificIdClient
    @impl true
    def resolve("Spinacia oleracea"),
      do: {:ok, %{ncbi_taxonomy_id: 3562, foodon_id: "FOODON:00003278", wikidata_id: "Q37937", id_source: "wikidata", synonyms: []}}

    def resolve(_), do: {:ok, %{}}
  end

  defp use_sources(usda, id_client) do
    Application.put_env(:mehungry, :usda_scientific_source, usda)
    Application.put_env(:mehungry, :scientific_id_client, id_client)

    on_exit(fn ->
      Application.delete_env(:mehungry, :usda_scientific_source)
      Application.delete_env(:mehungry, :scientific_id_client)
    end)
  end

  defp mark_all_attempted do
    naive = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    utc = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Repo.all(from(i in Ingredient, where: not is_nil(i.fdc_id) and i.fdc_id > 0, select: i.id))
      |> Enum.map(
        &%{
          ingredient_id: &1,
          source: "usda_fdc",
          outcome: "matched",
          attempted_at: utc,
          inserted_at: naive,
          updated_at: naive
        }
      )

    Repo.insert_all(Attempt, rows)
  end

  test "resolves a batch, records identity + attempt, tracks progress, chains next batch" do
    use_sources(SpinachUsdaStub, SpinachIdStub)
    ing = ingredient_fixture(%{name: "spinach", fdc_id: 999_001})
    run = IdentityResolutionRuns.start_run()

    assert :ok = perform_job(Worker, %{"run_id" => run.id})

    # Identity resolved for the freshly-inserted (newest, first-in-batch) ingredient.
    assert [identity] = IdentityResolution.list_identities(ing.id)
    assert identity.scientific_name == "Spinacia oleracea"
    assert identity.ncbi_taxonomy_id == 3562

    # Attempt ledger recorded (so a re-run skips it).
    assert Repo.get_by(Attempt, ingredient_id: ing.id, source: "usda_fdc").outcome == "matched"

    # Run advanced: processing, progress refreshed, next batch enqueued.
    reloaded = Repo.get!(Run, run.id)
    assert reloaded.status == "processing"
    assert reloaded.resolved >= 1
    assert_enqueued(worker: Worker)
  end

  test "completes the run and stops chaining when nothing is left to resolve" do
    use_sources(SpinachUsdaStub, SpinachIdStub)
    mark_all_attempted()
    run = IdentityResolutionRuns.start_run()

    assert :ok = perform_job(Worker, %{"run_id" => run.id})

    assert Repo.get!(Run, run.id).status == "completed"
    refute_enqueued(worker: Worker)
  end

  test "a transient source failure marks the run failed and returns error for Oban retry" do
    use_sources(RateLimitedUsdaStub, SpinachIdStub)
    _ing = ingredient_fixture(%{name: "spinach", fdc_id: 999_001})
    run = IdentityResolutionRuns.start_run()

    assert {:error, {:rate_limited, 30}} = perform_job(Worker, %{"run_id" => run.id})

    assert Repo.get!(Run, run.id).status == "failed"
  end
end
