defmodule Mehungry.Languages do 
  import Ecto.Query
  alias Mehungry.Language
  alias Mehungry.Repo

  def get_language_by_name(name) do
   query =  from lang in Language, where: lang.name == ^name
   Repo.one query
  end

  def list_languages() do
    Repo.all(Language)
  end

end
