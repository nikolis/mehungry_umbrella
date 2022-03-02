defmodule MehungryApi.LanguagesView do
  use MehungryApi, :view

  alias MehungryApi.LanguagesView

  def render("index.json", %{languages: languages}) do
    %{data: render_many(languages, LanguagesView, "language.json")}
  end

  def render("language.json", %{languages: language}) do
    %{
      id: language.id,
      name: language.name
    }
  end
end
