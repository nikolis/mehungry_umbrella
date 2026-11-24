defmodule MehungrySeasonality.Case do
  @moduledoc """
  Database-backed test case for the seasonality app: the shared sandbox, stub API
  clients, and helpers to create the species + mappings a test needs.
  """

  use ExUnit.CaseTemplate

  alias MehungrySeasonality.TestStubs

  using do
    quote do
      import MehungrySeasonality.Case
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Mehungry.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    Application.put_env(:mehungry_seasonality, :agridata_client, TestStubs.Agridata)
    Application.put_env(:mehungry_seasonality, :comext_client, TestStubs.Comext)

    on_exit(fn ->
      Application.delete_env(:mehungry_seasonality, :agridata_client)
      Application.delete_env(:mehungry_seasonality, :comext_client)
    end)

    :ok
  end

  @doc "Create a food species in the core app and return its id."
  def species_fixture(name) do
    {:ok, species} = Mehungry.Food.create_foundemental_species(%{name: name})
    species.id
  end

  @doc "Map a species to an agri-food product and/or a Comext code."
  def map_species(species_id, opts) do
    for {source, code} <- opts do
      {:ok, _} =
        MehungrySeasonality.save_mapping(%{
          foundemental_species_id: species_id,
          source: Atom.to_string(source),
          external_code: code
        })
    end

    :ok
  end
end
