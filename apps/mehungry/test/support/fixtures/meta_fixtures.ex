defmodule Mehungry.MetaFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Mehungry.Meta` context.
  """

  @doc """
  Generate a visit.
  """
  def visit_fixture(attrs \\ %{}) do
    {:ok, visit} =
      attrs
      |> Enum.into(%{
        details: %{},
        ip_address: "some ip_address",
        session_key: "some session_key"
      })
      |> Mehungry.Meta.create_visit()

    visit
  end
end
