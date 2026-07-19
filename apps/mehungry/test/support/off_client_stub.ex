defmodule Mehungry.FoodData.OpenFoodFacts.ClientStub do
  @moduledoc """
  Test stand-in for `Mehungry.FoodData.OpenFoodFacts.Client` (wired up via the
  `:off_client` config key in `config/test.exs`) so tests never hit the
  network.

  Tests control responses per callback through app config:

      Application.put_env(:mehungry, :off_stub,
        fetch_product: fn _barcode -> {:ok, %{"code" => "..."}} end
      )
      on_exit(fn -> Application.delete_env(:mehungry, :off_stub) end)
  """

  @behaviour Mehungry.FoodData.OpenFoodFacts.ClientBehaviour

  @impl true
  def fetch_product(barcode),
    do: call(:fetch_product, [barcode], {:error, :not_found})

  @impl true
  def fetch_delta_index,
    do: call(:fetch_delta_index, [], {:ok, []})

  @impl true
  def download_delta(filename, dest_path),
    do: call(:download_delta, [filename, dest_path], {:error, :not_stubbed})

  @impl true
  def download_dump(dest_path),
    do: call(:download_dump, [dest_path], {:error, :not_stubbed})

  defp call(fun_name, args, default) do
    case Application.get_env(:mehungry, :off_stub, [])[fun_name] do
      nil -> default
      fun -> apply(fun, args)
    end
  end
end
