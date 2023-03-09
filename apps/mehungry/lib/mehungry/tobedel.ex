defmodule Mehungry.Tobedel do
  @moduledoc """
  The Tobedel context.
  """

  import Ecto.Query, warn: false
  alias Mehungry.Repo

  alias Mehungry.Tobedel.Bedel

  @doc """
  Returns the list of bedels.

  ## Examples

      iex> list_bedels()
      [%Bedel{}, ...]

  """
  def list_bedels do
    Repo.all(Bedel)
  end

  @doc """
  Gets a single bedel.

  Raises `Ecto.NoResultsError` if the Bedel does not exist.

  ## Examples

      iex> get_bedel!(123)
      %Bedel{}

      iex> get_bedel!(456)
      ** (Ecto.NoResultsError)

  """
  def get_bedel!(id), do: Repo.get!(Bedel, id)

  @doc """
  Creates a bedel.

  ## Examples

      iex> create_bedel(%{field: value})
      {:ok, %Bedel{}}

      iex> create_bedel(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_bedel(attrs \\ %{}) do
    %Bedel{}
    |> Bedel.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a bedel.

  ## Examples

      iex> update_bedel(bedel, %{field: new_value})
      {:ok, %Bedel{}}

      iex> update_bedel(bedel, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_bedel(%Bedel{} = bedel, attrs) do
    bedel
    |> Bedel.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a bedel.

  ## Examples

      iex> delete_bedel(bedel)
      {:ok, %Bedel{}}

      iex> delete_bedel(bedel)
      {:error, %Ecto.Changeset{}}

  """
  def delete_bedel(%Bedel{} = bedel) do
    Repo.delete(bedel)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking bedel changes.

  ## Examples

      iex> change_bedel(bedel)
      %Ecto.Changeset{data: %Bedel{}}

  """
  def change_bedel(%Bedel{} = bedel, attrs \\ %{}) do
    Bedel.changeset(bedel, attrs)
  end
end
