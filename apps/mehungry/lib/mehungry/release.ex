defmodule Mehungry.Release do
  alias Mehungry.FoodData.Usda.SeedFileParser

  @app :mehungry

  def migrate(opts \\ [all: true]) do
    Application.load(@app)

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, opts))
    end
  end

  def migration_status do
    for repo <- repos(), do: print_migrations_for(repo)
  end

  @doc """
  Seeds the `Mehungry.Health` condition registry from the bundled catalogue
  inside a prod release (where Mix — and thus `mix run priv/repo/seeds.exs` —
  is unavailable).

  Starts `Mehungry.Repo` temporarily (an `eval` task does not boot the app
  supervision tree), then runs `Mehungry.Health.ConditionSeeder.seed/0`, which
  is idempotent (upsert on the unique `name`), so it is safe to re-run:

      bin/mehungry_umbrella eval "Mehungry.Release.seed_health_conditions"
  """
  def seed_health_conditions do
    Application.load(@app)

    {:ok, {:ok, %{inserted: inserted, total: total}}, _} =
      Ecto.Migrator.with_repo(Mehungry.Repo, fn _repo ->
        Mehungry.Health.ConditionSeeder.seed()
      end)

    IO.puts("Seeded health conditions: #{inserted} new, #{total} total.")
    :ok
  end

  def load_fdc_ingredients(file_path) do
    SeedFileParser.get_ingredients_from_food_data_central_json_file(file_path)
  end

  @doc """
  Imports one or more USDA FoodData Central foods by `fdc_id` into the shared
  ingredient catalogue, with their full USDA detail (nutrients + portions +
  category), inside a prod release (where Mix is unavailable). Used to backfill
  individual ingredients a user reports missing without re-seeding a whole file:

      bin/mehungry_umbrella eval "Mehungry.Release.import_usda_ingredients([175040, 170271, 170272, 170273])"

  Fetches each food live from the FDC API (so `FDC_API_KEY` must be set) and runs
  it through the same `FoodParser.create_ingredient/2` path as bulk seeding, so
  it is idempotent — re-running updates the existing row (upsert on name) rather
  than duplicating it. `eval` does not boot the app, so HTTP (`:httpoison`) and
  `Mehungry.Repo` are started temporarily, mirroring `seed_health_conditions/0`.
  Returns a per-id result list.
  """
  def import_usda_ingredients(fdc_ids) when is_list(fdc_ids) do
    Application.load(@app)
    {:ok, _} = Application.ensure_all_started(:httpoison)

    {:ok, results, _} =
      Ecto.Migrator.with_repo(Mehungry.Repo, fn _repo ->
        Enum.map(fdc_ids, &import_one_usda_ingredient/1)
      end)

    Enum.each(results, fn {id, status, label} ->
      IO.puts("[#{status}] fdc_id=#{id} #{label}")
    end)

    results
  end

  defp import_one_usda_ingredient(fdc_id) do
    case Mehungry.FoodData.Usda.SearchClient.get_food_details(fdc_id) do
      {:ok, food} ->
        Mehungry.FoodData.Usda.FoodParser.create_ingredient(food, "usda")
        {fdc_id, :ok, food["description"]}

      other ->
        {fdc_id, :error, inspect(other)}
    end
  end

  @doc """
  Bulk-imports European food products from Open Food Facts inside a prod
  release (where Mix is unavailable). Same options as
  `Mehungry.FoodData.OpenFoodFacts.BulkImporter.run/1`:

      Mehungry.Release.import_off_products(download: true)
      Mehungry.Release.import_off_products(path: "/data/off.jsonl.gz", resume_from: 500_000)
  """
  def import_off_products(opts \\ []) do
    Application.ensure_all_started(@app)
    Mehungry.FoodData.OpenFoodFacts.BulkImporter.run(opts)
  end

  defp print_migrations_for(repo) do
    paths = repo_migrations_path(repo)

    {:ok, repo_status, _} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.migrations(&1, paths), mode: :temporary)

    IO.puts(
      """
      Repo: #{inspect(repo)}
        Status    Migration ID    Migration Name
      --------------------------------------------------
      """ <>
        Enum.map_join(repo_status, "\n", fn {status, number, description} ->
          "  #{pad(status, 10)}#{pad(number, 16)}#{description}"
        end) <> "\n"
    )
  end

  defp repo_migrations_path(repo) do
    config = repo.config()
    priv = config[:priv] || "priv/#{repo |> Module.split() |> List.last() |> Macro.underscore()}"
    config |> Keyword.fetch!(:otp_app) |> Application.app_dir() |> Path.join(priv)
  end

  defp pad(content, pad) do
    content
    |> to_string
    |> String.pad_trailing(pad)
  end

  def rollback(version) do
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    end
  end

  defp repos do
    Application.load(@app)
    Application.fetch_env!(@app, :ecto_repos)
  end
end
