defmodule MehungryWeb.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :mehungry_web

  @doc """
  Deploy entry point (wired into `fly.toml`'s `release_command`): run pending
  migrations, then idempotently ensure the onboarding "default questions"
  template is seeded **and** its Greek prompts are present
  (`Mehungry.Release.seed_onboarding_defaults/0` → `Onboarding.seed_defaults/0`,
  which also heals any prompt_el left as the English label). Keeping the seed in
  the release step means every `fly deploy` brings both schema and this bootstrap
  data current with no manual console step.
  """
  def migrate_and_seed do
    migrate()
    Mehungry.Release.seed_onboarding_defaults()
  end

  def migrate do
    load_app()

    for repo <- repos() do
      # Use a tiny pool: migrations run during deploy while the live machine
      # still holds its own pool, and the Supabase session pooler caps total
      # clients (15 on the current plan). A migrator only needs one connection.
      {:ok, _, _} =
        Ecto.Migrator.with_repo(
          repo,
          &Ecto.Migrator.run(&1, :up, all: true),
          pool_size: 2
        )
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
