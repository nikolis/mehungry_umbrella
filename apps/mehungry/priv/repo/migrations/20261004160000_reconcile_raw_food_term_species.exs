defmodule Mehungry.Repo.Migrations.ReconcileRawFoodTermSpecies do
  use Ecto.Migration

  # One-off cleanup: a suggestion verified while its term was unknown is stored as a
  # free-text `raw_food_term` state recommendation. If that term is later curated as a
  # `FoundementalFoodSpecies`, the stored row goes stale — the admin re-derives the
  # suggestion as a species match whose target key no longer lines up with the raw row,
  # so it reads as "not accepted" and renders as a free-text note instead of a food card.
  #
  # Re-point such rows onto the matching species (by name / scientific name), clearing
  # the free-text term and recomputing `dedup_key`, dropping any that would collide with
  # a species row the condition already has.
  def up do
    repo = repo()

    %{rows: species} =
      repo.query!(
        "SELECT id, lower(trim(name)), lower(trim(scientific_name)) FROM foundemental_food_species"
      )

    by_name =
      Enum.reduce(species, %{}, fn [id, name, sci], acc ->
        acc = if name in [nil, ""], do: acc, else: Map.put_new(acc, name, id)
        if sci in [nil, ""], do: acc, else: Map.put_new(acc, sci, id)
      end)

    %{rows: recs} =
      repo.query!("""
      SELECT id, condition_id, condition_state_id, raw_food_term, source, dedup_key
      FROM condition_state_recommendations
      WHERE raw_food_term IS NOT NULL AND raw_food_term <> ''
        AND species_id IS NULL AND blueprint_id IS NULL AND compound_id IS NULL
        AND (nutrient_name IS NULL OR nutrient_name = '')
      """)

    Enum.each(recs, fn [id, condition_id, state_id, raw, source, _dedup] ->
      case Map.get(by_name, raw |> to_string() |> String.trim() |> String.downcase()) do
        nil ->
          :ok

        species_id ->
          new_key = "#{condition_id}|#{state_id || 0}|s#{species_id}|#{source}"

          %{rows: clash} =
            repo.query!(
              "SELECT 1 FROM condition_state_recommendations WHERE dedup_key = $1 AND id <> $2 LIMIT 1",
              [new_key, id]
            )

          if clash == [] do
            repo.query!(
              "UPDATE condition_state_recommendations SET species_id = $1, raw_food_term = NULL, dedup_key = $2 WHERE id = $3",
              [species_id, new_key, id]
            )
          else
            repo.query!("DELETE FROM condition_state_recommendations WHERE id = $1", [id])
          end
      end
    end)
  end

  # Irreversible data reconciliation.
  def down, do: :ok
end
