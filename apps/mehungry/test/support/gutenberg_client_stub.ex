defmodule Mehungry.FoodData.Gutenberg.ClientStub do
  @moduledoc """
  Test stand-in for `Mehungry.FoodData.Gutenberg.Client` (wired via the
  `:gutenberg_client` config key in `config/test.exs`) so importer/LiveView
  tests make no network calls.

  Tests control the per-book text through app config:

      Application.put_env(:mehungry, :gutenberg_client_books, %{
        "6385" => {:ok, "*** START OF ... ***\\n...book text...\\n*** END OF ... ***"}
      })
      on_exit(fn -> Application.delete_env(:mehungry, :gutenberg_client_books) end)

  Defaults to `{:error, :not_found}` so an un-configured call is harmless.
  """

  @behaviour Mehungry.FoodData.Gutenberg.ClientBehaviour

  @impl true
  def fetch_book(id) do
    books = Application.get_env(:mehungry, :gutenberg_client_books, %{})
    Map.get(books, id, {:error, :not_found})
  end
end
