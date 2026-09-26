defmodule Mehungry.Repo.Migrations.CreateNutrientRecommendations do
  use Ecto.Migration

  # The nutrient sibling of `compound_recommendations` (`Mehungry.Health`). Links a
  # health `Condition` to a nutrient — e.g. "Anti-Inflammatory: encourage Omega-3",
  # "Anti-Inflammatory: limit Saturated Fat".
  #
  # A recommendation references a nutrient by its canonical **name string**, never a
  # `nutrient_id` FK: the same nutrient name exists under several measurement units
  # (`nutrients` is unique on `[name, measurement_unit_id]`), and this matches how
  # blueprints store nutrient tags. The implicated foods resolve at read time by
  # thresholding `ingredient_nutrients.amount` (see Mehungry.Health.NutrientTargets).
  def up do
    create table(:nutrient_recommendations) do
      add :condition_id, references(:conditions, on_delete: :delete_all), null: false

      add :nutrient_name, :string, null: false
      add :recommendation, :string, null: false
      add :severity, :string
      add :evidence_level, :string
      add :source, :string, null: false
      add :notes, :text
      add :source_reference, :map

      timestamps()
    end

    # Never-overwrite natural key: one recommendation per condition/nutrient per
    # source; re-asserting from the same source upserts, a different source is a
    # distinct row.
    create unique_index(:nutrient_recommendations, [:condition_id, :nutrient_name, :source])
    create index(:nutrient_recommendations, [:condition_id])
  end

  def down do
    drop table(:nutrient_recommendations)
  end
end
