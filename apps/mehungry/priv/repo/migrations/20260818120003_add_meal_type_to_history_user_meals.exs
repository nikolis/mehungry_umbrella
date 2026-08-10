defmodule Mehungry.Repo.Migrations.AddMealTypeToHistoryUserMeals do
  use Ecto.Migration

  def up do
    alter table(:history_user_meals) do
      add :meal_type, :string
    end

    # Backfill AI-generated meals, which stored their slot in `title`
    # ("Breakfast"/"Lunch"/"Dinner"). Everything else stays NULL (unsorted).
    execute("""
    UPDATE history_user_meals
    SET meal_type = lower(title)
    WHERE title IN ('Breakfast', 'Lunch', 'Dinner')
    """)
  end

  def down do
    alter table(:history_user_meals) do
      remove :meal_type
    end
  end
end
