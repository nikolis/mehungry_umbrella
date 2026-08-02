defmodule Mehungry.Literature.CrawlAttempt do
  @moduledoc """
  Per-`(foundemental_species, search_term)` crawl ledger — records that a search
  term was run against Entrez for a food species, with the `outcome`
  (`matched | no_results | error`) and how many studies it produced.

  It lets the batch worker terminate (already-crawled `(species, term)` pairs are
  excluded from the next batch) and provides an audit trail. `last_crawled_at`
  doubles as the incremental-crawl watermark for a date-restricted re-crawl of
  only newer papers.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.FoundementalFoodSpecies

  @outcomes ~w(matched no_results error)

  schema "literature_crawl_attempts" do
    field :search_term, :string
    field :outcome, :string
    field :studies_found, :integer, default: 0
    field :last_crawled_at, :utc_datetime

    belongs_to :species, FoundementalFoodSpecies, foreign_key: :foundemental_species_id

    timestamps()
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :foundemental_species_id,
      :search_term,
      :outcome,
      :studies_found,
      :last_crawled_at
    ])
    |> validate_required([:foundemental_species_id, :search_term, :outcome])
    |> validate_inclusion(:outcome, @outcomes)
    |> unique_constraint([:foundemental_species_id, :search_term])
  end
end
