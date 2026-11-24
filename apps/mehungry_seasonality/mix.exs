defmodule MehungrySeasonality.MixProject do
  use Mix.Project

  @moduledoc """
  Self-contained **seasonality** bounded context: per species × country × month, is
  the produce locally on the market and is it imported (from where).

  Dependency direction is `mehungry_web → mehungry_seasonality → mehungry`. The app has
  no supervision tree of its own — it uses the core app's Repo, Oban and PubSub through
  the single adapter module `MehungrySeasonality.Core`. See
  `docs/implementation/seasonality.md`.
  """

  def project do
    [
      app: :mehungry_seasonality,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:mehungry, in_umbrella: true},
      {:ecto_sql, "~> 3.11"},
      {:oban, "~> 2.17"},
      {:httpoison, "~> 2.2"},
      {:jason, "~> 1.2"}
    ]
  end

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
