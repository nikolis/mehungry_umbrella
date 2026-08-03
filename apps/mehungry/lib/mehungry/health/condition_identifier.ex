defmodule Mehungry.Health.ConditionIdentifier do
  @moduledoc """
  A cross-database identity for a `Condition`, mirroring `Food.CompoundIdentifier`.

  Each row is one external identifier in one namespace — MeSH (`mesh`), ICD-10
  (`icd10`), SNOMED (`snomed`), or a free-form fallback. Identifiers, not names,
  are the stable currency for integrating literature data, so the registry is
  looked up and deduplicated by `(namespace, identifier)`. This is what lets a
  PubTator disease mention (a MeSH id) resolve to one of our seeded conditions
  instead of being carried around as a bare string.

  `is_primary` marks the identifier the mapping was seeded from; `source` records
  who asserted it (e.g. `"pubtator"` when a disease mention matched by name).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Health.Condition

  @namespaces ~w(mesh icd10 icd11 snomed omim doid other)

  @type t :: %__MODULE__{}

  schema "condition_identifiers" do
    field :namespace, :string
    field :identifier, :string
    field :is_primary, :boolean, default: false
    field :source, :string

    belongs_to :condition, Condition

    timestamps()
  end

  def changeset(condition_identifier, attrs) do
    condition_identifier
    |> cast(attrs, [:condition_id, :namespace, :identifier, :is_primary, :source])
    |> validate_required([:condition_id, :namespace, :identifier])
    |> validate_inclusion(:namespace, @namespaces)
    |> unique_constraint([:namespace, :identifier])
  end
end
