defmodule Mehungry.Literature.ConditionCrawlAttempt do
  @moduledoc """
  Per-`(condition, search_term)` ledger for the reverse (condition-seeded) crawl —
  the condition analogue of `CrawlAttempt`. Records that a term was run against
  Entrez for a `Health.Condition`, with the `outcome` (`matched | no_results |
  error`) and how many studies it produced.

  Lets the batch worker terminate (already-crawled `(condition, term)` pairs are
  excluded from the next batch); `last_crawled_at` doubles as the incremental-crawl
  watermark.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Health.Condition

  @outcomes ~w(matched no_results error)

  schema "condition_crawl_attempts" do
    field :search_term, :string
    field :outcome, :string
    field :studies_found, :integer, default: 0
    field :last_crawled_at, :utc_datetime

    belongs_to :condition, Condition

    timestamps()
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:condition_id, :search_term, :outcome, :studies_found, :last_crawled_at])
    |> validate_required([:condition_id, :search_term, :outcome])
    |> validate_inclusion(:outcome, @outcomes)
    |> unique_constraint([:condition_id, :search_term])
  end
end
