defmodule Mehungry.ComponentsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Mehungry.Components` context.
  """

  @doc """
  Generate a search_select.
  """
  def search_select_fixture(attrs \\ %{}) do
    {:ok, search_select} =
      attrs
      |> Enum.into(%{})
      |> Mehungry.Components.create_search_select()

    search_select
  end
end
