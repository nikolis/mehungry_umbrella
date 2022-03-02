defmodule Mehungry.Languages do
  import Ecto.Query

  alias Mehungry.Repo
  alias Mehungry.Languages.Language

  def create_language(attrs \\ %{}) do
    Language.changeset(%Language{}, attrs)
    |> Repo.insert()
  end

  def get_language_by_name(name) do
    query = from lang in Language, where: lang.name == ^name
    Repo.one(query)
  end

  def list_languages() do
    Repo.all(Language)
  end
end
