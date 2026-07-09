defmodule Mehungry.Release do
  alias Mehungry.FdcFoodParser

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

  def load_fdc_ingredients(file_path) do
    FdcFoodParser.get_ingredients_from_food_data_central_json_file(file_path)
  end

  @doc """
  Bulk-imports European food products from Open Food Facts inside a prod
  release (where Mix is unavailable). Same options as
  `Mehungry.OpenFoodFacts.BulkImporter.run/1`:

      Mehungry.Release.import_off_products(download: true)
      Mehungry.Release.import_off_products(path: "/data/off.jsonl.gz", resume_from: 500_000)
  """
  def import_off_products(opts \\ []) do
    Application.ensure_all_started(@app)
    Mehungry.OpenFoodFacts.BulkImporter.run(opts)
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
