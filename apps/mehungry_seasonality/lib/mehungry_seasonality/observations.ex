defmodule MehungrySeasonality.Observations do
  @moduledoc """
  Storage of the raw fetched signals. Each fetch **replaces** a species × country's
  twelve monthly rows for a source wholesale (delete + insert in one transaction), so
  the tables always reflect the latest fetch and nothing stale lingers when a mapping
  is removed.
  """

  import Ecto.Query, warn: false

  alias MehungrySeasonality.{Core, ImportObservation, LocalObservation}

  @doc """
  Replace the local observations of a species × country with a parsed agri-food
  result (`%{years, months}`). Returns the number of months stored.
  """
  def replace_local(species_id, country, %{years: years, months: months}) do
    rows =
      Enum.map(months, fn {month, m} ->
        base(species_id, country, month)
        |> Map.merge(%{
          weeks_quoted: m.weeks_quoted,
          weeks_possible: m.weeks_possible,
          years: years
        })
      end)

    replace(LocalObservation, species_id, country, rows)
  end

  @doc """
  Replace the import observations of a species × country with a parsed Comext result
  (`%{years, months}`). Returns the number of months stored.
  """
  def replace_imports(species_id, country, %{years: years, months: months}) do
    rows =
      Enum.map(months, fn {month, m} ->
        base(species_id, country, month)
        |> Map.merge(%{tonnes_avg: m.tonnes_avg, origins: m.origins, years: years})
      end)

    replace(ImportObservation, species_id, country, rows)
  end

  @doc "Local observations of a species × country, keyed by month."
  def local_by_month(species_id, country), do: by_month(LocalObservation, species_id, country)

  @doc "Import observations of a species × country, keyed by month."
  def imports_by_month(species_id, country), do: by_month(ImportObservation, species_id, country)

  @doc "Every local observation of a country, keyed by `{species_id, month}`."
  def local_for_country(country), do: for_country(LocalObservation, country)

  @doc "Every import observation of a country, keyed by `{species_id, month}`."
  def imports_for_country(country), do: for_country(ImportObservation, country)

  defp replace(schema, species_id, country, rows) do
    {:ok, count} =
      Core.repo().transaction(fn ->
        Core.repo().delete_all(scope(schema, species_id, country))
        {count, _} = Core.repo().insert_all(schema, rows)
        count
      end)

    count
  end

  defp by_month(schema, species_id, country) do
    schema |> scope(species_id, country) |> Core.repo().all() |> Map.new(&{&1.month, &1})
  end

  defp for_country(schema, country) do
    from(o in schema, where: o.country == ^country)
    |> Core.repo().all()
    |> Map.new(&{{&1.foundemental_species_id, &1.month}, &1})
  end

  defp scope(schema, species_id, country) do
    from(o in schema, where: o.foundemental_species_id == ^species_id and o.country == ^country)
  end

  defp base(species_id, country, month) do
    # `timestamps()` columns are :naive_datetime; insert_all needs them explicit.
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    %{
      foundemental_species_id: species_id,
      country: country,
      month: month,
      retrieved_at: DateTime.utc_now() |> DateTime.truncate(:second),
      inserted_at: now,
      updated_at: now
    }
  end
end
