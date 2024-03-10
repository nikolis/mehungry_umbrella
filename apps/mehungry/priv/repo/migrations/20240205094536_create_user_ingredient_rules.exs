defmodule Mehungry.Repo.Migrations.CreateUserIngredientRules do
  use Ecto.Migration

  def change do
    create table(:user_ingredient_rules) do
      add :user_id, references(:users, on_delete: :nothing)
      add :ingredient_id, references(:ingredients, on_delete: :nothing)
      add :food_restriction_type_id, references(:food_restriction_types, on_delete: :nothing)
      add :user_profile_id, references(:user_profiles, on_delete: :delete_all)

      timestamps()
    end

    create index(:user_ingredient_rules, [:user_profile_id])
    create index(:user_ingredient_rules, [:user_id])
    create index(:user_ingredient_rules, [:ingredient_id])
    create index(:user_ingredient_rules, [:food_restriction_type_id])
  end
end
