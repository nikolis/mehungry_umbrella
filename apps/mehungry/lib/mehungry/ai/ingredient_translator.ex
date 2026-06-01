defmodule Mehungry.AI.IngredientTranslator do
  @moduledoc false

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-haiku-4-5-20251001"
  @timeout_ms 60_000

  @doc """
  Translates a list of %{id: integer, name: string} maps into Greek.
  Returns {:ok, %{ingredient_id => greek_name}} or {:error, reason}.
  """
  def translate_to_greek(ingredients) when is_list(ingredients) do
    name_to_id = Map.new(ingredients, fn %{id: id, name: name} -> {name, id} end)
    names = Map.keys(name_to_id)

    system = """
    You are a food ingredient translator. Translate English food ingredient names to Greek.
    Return ONLY a valid JSON object mapping each English name to its Greek translation.
    Use common Greek culinary terminology. Do not add explanations or markdown.
    Example: {"chicken breast": "στήθος κοτόπουλου", "garlic": "σκόρδο"}
    """

    user = "Translate these ingredient names to Greek:\n#{Jason.encode!(names)}"

    case call_api(system, user) do
      {:ok, text} ->
        parse_translation_map(text, name_to_id)

      error ->
        error
    end
  end

  defp parse_translation_map(text, name_to_id) do
    cleaned =
      text
      |> String.trim()
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, map} when is_map(map) ->
        id_to_greek =
          map
          |> Enum.flat_map(fn {english_name, greek_name} ->
            case Map.get(name_to_id, english_name) do
              nil -> []
              id -> [{id, greek_name}]
            end
          end)
          |> Map.new()

        {:ok, id_to_greek}

      _ ->
        Logger.warning("IngredientTranslator: failed to parse response: #{inspect(text)}")
        {:error, "Could not parse translation response"}
    end
  end

  defp call_api(system, user) do
    api_key = Application.get_env(:mehungry, :anthropic_api_key, "")

    if api_key == "" do
      {:error, "ANTHROPIC_API_KEY is not configured"}
    else
      body =
        Jason.encode!(%{
          model: @model,
          max_tokens: 4096,
          system: system,
          messages: [%{role: "user", content: user}]
        })

      headers = [
        {"Content-Type", "application/json"},
        {"x-api-key", api_key},
        {"anthropic-version", "2023-06-01"}
      ]

      case HTTPoison.post(@api_url, body, headers, recv_timeout: @timeout_ms) do
        {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
          case Jason.decode(resp_body) do
            {:ok, %{"content" => [%{"text" => text} | _]}} ->
              {:ok, text}

            {:ok, response} ->
              Logger.warning("IngredientTranslator: unexpected API shape: #{inspect(response)}")
              {:error, "Unexpected API response format"}
          end

        {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} ->
          Logger.warning("IngredientTranslator: API error #{code}: #{resp_body}")
          {:error, "API returned status #{code}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.warning("IngredientTranslator: HTTP error: #{inspect(reason)}")
          {:error, "HTTP request failed: #{inspect(reason)}"}
      end
    end
  end
end
