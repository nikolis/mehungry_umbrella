defmodule Mehungry.Literature.CrawlAttempt do
  @moduledoc """
  Per-`(ingredient, search_term)` crawl ledger — records that a search term was
  run against Entrez for an ingredient, with the `outcome`
  (`matched | no_results | error`) and how many studies it produced.

  Mirrors the role of `IngredientIdentityResolutionAttempt`: it lets the batch
  worker terminate (already-crawled `(ingredient, term)` pairs are excluded from
  the next batch) and provides an audit trail. `last_crawled_at` doubles as the
  incremental-crawl watermark for a date-restricted re-crawl of only newer papers.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.Ingredient

  @outcomes ~w(matched no_results error)

  schema "literature_crawl_attempts" do
    field :search_term, :string
    field :outcome, :string
    field :studies_found, :integer, default: 0
    field :last_crawled_at, :utc_datetime

    belongs_to :ingredient, Ingredient

    timestamps()
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:ingredient_id, :search_term, :outcome, :studies_found, :last_crawled_at])
    |> validate_required([:ingredient_id, :search_term, :outcome])
    |> validate_inclusion(:outcome, @outcomes)
    |> unique_constraint([:ingredient_id, :search_term])
  end
end
