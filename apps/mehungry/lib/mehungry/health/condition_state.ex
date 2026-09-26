defmodule Mehungry.Health.ConditionState do
  @moduledoc """
  A disease **state / phase** of a `Condition` — e.g. Ulcerative Colitis →
  *Active Flare* / *Remission*, gout → *Acute Attack* / *Chronic*.

  Dietary advice is frequently state-dependent: the low-residue, low-fiber diet
  indicated during an active IBD flare is the opposite of the diverse high-fiber
  diet appropriate in remission. A phase-specific recommendation
  (`ConditionStateRecommendation`) or extraction candidate is tagged with a
  `condition_state`; a `nil` state means the advice is **general / all-phase**.

  A first-class reference entity like `Condition` itself: each condition owns its
  valid states (`name` + a stable `slug`), one of which may be flagged `is_default`
  (the phase shown when the user hasn't picked one). Most conditions carry no states
  and behave exactly as before this layer existed.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Health.Condition

  @type t :: %__MODULE__{}

  schema "condition_states" do
    field :name, :string
    field :slug, :string
    field :is_default, :boolean, default: false
    field :position, :integer, default: 0
    field :description, :string

    belongs_to :condition, Condition

    timestamps()
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [:condition_id, :name, :slug, :is_default, :position, :description])
    |> validate_required([:condition_id, :name, :slug])
    |> unique_constraint([:condition_id, :slug])
  end
end
