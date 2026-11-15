defmodule Mehungry.Repo.Migrations.AddQueryToFactMiningRuns do
  use Ecto.Migration

  # The admin can now customize the prompt per single-entity mine; persist what was
  # sent so the streamed tracking row is auditable. Nullable — dormant bulk rows and
  # pre-existing rows keep NULL (worker falls back to the default query builder).
  def change do
    alter table(:species_fact_mining_runs) do
      add :query, :text
    end

    alter table(:condition_fact_mining_runs) do
      add :query, :text
    end
  end
end
