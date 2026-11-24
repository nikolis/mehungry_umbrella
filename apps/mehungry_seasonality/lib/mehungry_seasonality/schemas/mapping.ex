defmodule MehungrySeasonality.Mapping do
  @moduledoc """
  Crosswalk from one food species to one external product identifier. A species can
  have several per source (e.g. two Comext codes). `source` is:

    * `"agridata"` — `external_code` is an EU agri-food portal product name
      (`"Tomatoes"`), the local-production signal;
    * `"comext"` — `external_code` is an HS/CN product code (`"0702"`), the import signal.

  The species is referenced by id only — this app never owns or edits species.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @sources ~w(agridata comext)

  schema "seasonality_mappings" do
    field :foundemental_species_id, :integer
    field :source, :string
    field :external_code, :string
    field :label, :string

    timestamps()
  end

  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [:foundemental_species_id, :source, :external_code, :label])
    |> update_change(:external_code, &String.trim/1)
    |> validate_required([:foundemental_species_id, :source, :external_code])
    |> validate_inclusion(:source, @sources)
    |> validate_comext_code()
    |> foreign_key_constraint(:foundemental_species_id)
    |> unique_constraint([:foundemental_species_id, :source, :external_code],
      name: :seasonality_mappings_species_source_code_index,
      message: "is already mapped"
    )
  end

  # Comext product codes are 2–8 digit HS/CN codes.
  defp validate_comext_code(changeset) do
    if get_field(changeset, :source) == "comext" do
      validate_format(changeset, :external_code, ~r/^\d{2,8}$/,
        message: "must be a 2–8 digit HS/CN code"
      )
    else
      changeset
    end
  end

  def sources, do: @sources
end
