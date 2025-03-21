defmodule Mehungry.MixProject do
  use Mix.Project

  def project do
    [
      app: :mehungry,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
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
      mod: {Mehungry.Application, []},
      extra_applications: [:logger, :runtime_tools]
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
      {:bcrypt_elixir, "~> 3.0"},
      {:poison, "~> 5.0"},
      {:numexy, "~> 0.1.9"},
      {:hackney, "~> 1.18.1"},
      {:ex_aws, "~> 2.1"},
      {:aws, "~> 1.0.0"},
      {:hackney, "~> 1.18"},
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:hackney, "~> 1.18"},
      {:sweet_xml, "~> 0.7"},
      {:configparser_ex, "~> 4.0", optional: true},  # For
      {:ueberauth, "~> 0.6"},
      {:oauth2, "~> 2.0", override: true},
      {:ueberauth_facebook, "~> 0.8"},
      {:ueberauth_google, "~> 0.8"},
      {:phoenix, "~> 1.7.10"},
      {:swoosh, "~> 1.8"},
      {:phoenix_pubsub, "~> 2.0"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, ">= 0.0.0"},
      {:jason, "~> 1.0"},
      {:paginator, "~> 1.2.0"},
      {:cachex, "~> 3.4"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
