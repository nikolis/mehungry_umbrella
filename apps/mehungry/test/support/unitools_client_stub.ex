defmodule Mehungry.FoodData.UniTools.ClientStub do
  @moduledoc """
  Test stand-in for `Mehungry.FoodData.UniTools.Client` (wired via the
  `:unitools_client` config key in `config/test.exs`) so importer/LiveView tests
  read no bundled file.

  Tests control the per-dataset wrapper map through app config:

      Application.put_env(:mehungry, :unitools_client_datasets, %{
        "v1" => {:ok, %{"license" => "CC BY-SA 4.0", "recipes" => [...]}}
      })
      on_exit(fn -> Application.delete_env(:mehungry, :unitools_client_datasets) end)

  Defaults to `{:error, :not_found}` so an un-configured call is harmless.
  """

  @behaviour Mehungry.FoodData.UniTools.ClientBehaviour

  @impl true
  def load_dataset(id) do
    datasets = Application.get_env(:mehungry, :unitools_client_datasets, %{})
    Map.get(datasets, id, {:error, :not_found})
  end
end
