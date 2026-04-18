defmodule Mehungry.Languages do
  @moduledoc false

  import Ecto.Query

  alias Mehungry.Repo
  alias Mehungry.Languages.Language

  def create_language(attrs \\ %{}) do
    Language.changeset(%Language{}, attrs)
    |> Repo.insert()
  end

  def change_language(language, attrs \\ %{}) do
    Language.changeset(%Language{}, attrs)
  end


  def get_language_by_name(name) do
    query = from lang in Language, where: lang.name == ^name
    Repo.one(query)
  end

  def list_languages() do
    Repo.all(Language)
  end
end
