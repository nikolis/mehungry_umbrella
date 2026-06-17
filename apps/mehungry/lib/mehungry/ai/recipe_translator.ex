defmodule Mehungry.AI.RecipeTranslator do
  require Logger

  @model "claude-sonnet-4-6"

  @language_names %{
    "el" => "Greek",
    "en" => "English"
  }

  @doc """
  Translates a recipe's title, description, and steps into the target language.
  Returns {:ok, %{title: string, description: string, steps: [%{index: int, description: string}]}}
  or {:error, reason}.
  """
  def translate_recipe(%{title: title, description: description} = recipe, target_language_name) do
    language = Map.get(@language_names, target_language_name, target_language_name)
    steps = Map.get(recipe, :steps, []) || []

    system = build_system_prompt(language)
    user = build_user_message(title, description, steps)

    case Mehungry.AI.Client.request(%{
           model: @model,
           system: system,
           messages: [%{role: "user", content: user}],
           max_tokens: 1024
         }) do
      {:ok, response} ->
        text = Mehungry.AI.Client.text_from(response)
        parse_translation(text, length(steps))

      error ->
        error
    end
  end

  defp build_system_prompt(language) do
    """
    You are a professional culinary translator specializing in recipe localization.
    Translate the provided recipe content into #{language}.

    Rules:
    - Translate naturally for a home cook audience, not literally word-for-word.
    - Preserve all cooking times, quantities, and temperatures exactly.
    - Keep ingredient names in their common #{language} kitchen form.
    - Maintain the same number of steps as the original.
    - Return ONLY valid JSON, no markdown fences, no explanation.

    Response format:
    {
      "title": "translated title",
      "description": "translated description",
      "steps": [
        {"index": 0, "description": "step 0 translated"},
        {"index": 1, "description": "step 1 translated"}
      ]
    }
    """
  end

  defp build_user_message(title, description, steps) do
    steps_text =
      steps
      |> Enum.map(fn step ->
        idx = Map.get(step, :index) || Map.get(step, "index") || 0
        desc = Map.get(step, :description) || Map.get(step, "description") || ""
        %{"index" => idx, "description" => desc}
      end)
      |> Jason.encode!()

    Jason.encode!(%{
      title: title,
      description: description,
      steps: steps_text
    })
  end

  defp parse_translation(text, original_step_count) do
    cleaned =
      text
      |> String.trim()
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, %{"title" => title, "description" => description, "steps" => steps}}
      when is_list(steps) ->
        parsed_steps =
          steps
          |> Enum.map(fn
            %{"index" => idx, "description" => desc} -> %{"index" => idx, "description" => desc}
            step -> step
          end)
          |> Enum.take(original_step_count)

        {:ok, %{title: title, description: description, steps: parsed_steps}}

      {:ok, other} ->
        Logger.warning("RecipeTranslator: unexpected response shape: #{inspect(other)}")
        {:error, "Unexpected response format"}

      {:error, _} ->
        Logger.warning("RecipeTranslator: failed to parse JSON: #{inspect(text)}")
        {:error, "Could not parse translation response"}
    end
  end
end
