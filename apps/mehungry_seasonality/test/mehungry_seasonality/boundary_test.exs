defmodule MehungrySeasonality.BoundaryTest do
  @moduledoc """
  Guards the app's limits. The dependency graph already stops the core app from
  *depending* on this one; these checks stop the softer leaks.
  """

  use ExUnit.Case, async: true

  @app_root Path.expand("../..", __DIR__)
  @core_lib Path.expand("../../../mehungry/lib", __DIR__)

  # A reference to a core module: `Mehungry.` not preceded by a letter (so
  # `MehungrySeasonality.` itself never matches).
  @core_reference ~r/(?<![A-Za-z])Mehungry\./

  test "only core.ex reaches into the core app" do
    offenders =
      @app_root
      |> Path.join("lib/**/*.ex")
      |> Path.wildcard()
      |> Enum.reject(&String.ends_with?(&1, "mehungry_seasonality/core.ex"))
      |> Enum.filter(fn file ->
        file
        |> File.stream!()
        |> Enum.reject(&comment_or_doc_free_line?/1)
        |> Enum.any?(&Regex.match?(@core_reference, &1))
      end)
      |> Enum.map(&Path.relative_to(&1, @app_root))

    assert offenders == [],
           "these files reference Mehungry.* directly — go through MehungrySeasonality.Core: " <>
             inspect(offenders)
  end

  test "the core app never references the seasonality app" do
    offenders =
      @core_lib
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.filter(&(File.read!(&1) =~ "MehungrySeasonality"))

    assert offenders == []
  end

  # Line comments may mention core modules freely.
  defp comment_or_doc_free_line?(line), do: String.trim_leading(line) =~ ~r/^#/
end
