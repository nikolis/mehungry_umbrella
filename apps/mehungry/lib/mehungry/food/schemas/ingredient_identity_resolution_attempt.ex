defmodule Mehungry.Food.IngredientIdentityResolutionAttempt do
  @moduledoc """
  Per-ingredient resolution ledger — records that an ingredient was processed by
  the identity resolver for a given `source` (e.g. `usda_fdc`), with the `outcome`
  (`matched | no_scientific_name | error`).

  Mirrors the role of `seed_files` in the seeding pipeline: it lets the batch
  worker terminate (already-attempted ingredients are excluded from the next
  batch) and provides an audit trail even when no identity could be created.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.Ingredient

  @outcomes ~w(matched no_scientific_name error)

  schema "ingredient_identity_resolution_attempts" do
    field :source, :string
    field :outcome, :string
    field :detail, :string
    field :attempted_at, :utc_datetime

    belongs_to :ingredient, Ingredient

    timestamps()
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:ingredient_id, :source, :outcome, :detail, :attempted_at])
    |> validate_required([:ingredient_id, :source, :outcome])
    |> validate_inclusion(:outcome, @outcomes)
    |> unique_constraint([:ingredient_id, :source])
  end
end
