defmodule Mehungry.Languages do
  @moduledoc false

  import Ecto.Query

  alias Mehungry.Repo
  alias Mehungry.Languages.Language

  def create_language(attrs \\ %{}) do
    Language.changeset(%Language{}, attrs)
    |> Repo.insert()
  end

  def update_language(%Language{} = language, attrs) do
    language
    |> Language.changeset(attrs)
    |> Repo.update()
  end

  def change_language(_language, attrs \\ %{}) do
    Language.changeset(%Language{}, attrs)
  end

  def get_language!(id), do: Repo.get!(Language, id)

  def get_language_by_name(name) do
    query = from lang in Language, where: lang.name == ^name
    Repo.one(query)
  end

  @doc """
  Returns the `Language` row for `name`, creating it if missing. Used before
  writing a translation row so the `language_name` FK never fails (e.g. the
  ISO `"el"` code may not have been seeded alongside the legacy `"Gr"`).
  """
  def ensure_language(name) do
    case get_language_by_name(name) do
      nil ->
        case create_language(%{name: name}) do
          {:ok, lang} -> lang
          # Lost a race — the row now exists.
          {:error, _} -> get_language_by_name(name)
        end

      lang ->
        lang
    end
  end

  def list_languages() do
    Repo.all(Language)
  end

  def delete_language(%Language{} = language) do
    Repo.delete(language)
  end
end
