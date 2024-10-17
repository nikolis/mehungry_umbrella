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
      env: [
        aws_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
        aws_secret: System.get_env("AWS_SECRET_ACCESS_KEY"),
        aws_bucket: System.get_env("AWS_ASSETS_BUCKET_NAME"),
        region: "eu-central-1"
      ],
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
      {:vix, "~> 0.23.0"},
      {:image, "~> 0.37"},
      {:seqfuzz, "~> 0.2.0"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:bcrypt_elixir, "~> 3.0"},
      {:httpoison, "~> 1.2"},
      {:contex, "~> 0.4.0"},
      {:mehungry, in_umbrella: true},
      {:ueberauth, "~> 0.6"},
      {:ueberauth_facebook, "~> 0.8"},
      {:ueberauth_google, "~> 0.10"},
      {:phoenix, "~> 1.7.11", override: true},
      {:phoenix_live_view, "~> 0.20.17"},
      {:phoenix_view, "~> 2.0"},
      {:phoenix_ecto, "~> 4.4"},
      {:paginator, "~> 1.2.0"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:gettext, "~> 0.11"},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.5"},
      {:esbuild, "~> 0.8"},
      {:tailwind, "~> 0.2"},
      {:hackney, "~> 1.9"},
      {:sweet_xml, "~> 0.6"},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:live_isolated_component, "~> 0.8.0", only: [:dev, :test]},
      {:wallaby, "~> 0.30", runtime: false, only: :test}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "cmd npm install --prefix assets"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.build": ["tailwind mehungry_web", "esbuild mehungry_web"],
      "assets.deploy": [
        "tailwind mehungry_web --minify",
        "esbuild mehungry_web --minify",
        "phx.digest"
      ]
    ]
  end
end
