defmodule Mehungry.Food.CompoundMeasurements do
  @moduledoc """
  Quantitative scientific measurements of compounds in ingredients — the
  numbers a research paper reports (e.g. *Spinach, Oxalate, Raw: 750 mg/100g*).

  A `CompoundMeasurement` is a single **immutable** observation. This context is
  deliberately insert-and-read only:

    * `record_measurement/1` — idempotent insert. Re-recording the same
      observation returns the original row **unchanged**; it never overwrites a
      historical value.
    * `create_measurement/1` — strict insert that surfaces the duplicate as a
      changeset error (for callers that want to know).

  There is no update or upsert-replace path. A new study reporting a different
  value creates a *new* measurement, so conflicting values coexist. Aggregating
  across measurements (means, ranges, per-preparation summaries) is a separate
  read-only concern that reads these rows and never mutates them.

  Like `Mehungry.Food.Compounds`, this sidecar is keyed by `ingredient_id`/
  `compound_id` and is never touched by the USDA ingestion path. It records
  **scientific facts only** — never recommendations or dietary advice.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Food.CompoundMeasurement

  # The columns that identify "the same measurement" for dedup on re-extraction.
  @natural_key [:study_id, :ingredient_id, :compound_id, :preparation_method, :analytical_method]

  # ── Writes (insert-only — measurements are immutable) ──────────────────────

  @doc "Strict insert of a measurement; a duplicate surfaces as a changeset error."
  def create_measurement(attrs) do
    %CompoundMeasurement{}
    |> CompoundMeasurement.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Idempotent insert. On the natural key
  `(study_id, ingredient_id, compound_id, preparation_method, analytical_method)`
  a conflict does **nothing** — the original, immutable row is preserved and
  returned unchanged, never overwritten with the incoming value.

  Safe to call repeatedly from automated / PDF extraction re-runs.
  """
  def record_measurement(attrs) do
    %CompoundMeasurement{}
    |> CompoundMeasurement.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: @natural_key)
    |> case do
      # on_conflict: :nothing skipped the write — reload the pre-existing row.
      {:ok, %CompoundMeasurement{id: nil}} -> {:ok, get_existing_measurement(attrs)}
      other -> other
    end
  end

  defp get_existing_measurement(attrs) do
    attrs = Map.new(attrs)

    where =
      Enum.reduce(@natural_key, dynamic(true), fn field, acc ->
        case Map.get(attrs, field) || Map.get(attrs, to_string(field)) do
          nil -> dynamic([m], ^acc and is_nil(field(m, ^field)))
          value -> dynamic([m], ^acc and field(m, ^field) == ^value)
        end
      end)

    Repo.one(from(m in CompoundMeasurement, where: ^where))
  end

  # ── Reads (raw rows — aggregation is a separate layer) ─────────────────────

  def get_measurement!(id), do: Repo.get!(CompoundMeasurement, id)

  @doc "All measurements recorded for an ingredient (newest first)."
  def list_measurements_for_ingredient(ingredient_id) do
    Repo.all(
      from(m in CompoundMeasurement,
        where: m.ingredient_id == ^ingredient_id,
        order_by: [desc: m.inserted_at, desc: m.id]
      )
    )
  end

  @doc "All measurements recorded for a compound (newest first)."
  def list_measurements_for_compound(compound_id) do
    Repo.all(
      from(m in CompoundMeasurement,
        where: m.compound_id == ^compound_id,
        order_by: [desc: m.inserted_at, desc: m.id]
      )
    )
  end

  @doc "All measurements a study reported."
  def list_measurements_for_study(study_id) do
    Repo.all(
      from(m in CompoundMeasurement,
        where: m.study_id == ^study_id,
        order_by: [asc: m.id]
      )
    )
  end

  @doc """
  Every measurement of `compound_id` in `ingredient_id`, across all studies —
  the raw input an aggregation layer reads to summarize (mean, range, …).
  """
  def list_measurements(ingredient_id, compound_id) do
    Repo.all(
      from(m in CompoundMeasurement,
        where: m.ingredient_id == ^ingredient_id and m.compound_id == ^compound_id,
        order_by: [asc: m.id]
      )
    )
  end
end
