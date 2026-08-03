defmodule Mehungry.Repo.Migrations.AddRawSpanToCompoundMeasurements do
  use Ecto.Migration

  # Provenance for auto-extracted measurements: the source sentence the value came
  # from, carried over from the review candidate on accept so the context (e.g.
  # "reduced by 40%" vs a real composition) isn't lost once it becomes a fact.
  def change do
    alter table(:compound_measurements) do
      add :raw_span, :text
    end
  end
end
