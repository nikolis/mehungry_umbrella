defmodule Mehungry.RecipePutNutrientsWorker do
  use Oban.Worker,
    max_attempts: 3

  alias Mehungry.Repo
  alias Mehungry.Food
  alias Mehungry.Food.Recipe

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"recipe_id" => recipe_id}
      }) do
    IO.inspect(recipe_id, label: "Recipe id")

    recipe =
      Repo.get(Recipe, recipe_id)
      |> Repo.preload([
        [recipe_ingredients: [:measurement_unit, :ingredient]],
        :user,
        :recipe_hashtags,
        comments: [:user, votes: [:user], comment_answers: [:user, votes: [:user]]]
      ])

    changeset = Food.change_recipe(recipe)

    _create_post = Mehungry.Posts.create_post(recipe)

    Cachex.del(:recipes_cache, {Mehungry.Food, recipe_id})

    result =
      Food.put_nutrient_info(changeset, Map.from_struct(recipe))

    {:ok, Repo.update(result)}
  end
end
