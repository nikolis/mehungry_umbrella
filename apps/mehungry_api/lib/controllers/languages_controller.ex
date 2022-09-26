defmodule MehungryApi.LanguagesController do
  use MehungryApi, :controller

  alias Mehungry.Languages

  def index(conn, _params) do
    languages = Languages.list_languages()
    IO.inspect(languages)
    render(conn, "index.json", languages: languages)
  end
end
