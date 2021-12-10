defmodule Mehungry.Accounts2Fixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Mehungry.Accounts2` context.
  """

  @doc """
  Generate a u2ser.
  """
  def u2ser_fixture(attrs \\ %{}) do
    {:ok, u2ser} =
      attrs
      |> Enum.into(%{
        age: 42,
        name: "some name"
      })
      |> Mehungry.Accounts2.create_u2ser()

    u2ser
  end
end
