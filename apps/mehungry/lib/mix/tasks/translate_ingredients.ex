defmodule Mix.Tasks.Translate.Ingredients do
  @shortdoc "Enqueues Oban jobs to translate all ingredient names to Greek"

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    %{} |> Mehungry.IngredientTranslationWorker.new() |> Oban.insert!()
    Mix.shell().info("Ingredient translation job enqueued. Check Oban for progress.")
  end
end
