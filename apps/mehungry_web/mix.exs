defmodule MehungryWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :mehungry_web,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {MehungryWeb.Application, []},
      extra_applications: [:logger, :runtime_tools, :ueberauth_facebook]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:cachex, "~> 3.4"},
      {:floki, ">= 0.30.0", only: :test},
      {:evision, "~> 0.1.16"},
      {:vix, "~> 0.23.0"},
      {:image, "~> 0.37"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:bcrypt_elixir, "~> 3.0"},
      {:httpoison, "~> 1.2"},
      {:contex, "~> 0.4.0"},
      {:mehungry, in_umbrella: true},
      {:ueberauth_facebook, "~> 0.8"},
      {:ueberauth_google, "~> 0.10"},
      {:phoenix, "~> 1.7.11", override: true},
      {:phoenix_live_view, "~> 0.20.11"},
      {:phoenix_view, "~> 2.0"},
      {:phoenix_ecto, "~> 4.4"},
      {:paginator, "~> 1.2.0"},
      {:phoenix_html, "~> 4.1.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:telemetry_metrics, "~> 0.4"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.11"},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.5"},
      {:tailwind, "~> 0.1", runtime: Mix.env() == :dev}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"],
      setup: ["deps.get", "cmd npm install --prefix assets"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
