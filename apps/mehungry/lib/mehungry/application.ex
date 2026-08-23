defmodule Mehungry.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      Mehungry.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Mehungry.PubSub},
      {Oban, Application.fetch_env!(:mehungry, Oban)},
      # Start a worker by calling: Mehungry.Worker.start_link(arg)
      # {Mehungry.Worker, arg}
      # Supervisor.child_spec({Cachex, name: :recipe_cache}, id: :recipe_cache)
      # Supervisor.child_spec({Cachex, name: :create_recipe_cache}, id: :create_recipe_cache)
      # {Cachex, [:recipe_cache, [limit: 300]], id: :recipes_cache_worker}  # with custom options
      %{id: :recipes_cache, start: {Cachex, :start_link, [:recipes_cache, [limit: 150]]}},
      %{id: :cache_user_tokens, start: {Cachex, :start_link, [:cache_user_tokens]}},
      %{id: :geo_cache, start: {Cachex, :start_link, [:geo_cache, [limit: 5000]]}},
      # Negative cache for Open Food Facts barcode lookups (respects OFF's 100 req/min limit)
      %{id: :off_lookup_cache, start: {Cachex, :start_link, [:off_lookup_cache, [limit: 1000]]}},
      # Hot name->CID cache for the PubChem importer; the durable cache is the
      # `pubchem_responses` ledger (Mehungry.Chemistry).
      %{id: :pubchem_cache, start: {Cachex, :start_link, [:pubchem_cache, [limit: 5000]]}},
      # Hot search->PMIDs cache for the Entrez literature crawler; the durable
      # cache is the `entrez_responses` ledger (Mehungry.Literature).
      %{id: :entrez_cache, start: {Cachex, :start_link, [:entrez_cache, [limit: 5000]]}},
      # Hot pmid->mentions cache for the PubTator3 annotator; the raw payloads are
      # retained in the `pubtator_responses` ledger (Mehungry.Literature).
      %{id: :pubtator_cache, start: {Cachex, :start_link, [:pubtator_cache, [limit: 5000]]}},
      # Fixed-window rate limiting counters (registration throttle, Spoonacular gating)
      %{id: :rate_limit, start: {Cachex, :start_link, [:rate_limit, [limit: 100_000]]}},
      # Read-through cache for the (editorial, shared-safe) condition-page reads in
      # Mehungry.Health — species_for_condition/recommendations_for_condition/get_condition.
      # Keyed by {condition, recommendation, language}; entries expire via per-put TTL.
      %{id: :health_cache, start: {Cachex, :start_link, [:health_cache, [limit: 1000]]}},
      # Read-through cache for the heavy get_ingredient_details! nutrient/portion preloads
      # (near-immutable reference data); per-put TTL.
      %{
        id: :ingredient_details_cache,
        start: {Cachex, :start_link, [:ingredient_details_cache, [limit: 500]]}
      },
      {Task.Supervisor, name: Mehungry.TaskSupervisor}
    ]

    case Supervisor.start_link(children, strategy: :one_for_one, name: Mehungry.Supervisor) do
      {:ok, _pid} = ok ->
        # Reset any pipeline run left stuck "processing" by a mid-run restart, so
        # the /professional/science Run buttons don't stay disabled forever.
        Mehungry.Science.RunReconciler.reconcile_on_boot()
        ok

      other ->
        other
    end
  end
end
