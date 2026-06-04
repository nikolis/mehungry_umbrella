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

    # Explicitly list columns that exist at this point in migration history,
    # avoiding any fields added in later migrations (e.g. ingredient_interactions).
    import Ecto.Query

    recipes =
      repo.all(
        from r in Mehungry.Food.Recipe,
          select:
            struct(r, [
              :id,
              :author,
              :cooking_time_lower_limit,
              :cooking_time_upper_limit,
              :cousine,
              :description,
              :list_image_url,
              :image_url,
              :detail_image_url,
              :recipe_image_remote,
              :original_url,
              :preperation_time_lower_limit,
              :preperation_time_upper_limit,
              :primary_nutrients_size,
              :servings,
              :private,
              :title,
              :difficulty,
              :nutrients,
              :user_id,
              :language_name,
              :inserted_at,
              :updated_at
            ])
      )
      |> repo.preload([
        [recipe_ingredients: [:measurement_unit, :ingredient]],
        :user,
        comments: [:user, votes: [:user], comment_answers: [:user, votes: [:user]]]
      ])

    Enum.each(recipes, fn recipe ->
      {primary_size, nutrients} = Mehungry.Food.RecipeUtils.get_nutrients(recipe)

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
