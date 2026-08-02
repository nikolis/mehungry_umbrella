defmodule MehungryLocalAi.MixProject do
  use Mix.Project

  @moduledoc """
  Local-only, GPU/CPU-heavy measurement-extraction service.

  This app is **not part of the production release** (see the umbrella root
  `mix.exs` `releases:` block and the `Dockerfile`, which removes this app before
  building). It carries the heavy Bumblebee/EXLA/Nx dependency tree and runs on a
  local machine with real hardware, talking to the deployed app only over REST.
  """

  def project do
    [
      app: :mehungry_local_ai,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MehungryLocalAi.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Heavy ML stack lives ONLY here — deliberately absent from apps/mehungry so the
  # production release never fetches or compiles exla/xla/bumblebee.
  defp deps do
    [
      {:nx, "~> 0.9"},
      {:exla, "~> 0.9"},
      {:bumblebee, "~> 0.6"},
      {:httpoison, "~> 2.2"},
      {:jason, "~> 1.2"}
    ]
  end
end
