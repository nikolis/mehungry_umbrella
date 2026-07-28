defmodule Mehungry.Food.IdentityResolution.NullScientificIdClient do
  @moduledoc """
  No-op `ScientificIdClient` — returns no external identifiers.

  Use it to run the pipeline on the USDA `scientific_name` alone (no external
  network calls), e.g. by setting `config :mehungry, :scientific_id_client,
  Mehungry.Food.IdentityResolution.NullScientificIdClient`. Also a convenient base
  for test stubs.
  """

  @behaviour Mehungry.Food.IdentityResolution.ScientificIdClient

  @impl true
  def resolve(_scientific_name), do: {:ok, %{}}
end
