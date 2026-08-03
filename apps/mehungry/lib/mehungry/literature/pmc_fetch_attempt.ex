defmodule Mehungry.Literature.PmcFetchAttempt do
  @moduledoc """
  Per-study PMC full-text fetch ledger: records that we tried to obtain full text
  for a study and the `outcome` (`open_access | no_pmcid | not_oa | error`). Lets the
  batch worker terminate — already-attempted studies are excluded from the next batch.
  Most papers are not open-access, so this mostly records skips.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Literature.ScientificStudy

  @outcomes ~w(open_access no_pmcid not_oa error)

  schema "pmc_fetch_attempts" do
    field :pmcid, :string
    field :outcome, :string
    field :last_attempted_at, :utc_datetime

    belongs_to :study, ScientificStudy

    timestamps()
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:study_id, :pmcid, :outcome, :last_attempted_at])
    |> validate_required([:study_id, :outcome])
    |> validate_inclusion(:outcome, @outcomes)
    |> unique_constraint(:study_id)
  end
end
