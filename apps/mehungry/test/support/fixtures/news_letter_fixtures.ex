defmodule Mehungry.NewsLetterFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Mehungry.NewsLetter` context.
  """

  @doc """
  Generate a nuser.
  """
  def nuser_fixture(attrs \\ %{}) do
    {:ok, nuser} =
      attrs
      |> Enum.into(%{
        email: "some email"
      })
      |> Mehungry.NewsLetter.create_nuser()

    nuser
  end
end
