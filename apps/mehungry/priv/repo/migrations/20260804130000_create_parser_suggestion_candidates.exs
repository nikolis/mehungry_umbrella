defmodule Mehungry.Repo.Migrations.CreateParserSuggestionCandidates do
  use Ecto.Migration

  # Append-only, review-gated suggestions from the semantic layer — never facts.
  # For a low-confidence deterministic parse, a row proposes that the unresolved
  # surface string most likely maps to an existing canonical food, at a cosine
  # score from Mehungry.AI.SemanticMatcher. Accepting one grows the vocabulary
  # through the EXISTING alias path (ParserVocabulary.add_food_alias/2); rejecting
  # keeps it for history. The deterministic parser never consults this table.
  def change do
    create table(:parser_suggestion_candidates) do
      add :ingredient_parsed_food_id,
          references(:ingredient_parsed_foods, on_delete: :delete_all),
          null: false

      # :canonical_food — surface_text ≈ an existing canonical food (alias candidate)
      # :merge          — two canonical foods look like duplicates (dedup candidate)
      add :suggestion_kind, :string, null: false, default: "canonical_food"

      # The unresolved string the parser produced (free-text head / :unknown token).
      add :surface_text, :string, null: false

      # The nearest existing lexicon entry proposed for it.
      add :suggested_target, :string, null: false
      add :suggested_canonical_food_id, references(:canonical_foods, on_delete: :nilify_all)

      add :score, :float, null: false
      add :status, :string, null: false, default: "candidate"
      add :model_version, :string, null: false

      add :reviewed_by_user_id, :id
      add :reviewed_at, :utc_datetime
      add :notes, :string

      timestamps()
    end

    create index(:parser_suggestion_candidates, [:status])
    create index(:parser_suggestion_candidates, [:ingredient_parsed_food_id])
    create index(:parser_suggestion_candidates, [:suggested_canonical_food_id])

    # One live suggestion per (parse, target, kind) so re-running the generator
    # is idempotent and never piles up duplicate candidates.
    create unique_index(
             :parser_suggestion_candidates,
             [:ingredient_parsed_food_id, :suggested_target, :suggestion_kind],
             name: :one_suggestion_per_parse_target_kind
           )
  end
end
