defmodule Mehungry.TobedelFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Mehungry.Tobedel` context.
  """

  @doc """
  Generate a bedel.
  """
  def bedel_fixture(attrs \\ %{}) do
    {:ok, bedel} =
      attrs
      |> Enum.into(%{
        age: 42,
        url: "some url"
      })
      |> Mehungry.Tobedel.create_bedel()

    bedel
  end
end
