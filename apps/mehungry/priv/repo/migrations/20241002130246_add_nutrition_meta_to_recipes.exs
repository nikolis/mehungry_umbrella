defmodule Mehungry.Repo.Migrations.AddNutritionMetaToRecipes do
  use Ecto.Migration

  def down do
    alter table(:recipes) do
      remove :nutrients
      remove :primary_nutrients_size
    end
  end

  def up do
    alter table(:recipes) do
      add :nutrients, :map, default: %{}
      add :primary_nutrients_size, :integer
    end

    flush()
    repo = repo()

    recipes =
      repo.all(Mehungry.Food.Recipe)
      |> repo.preload([
        [recipe_ingredients: [:measurement_unit, :ingredient]],
        :user,
        comments: [:user, votes: [:user], comment_answers: [:user, votes: [:user]]]
      ])

    Enum.each(recipes, fn recipe ->
      {primary_size, nutrients} = Mehungry.Food.RecipeUtils.get_nutrients(recipe)

      IO.inspect(primary_size)

      nutrients =
        nutrients
        |> Enum.map(fn x -> Map.new([{x.name, x}]) end)
        |> Enum.reduce(&Map.merge/2)

      changeset =
        Mehungry.Food.Recipe.changeset(recipe, %{
          nutrients: nutrients,
          primary_nutrients_size: primary_size
        })

      if !changeset.valid? do
        repo.update(changeset)
      else
        changeset =
          Mehungry.Food.Recipe.changeset(recipe, %{
            nutrients: nutrients,
            cooking_time_lower_limit: 1,
            preperation_time_lower_limit: 1,
            difficulty: 1,
            primary_nutrients_size: primary_size
          })

        repo.update(changeset)
      end
    end)
  end
end
