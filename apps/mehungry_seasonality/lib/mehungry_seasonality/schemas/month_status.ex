defmodule MehungrySeasonality.MonthStatus do
  @moduledoc """
  **The result**: for one species × country × calendar month, two independent facts.

    * `local` — `unknown` (no local source mapped) · `none` · `in_season` ·
      `greenhouse` · `stored` · `unresolved` (on the market all year, so the data
      cannot tell open-field from greenhouse/storage — an admin decides).
    * `imported` — `unknown` (no import source mapped) · `none` · `some` · `major`.

  Both are derived from the observations, and either can be overridden by an admin:
  a `*_curated` flag marks a hand-set value that re-derivation never overwrites.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @local ~w(unknown none in_season greenhouse stored unresolved)
  @imported ~w(unknown none some major)

  schema "seasonality_month_statuses" do
    field :foundemental_species_id, :integer
    field :country, :string
    field :month, :integer
    field :local, :string, default: "unknown"
    field :imported, :string, default: "unknown"
    field :top_origins, {:array, :map}, default: []
    field :local_curated, :boolean, default: false
    field :imported_curated, :boolean, default: false
    field :note, :string

    timestamps()
  end

  @castable ~w(foundemental_species_id country month local imported top_origins
               local_curated imported_curated note)a

  def changeset(status, attrs) do
    status
    |> cast(attrs, @castable)
    |> validate_required([:foundemental_species_id, :country, :month, :local, :imported])
    |> validate_inclusion(:month, 1..12)
    |> validate_inclusion(:local, @local)
    |> validate_inclusion(:imported, @imported)
    |> unique_constraint([:foundemental_species_id, :country, :month],
      name: :seasonality_month_statuses_species_country_month_index
    )
  end

  def local_values, do: @local
  def imported_values, do: @imported
end
