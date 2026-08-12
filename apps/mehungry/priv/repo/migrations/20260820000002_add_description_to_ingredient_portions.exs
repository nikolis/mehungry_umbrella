defmodule Mehungry.Repo.Migrations.AddDescriptionToIngredientPortions do
  use Ecto.Migration

  # USDA food portions frequently carry an "undetermined" measureUnit (id 9999)
  # while the human-readable label lives in `portionDescription` (e.g. "cake
  # square (average weight of whole item)", "jar Beech-Nut Stage 2 (4 oz)").
  # Historically the parser minted a measurement_unit from that free text, which
  # polluted the units table. `description` lets the portion keep that label
  # locally without creating a bogus measurement_unit. `measurement_unit_id` is
  # already nullable (references/2 without null: false), so a portion may now
  # carry a description and no unit.
  def change do
    alter table(:ingredient_portions) do
      add :description, :text
    end
  end
end
