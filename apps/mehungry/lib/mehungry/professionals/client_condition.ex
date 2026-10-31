defmodule Mehungry.Professionals.ClientCondition do
  @moduledoc """
  Join row linking a `ProfessionalClient` to an existing `Health.Condition` — the
  structured client↔condition association.

  A client can carry several conditions, but each only once (unique on the pair).
  Only an existing condition can be linked (the `condition_id` is picked from the
  `Health.Condition` registry; this layer never creates conditions). Authored
  exclusively from the nutritionist-gated client record editor.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Professionals.ProfessionalClient
  alias Mehungry.Health.Condition

  schema "professional_client_conditions" do
    belongs_to :professional_client, ProfessionalClient
    belongs_to :condition, Condition

    timestamps()
  end

  @doc false
  def changeset(client_condition, attrs) do
    client_condition
    |> cast(attrs, [:professional_client_id, :condition_id])
    |> validate_required([:professional_client_id, :condition_id])
    |> foreign_key_constraint(:professional_client_id)
    |> foreign_key_constraint(:condition_id)
    |> unique_constraint([:professional_client_id, :condition_id],
      name: :professional_client_conditions_unique_index
    )
  end
end
