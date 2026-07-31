defmodule Mehungry.Repo.Migrations.CreateIngredientParsedFoods do
  use Ecto.Migration

  def change do
    create table(:ingredient_parsed_foods) do
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false
      add :canonical_food_id, references(:canonical_foods, on_delete: :nilify_all)
      add :canonical_food_text, :string
      add :harvest_stage, :string, null: false, default: "mature"
      add :processing, {:array, :string}, null: false, default: []
      add :processing_modifiers, {:array, :string}, null: false, default: []
      add :packaging, :string, null: false, default: "na"
      add :confidence, :float
      add :skip_reason, :string
      add :parser_version, :string, null: false
      add :trace, :map
      add :status, :string, null: false, default: "candidate"
      add :verified_by_user_id, references(:users, on_delete: :nilify_all)
      add :verified_at, :utc_datetime
      add :superseded_by_id, references(:ingredient_parsed_foods, on_delete: :nilify_all)
      add :notes, :text

      timestamps()
    end

    create index(:ingredient_parsed_foods, [:ingredient_id])
    create index(:ingredient_parsed_foods, [:status, :parser_version])
    create index(:ingredient_parsed_foods, [:canonical_food_id])
    create unique_index(:ingredient_parsed_foods, [:ingredient_id, :parser_version])

    create unique_index(:ingredient_parsed_foods, [:ingredient_id],
             where: "status = 'verified'",
             name: :one_verified_parsed_food_per_ingredient
           )

    create table(:ingredient_food_parsing_runs) do
      add :status, :string, null: false, default: "pending"
      add :processed, :integer
      add :total, :integer
      add :error, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:ingredient_food_parsing_runs, [:status])
  end
end
