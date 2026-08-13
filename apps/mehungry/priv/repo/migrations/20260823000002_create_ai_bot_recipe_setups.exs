defmodule Mehungry.Repo.Migrations.CreateAiBotRecipeSetups do
  use Ecto.Migration

  def change do
    create table(:ai_bot_recipe_setups) do
      add :name, :string, null: false
      add :persona_id, references(:ai_bot_personas, on_delete: :nilify_all)
      # Free-text place hierarchy, e.g. "Rethymno -> Crete -> Greece".
      add :origin, :string
      add :story, :text
      add :condition_id, references(:conditions, on_delete: :nilify_all)
      add :diet_direction, :string
      add :active, :boolean, null: false, default: true

      timestamps()
    end

    create index(:ai_bot_recipe_setups, [:persona_id])
    create index(:ai_bot_recipe_setups, [:condition_id])
    create unique_index(:ai_bot_recipe_setups, [:name])
  end
end
