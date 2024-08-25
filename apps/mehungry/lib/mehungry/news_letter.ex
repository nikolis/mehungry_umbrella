defmodule Mehungry.NewsLetter do
  @moduledoc """
  The NewsLetter context.
  """

  import Ecto.Query, warn: false
  alias Mehungry.Repo

  alias Mehungry.NewsLetter.Nuser

  @doc """
  Returns the list of nusers.

  ## Examples

      iex> list_nusers()
      [%Nuser{}, ...]

  """
  def list_nusers do
    Repo.all(Nuser)
  end

  @doc """
  Gets a single nuser.

  Raises `Ecto.NoResultsError` if the Nuser does not exist.

  ## Examples

      iex> get_nuser!(123)
      %Nuser{}

      iex> get_nuser!(456)
      ** (Ecto.NoResultsError)

  """
  def get_nuser!(id), do: Repo.get!(Nuser, id)

  @doc """
  Creates a nuser.

  ## Examples

      iex> create_nuser(%{field: value})
      {:ok, %Nuser{}}

      iex> create_nuser(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_nuser(attrs \\ %{}) do
    %Nuser{}
    |> Nuser.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a nuser.

  ## Examples

      iex> update_nuser(nuser, %{field: new_value})
      {:ok, %Nuser{}}

      iex> update_nuser(nuser, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_nuser(%Nuser{} = nuser, attrs) do
    nuser
    |> Nuser.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a nuser.

  ## Examples

      iex> delete_nuser(nuser)
      {:ok, %Nuser{}}

      iex> delete_nuser(nuser)
      {:error, %Ecto.Changeset{}}

  """
  def delete_nuser(%Nuser{} = nuser) do
    Repo.delete(nuser)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking nuser changes.

  ## Examples

      iex> change_nuser(nuser)
      %Ecto.Changeset{data: %Nuser{}}

  """
  def change_nuser(%Nuser{} = nuser, attrs \\ %{}) do
    Nuser.changeset(nuser, attrs)
  end
end
