defmodule MehungrySeasonality.Statuses do
  @moduledoc """
  The monthly statuses — the result this app exists to produce. They are derived from
  the stored observations (`rederive/2`) and can be overridden per month by an admin;
  a curated value is never overwritten by re-derivation.
  """

  import Ecto.Query, warn: false

  alias MehungrySeasonality.{Core, Derivation, Mappings, MonthStatus, Observations}

  @doc """
  Recompute the twelve statuses of a species × country from its stored observations
  and current mappings, leaving any curated `local` / `imported` value untouched.
  """
  def rederive(species_id, country) do
    sources = species_id |> Mappings.for_species() |> MapSet.new(& &1.source)

    local =
      if "agridata" in sources, do: Observations.local_by_month(species_id, country)

    imports =
      if "comext" in sources, do: Observations.imports_by_month(species_id, country)

    existing = by_month(species_id, country)

    for derived <- Derivation.derive(local, imports) do
      current =
        Map.get(existing, derived.month) ||
          %MonthStatus{
            foundemental_species_id: species_id,
            country: country,
            month: derived.month
          }

      attrs =
        %{}
        |> put_unless(current.local_curated, :local, derived.local)
        |> put_unless(current.imported_curated, :imported, derived.imported)
        |> put_unless(current.imported_curated, :top_origins, derived.top_origins)

      current |> MonthStatus.changeset(attrs) |> Core.repo().insert_or_update!()
    end

    :ok
  end

  @doc """
  The admin results grid for a country: one row per mapped species (name-ordered),
  each with its twelve month cells and the raw observations behind them.

      [%{species: %{id, name, variety},
         months: %{1 => %{status: %MonthStatus{} | nil, local: obs | nil, import: obs | nil}}}]
  """
  def grid(country) do
    species_ids = Mappings.mapped_species_ids()
    species = Core.species_by_ids(species_ids)

    statuses =
      from(s in MonthStatus, where: s.country == ^country)
      |> Core.repo().all()
      |> Map.new(&{{&1.foundemental_species_id, &1.month}, &1})

    local = Observations.local_for_country(country)
    imports = Observations.imports_for_country(country)

    species
    |> Map.values()
    |> Enum.sort_by(&{&1.name, &1.variety || ""})
    |> Enum.map(fn sp ->
      months =
        Map.new(1..12, fn month ->
          key = {sp.id, month}
          {month, %{status: statuses[key], local: local[key], import: imports[key]}}
        end)

      %{species: sp, months: months}
    end)
  end

  @doc "The twelve statuses of a species × country, keyed by month (missing months absent)."
  def by_month(species_id, country) do
    from(s in MonthStatus,
      where: s.foundemental_species_id == ^species_id and s.country == ^country
    )
    |> Core.repo().all()
    |> Map.new(&{&1.month, &1})
  end

  # `local` values that mean "a domestic product is on the market that month". A
  # year-round product (`unresolved`) counts: it is on the market, the data just
  # cannot say whether from the field, a greenhouse or storage.
  @on_market ~w(in_season greenhouse stored unresolved)

  @doc """
  Species ids locally on the market in `country` in `month` (`local` one of
  #{Enum.join(@on_market, ", ")}). Curated values count like derived ones — the
  stored `local` is already the effective value.
  """
  def available_species_ids(country, month) do
    from(s in MonthStatus,
      where: s.country == ^country and s.month == ^month and s.local in @on_market,
      select: s.foundemental_species_id
    )
    |> Core.repo().all()
    |> MapSet.new()
  end

  @doc """
  Hand-set a month. `key` is `%{species_id, country, month}`; `attrs` may carry
  `"local"`, `"imported"` and `"note"`. A given `local` / `imported` value is stored
  and flagged curated; a blank one hands that fact back to derivation.
  """
  def override(%{species_id: species_id, country: country, month: month}, attrs) do
    current =
      Core.repo().get_by(MonthStatus,
        foundemental_species_id: species_id,
        country: country,
        month: month
      ) || %MonthStatus{foundemental_species_id: species_id, country: country, month: month}

    changes =
      %{note: blank_to_nil(attrs["note"])}
      |> put_curated(:local, :local_curated, blank_to_nil(attrs["local"]))
      |> put_curated(:imported, :imported_curated, blank_to_nil(attrs["imported"]))

    with {:ok, _status} <-
           current |> MonthStatus.changeset(changes) |> Core.repo().insert_or_update() do
      # Refill whichever fact is not curated from the observations.
      rederive(species_id, country)

      {:ok,
       Core.repo().get_by!(MonthStatus,
         foundemental_species_id: species_id,
         country: country,
         month: month
       )}
    end
  end

  @doc "Drop a month's overrides and note, then re-derive it from the observations."
  def clear_override(%{species_id: species_id, country: country, month: month}) do
    from(s in MonthStatus,
      where:
        s.foundemental_species_id == ^species_id and s.country == ^country and s.month == ^month
    )
    |> Core.repo().update_all(set: [local_curated: false, imported_curated: false, note: nil])

    rederive(species_id, country)
  end

  defp put_unless(attrs, true, _key, _value), do: attrs
  defp put_unless(attrs, _curated, key, value), do: Map.put(attrs, key, value)

  defp put_curated(changes, _field, flag, nil), do: Map.put(changes, flag, false)

  defp put_curated(changes, field, flag, value),
    do: changes |> Map.put(field, value) |> Map.put(flag, true)

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
