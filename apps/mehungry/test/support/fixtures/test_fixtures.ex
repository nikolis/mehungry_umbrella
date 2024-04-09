defmodule Mehungry.TestFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Mehungry.Test` context.
  """

  @doc """
  Generate a testinger.
  """
  def testinger_fixture(attrs \\ %{}) do
    {:ok, testinger} =
      attrs
      |> Enum.into(%{})
      |> Mehungry.Test.create_testinger()

    testinger
  end

  @doc """
  Generate a testinger.

  def testinger_fixture(attrs \\ %{}) do
    {:ok, testinger} =
      attrs
      |> Enum.into(%{
        name: "some name"
      })
      |> Mehungry.Test.create_testinger()

    testinger
  end
  """
end
