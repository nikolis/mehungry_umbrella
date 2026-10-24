defmodule Mehungry.FoodData.MyPlate.ClientStub do
  @moduledoc """
  Test stand-in for `Mehungry.FoodData.MyPlate.Client` (wired via the
  `:myplate_client` config key in `config/test.exs`) so importer/worker tests
  make no network calls.

  Tests control the responses through app config:

      Application.put_env(:mehungry, :myplate_client_slugs, {:ok, ["zucchini-bread"]})
      Application.put_env(:mehungry, :myplate_client_recipes, %{
        "zucchini-bread" => {:ok, %{"name" => "Zucchini Bread", ...}}
      })
      on_exit(fn ->
        Application.delete_env(:mehungry, :myplate_client_slugs)
        Application.delete_env(:mehungry, :myplate_client_recipes)
      end)

  Defaults to empty results so an un-configured call is harmless.
  """

  @behaviour Mehungry.FoodData.MyPlate.ClientBehaviour

  @impl true
  def list_slugs do
    Application.get_env(:mehungry, :myplate_client_slugs, {:ok, []})
  end

  @impl true
  def fetch_recipe(slug) do
    recipes = Application.get_env(:mehungry, :myplate_client_recipes, %{})
    Map.get(recipes, slug, {:error, :not_found})
  end
end
