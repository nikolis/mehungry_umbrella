defmodule MehungryApi.MixProject do
  use Mix.Project

  def project do
    [
      app: :mehungry_api,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.7",
      compilers: [:phoenix] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: ExCoveralls],
      # preferred_cli_env: [coveralls: :test, "coveralls.detail": :test, "coveralls.post": :test],
      deps: deps()
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {MehungryApi.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:open_api_spex, "~> 3.11"},
      {:mehungry, in_umbrella: true},
      {:bcrypt_elixir, "~> 2.3"},
      {:phoenix, "~> 1.6.2"},
      {:credo, "~> 1.5.0-rc.2", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:con_cache, "~> 0.13.1"},
      {:cors_plug, "~> 1.5"},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix_ecto, "~> 4.4"},
      {:comeonin, "~> 5.1"},
      {:ex_json_schema, "~> 0.5"},
      {:guardian, "~> 2.0"},
      {:pbkdf2_elixir, "~> 0.12"},
      {:ecto_sql, "~> 3.7"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 3.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_dashboard, "~> 0.6"},
      {:gettext, "~> 0.11"},
      {:jason, "~> 1.0"},
      {:httpoison, "~> 1.2"},
      {:poison, "~> 3.1"},
      {:plug_cowboy, "~> 2.5"},
      {:telemetry_metrics, "~> 0.4"},
      {:telemetry_poller, "~> 1.0"}
    ]
  end
end
