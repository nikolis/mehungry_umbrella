defmodule Mehungry.AI.FieldTranslator do
  @moduledoc """
  Generic AI translator for short, free-text DB fields (a compound's name, a
  condition's description, a unit's alternate name…). Given a map of
  `field => text`, it returns the same shape with each value translated into the
  target locale. Built on `Mehungry.AI.Client`, like `AI.RecipeTranslator` and
  `AI.IngredientTranslator`, but resource-agnostic — the translatable fields and
  a domain `:hint` come from the caller (the translation registry).

  Used by the professional translation hub (per-item and bulk drafts) for every
  field-based resource. Recipes keep their structured `AI.RecipeTranslator`.
  """

  require Logger

  alias Mehungry.Languages.Locale

  @model "claude-sonnet-4-6"

  @doc """
  Translate a `%{field => text}` map into `locale`.

  Empty/nil values are passed through untranslated. `opts[:hint]` is a short
  domain description (e.g. "bioactive compound") to steer terminology.
  Returns `{:ok, %{field => translated_text}}` or `{:error, reason}`.
  """
  def translate_fields(field_values, locale, opts \\ []) when is_map(field_values) do
    {translatable, passthrough} =
      Enum.split_with(field_values, fn {_k, v} -> is_binary(v) and String.trim(v) != "" end)

    case translatable do
      [] ->
        {:ok, field_values}

      _ ->
        language = Locale.label(locale)
        hint = Keyword.get(opts, :hint, "content")
        payload = Map.new(translatable, fn {k, v} -> {to_string(k), v} end)

        case call(system_prompt(language, hint), Jason.encode!(payload), 2048) do
          {:ok, decoded} ->
            translated =
              Enum.reduce(translatable, %{}, fn {k, original}, acc ->
                Map.put(acc, k, Map.get(decoded, to_string(k)) || original)
              end)

            {:ok, Map.merge(Map.new(passthrough), translated)}

          error ->
            error
        end
    end
  end

  @doc """
  Translate many items in one request. `items` is a list of
  `%{id: term, fields: %{field => text}}`. Returns
  `{:ok, %{id => %{field => translated_text}}}` or `{:error, reason}`.
  """
  def translate_batch(items, locale, opts \\ []) when is_list(items) do
    language = Locale.label(locale)
    hint = Keyword.get(opts, :hint, "content")

    payload =
      Map.new(items, fn %{id: id, fields: fields} ->
        {to_string(id), Map.new(fields, fn {k, v} -> {to_string(k), v} end)}
      end)

    case call(batch_system_prompt(language, hint), Jason.encode!(payload), 4096) do
      {:ok, decoded} ->
        result =
          Map.new(items, fn %{id: id, fields: fields} ->
            translated = Map.get(decoded, to_string(id), %{})

            merged =
              Map.new(fields, fn {k, original} ->
                {k, Map.get(translated, to_string(k)) || original}
              end)

            {id, merged}
          end)

        {:ok, result}

      error ->
        error
    end
  end

  # ── internals ──────────────────────────────────────────────────────────────

  defp call(system, user, max_tokens) do
    case Mehungry.AI.Client.request(%{
           model: @model,
           system: system,
           messages: [%{role: "user", content: user}],
           max_tokens: max_tokens
         }) do
      {:ok, response} ->
        response
        |> Mehungry.AI.Client.text_from()
        |> parse_json()

      error ->
        error
    end
  end

  defp system_prompt(language, hint) do
    """
    You are a professional translator localizing a food & health app into #{language}.
    You will receive a JSON object whose values are short pieces of text describing
    a #{hint}. Translate each value naturally into #{language}, keeping domain
    terminology accurate for a general audience.

    Rules:
    - Preserve the exact set of keys. Do not add, drop, or rename keys.
    - Translate the values only; never translate the keys.
    - Keep proper nouns / chemical names in their common #{language} form.
    - Return ONLY valid JSON, no markdown fences, no explanation.
    """
  end

  defp batch_system_prompt(language, hint) do
    """
    You are a professional translator localizing a food & health app into #{language}.
    You will receive a JSON object mapping each item id to an object of short text
    fields describing a #{hint}. Translate every field value into #{language}.

    Rules:
    - Preserve the exact structure: the same ids and the same field keys.
    - Translate the values only; never translate keys or ids.
    - Keep proper nouns / chemical names in their common #{language} form.
    - Return ONLY valid JSON, no markdown fences, no explanation.
    """
  end

  defp parse_json(text) do
    cleaned =
      text
      |> String.trim()
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, map} when is_map(map) ->
        {:ok, map}

      {:ok, other} ->
        Logger.warning("FieldTranslator: unexpected response shape: #{inspect(other)}")
        {:error, "Unexpected response format"}

      {:error, _} ->
        Logger.warning("FieldTranslator: could not parse JSON: #{inspect(text)}")
        {:error, "Could not parse translation response"}
    end
  end
end
