defmodule Mehungry.Test do
  @moduledoc """
  The Test context.
  """

  import Ecto.Query, warn: false
  alias Mehungry.Repo

  alias Mehungry.Test.Testinger

  @doc """
  Returns the list of testingers.

  ## Examples

      iex> list_testingers()
      [%Testinger{}, ...]

  """
  def list_testingers do
    Repo.all(Testinger)
  end

  @doc """
  Gets a single testinger.

  Raises `Ecto.NoResultsError` if the Testinger does not exist.

  ## Examples

      iex> get_testinger!(123)
      %Testinger{}

      iex> get_testinger!(456)
      ** (Ecto.NoResultsError)

  """
  def get_testinger!(id), do: Repo.get!(Testinger, id)

  @doc """
  Creates a testinger.

  ## Examples

      iex> create_testinger(%{field: value})
      {:ok, %Testinger{}}

      iex> create_testinger(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_testinger(attrs \\ %{}) do
    %Testinger{}
    |> Testinger.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a testinger.

  ## Examples

      iex> update_testinger(testinger, %{field: new_value})
      {:ok, %Testinger{}}

      iex> update_testinger(testinger, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_testinger(%Testinger{} = testinger, attrs) do
    testinger
    |> Testinger.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a testinger.

  ## Examples

      iex> delete_testinger(testinger)
      {:ok, %Testinger{}}

      iex> delete_testinger(testinger)
      {:error, %Ecto.Changeset{}}

  """
  def delete_testinger(%Testinger{} = testinger) do
    Repo.delete(testinger)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking testinger changes.

  ## Examples

      iex> change_testinger(testinger)
      %Ecto.Changeset{data: %Testinger{}}

  """
  def change_testinger(%Testinger{} = testinger, attrs \\ %{}) do
    Testinger.changeset(testinger, attrs)
  end
end
