defmodule Mehungry.Components do
  @moduledoc """
  The Components context.
  """

  import Ecto.Query, warn: false
  alias Mehungry.Repo

  alias Mehungry.Components.SearchSelect

  @doc """
  Returns the list of search_selects.

  ## Examples

      iex> list_search_selects()
      [%SearchSelect{}, ...]

  """
  def list_search_selects do
    Repo.all(SearchSelect)
  end

  @doc """
  Gets a single search_select.

  Raises `Ecto.NoResultsError` if the Search select does not exist.

  ## Examples

      iex> get_search_select!(123)
      %SearchSelect{}

      iex> get_search_select!(456)
      ** (Ecto.NoResultsError)

  """
  def get_search_select!(id), do: Repo.get!(SearchSelect, id)

  @doc """
  Creates a search_select.

  ## Examples

      iex> create_search_select(%{field: value})
      {:ok, %SearchSelect{}}

      iex> create_search_select(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_search_select(attrs \\ %{}) do
    %SearchSelect{}
    |> SearchSelect.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a search_select.

  ## Examples

      iex> update_search_select(search_select, %{field: new_value})
      {:ok, %SearchSelect{}}

      iex> update_search_select(search_select, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_search_select(%SearchSelect{} = search_select, attrs) do
    search_select
    |> SearchSelect.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a search_select.

  ## Examples

      iex> delete_search_select(search_select)
      {:ok, %SearchSelect{}}

      iex> delete_search_select(search_select)
      {:error, %Ecto.Changeset{}}

  """
  def delete_search_select(%SearchSelect{} = search_select) do
    Repo.delete(search_select)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking search_select changes.

  ## Examples

      iex> change_search_select(search_select)
      %Ecto.Changeset{data: %SearchSelect{}}

  """
  def change_search_select(%SearchSelect{} = search_select, attrs \\ %{}) do
    SearchSelect.changeset(search_select, attrs)
  end
end
