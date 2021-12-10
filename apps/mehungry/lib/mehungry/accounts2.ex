defmodule Mehungry.Accounts2 do
  @moduledoc """
  The Accounts2 context.
  """

  import Ecto.Query, warn: false
  alias Mehungry.Repo

  alias Mehungry.Accounts2.U2ser

  @doc """
  Returns the list of u2sers.

  ## Examples

      iex> list_u2sers()
      [%U2ser{}, ...]

  """
  def list_u2sers do
    Repo.all(U2ser)
  end

  @doc """
  Gets a single u2ser.

  Raises `Ecto.NoResultsError` if the U2ser does not exist.

  ## Examples

      iex> get_u2ser!(123)
      %U2ser{}

      iex> get_u2ser!(456)
      ** (Ecto.NoResultsError)

  """
  def get_u2ser!(id), do: Repo.get!(U2ser, id)

  @doc """
  Creates a u2ser.

  ## Examples

      iex> create_u2ser(%{field: value})
      {:ok, %U2ser{}}

      iex> create_u2ser(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_u2ser(attrs \\ %{}) do
    %U2ser{}
    |> U2ser.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a u2ser.

  ## Examples

      iex> update_u2ser(u2ser, %{field: new_value})
      {:ok, %U2ser{}}

      iex> update_u2ser(u2ser, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_u2ser(%U2ser{} = u2ser, attrs) do
    u2ser
    |> U2ser.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a u2ser.

  ## Examples

      iex> delete_u2ser(u2ser)
      {:ok, %U2ser{}}

      iex> delete_u2ser(u2ser)
      {:error, %Ecto.Changeset{}}

  """
  def delete_u2ser(%U2ser{} = u2ser) do
    Repo.delete(u2ser)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking u2ser changes.

  ## Examples

      iex> change_u2ser(u2ser)
      %Ecto.Changeset{data: %U2ser{}}

  """
  def change_u2ser(%U2ser{} = u2ser, attrs \\ %{}) do
    U2ser.changeset(u2ser, attrs)
  end
end
