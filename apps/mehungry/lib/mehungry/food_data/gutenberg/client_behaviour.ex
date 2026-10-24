defmodule Mehungry.FoodData.Gutenberg.ClientBehaviour do
  @moduledoc """
  Behaviour for the Project Gutenberg plain-text download client, so the network
  call can be swapped for a stub in tests via the `:gutenberg_client` config key.
  """

  @doc "Downloads the full UTF-8 plain text of the ebook with this id."
  @callback fetch_book(id :: String.t()) :: {:ok, String.t()} | {:error, term()}
end
