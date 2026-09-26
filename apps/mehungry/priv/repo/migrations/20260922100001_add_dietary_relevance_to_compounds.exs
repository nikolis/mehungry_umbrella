defmodule Mehungry.Repo.Migrations.AddDietaryRelevanceToCompounds do
  use Ecto.Migration

  import Ecto.Query

  alias Mehungry.Repo

  # Curatable dietary-relevance attribute on the compound registry. Replaces the
  # exact-name `:non_dietary_compounds` blocklist as the source of truth for which
  # compounds must never become dietary facts. `non_dietary` compounds are excluded
  # from candidate derivation and health advice; `pending` (the default) is allowed
  # so existing good facts are preserved; `dietary` is an admin-confirmed constituent.
  def up do
    alter table(:compounds) do
      add :dietary_relevance, :string, null: false, default: "pending"
    end

    create index(:compounds, [:dietary_relevance])

    flush()

    # Backfill `non_dietary` from the config seed list — the compounds the old
    # blocklist targeted (assay reagents / solvents / non-specific class terms).
    # Matched case-insensitively against the compound name or any synonym.
    seed_names =
      :mehungry
      |> Application.get_env(:non_dietary_compounds, [])
      |> Enum.map(&String.downcase/1)

    if seed_names != [] do
      compound_ids =
        from(c in "compounds",
          where:
            fragment("lower(?)", c.name) in ^seed_names or
              fragment(
                "EXISTS (SELECT 1 FROM unnest(?) syn WHERE lower(syn) = ANY(?))",
                c.synonyms,
                ^seed_names
              ),
          select: c.id
        )
        |> Repo.all()

      if compound_ids != [] do
        from(c in "compounds", where: c.id in ^compound_ids)
        |> Repo.update_all(set: [dietary_relevance: "non_dietary"])
      end
    end
  end

  def down do
    drop index(:compounds, [:dietary_relevance])

    alter table(:compounds) do
      remove :dietary_relevance
    end
  end
end
