defmodule Mehungry.TestDeleteFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Mehungry.TestDelete` context.
  """

  @doc """
  Generate a delete_test.
  """
  def delete_test_fixture(attrs \\ %{}) do
    {:ok, delete_test} =
      attrs
      |> Enum.into(%{
        name: "some name"
      })
      |> Mehungry.TestDelete.create_delete_test()

    delete_test
  end
end
