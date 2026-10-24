defmodule Mehungry.ObanWorkers.ResourceTranslationWorker do
  @moduledoc """
  Bulk, descriptor-driven AI translation for any registry resource. Given a
  resource key, a target locale and a chunk of base-row ids, it machine-translates
  each row and upserts the result as an **`ai_draft`** — a human still verifies it
  in the translation hub. The "AI-translate all missing" button enqueues these in
  batches. Runs on the `:ai_agents` queue (shared with recipe generation) so it
  stays within the DB pool budget.
  """

  use Oban.Worker, queue: :ai_agents, max_attempts: 3

  require Logger

  alias Mehungry.Repo
  alias Mehungry.Food
  alias Mehungry.AI.{FieldTranslator, RecipeTranslator}
  alias Mehungry.Languages.{Locale, Translations, TranslationRegistry}

  @batch_size 25

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"resource" => key, "language" => locale, "ids" => ids} = args}) do
    case TranslationRegistry.get(key) do
      nil ->
        Logger.error("[ResourceTranslationWorker] unknown resource #{inspect(key)}")
        {:discard, :unknown_resource}

      descriptor ->
        # `portions_only` targets already-translated ingredients: fill just their
        # missing portion translations without touching the (possibly verified)
        # base name/description translation.
        if Map.get(args, "portions_only", false) do
          Enum.each(ids, &translate_and_store_portions(descriptor, &1, locale))
        else
          Enum.each(ids, &translate_and_store(descriptor, &1, locale))
        end

        :ok
    end
  end

  @doc """
  Enqueue AI-draft translation of `ids` for a resource + locale, chunked into
  per-job batches. Returns `{:ok, job_count}`.
  """
  def enqueue_all(key, locale, ids) do
    enqueue_jobs(fn chunk -> new(%{resource: key, language: locale, ids: chunk}) end, ids)
  end

  @doc """
  Enqueue a **portions-only** AI-draft run for `ids` — fills missing
  `IngredientPortion` translations for otherwise-translated ingredients, leaving
  their base translation untouched. Returns `{:ok, job_count}`.
  """
  def enqueue_portions_only(key, locale, ids) do
    enqueue_jobs(
      fn chunk -> new(%{resource: key, language: locale, ids: chunk, portions_only: true}) end,
      ids
    )
  end

  defp enqueue_jobs(job_fun, ids) do
    jobs =
      ids
      |> Enum.chunk_every(@batch_size)
      |> Enum.map(job_fun)

    case Oban.insert_all(jobs) do
      inserted when is_list(inserted) -> {:ok, length(inserted)}
      other -> other
    end
  end

  defp translate_and_store(descriptor, base_id, locale) do
    with base when not is_nil(base) <- Repo.get(descriptor.base_schema, base_id),
         {:ok, field_values} <- translate(descriptor, base, locale) do
      Translations.upsert(descriptor, base_id, locale, field_values, status: "ai_draft")
      translate_and_store_portions(descriptor, base_id, locale)
    else
      nil ->
        Logger.warning("[ResourceTranslationWorker] #{descriptor.key} ##{base_id} not found")

      {:error, reason} ->
        Logger.error(
          "[ResourceTranslationWorker] #{descriptor.key} ##{base_id} failed: #{inspect(reason)}"
        )
    end
  end

  # For descriptors flagged `:translate_portions` (ingredients), AI-draft the
  # unit-less free-text portion descriptions that are **still missing** a
  # translation (keyed by portion id). Only the missing ones, so a re-run — or a
  # portions-only run over an already-translated ingredient — never clobbers an
  # existing (possibly verified) portion translation.
  defp translate_and_store_portions(descriptor, base_id, locale) do
    if descriptor[:translate_portions] do
      items =
        base_id
        |> Food.list_portion_translation_pairs(locale)
        |> Enum.filter(fn %{translation: t} -> is_nil(t) end)
        |> Enum.map(fn %{portion: p} -> %{id: p.id, fields: %{description: p.description}} end)

      case items do
        [] ->
          :ok

        _ ->
          case FieldTranslator.translate_batch(items, locale, hint: "cooking serving/portion label") do
            {:ok, result} ->
              Enum.each(result, fn {portion_id, fields} ->
                Food.upsert_portion_translation(portion_id, locale, Map.get(fields, :description),
                  status: "ai_draft"
                )
              end)

            {:error, reason} ->
              Logger.error(
                "[ResourceTranslationWorker] #{descriptor.key} ##{base_id} portions failed: #{inspect(reason)}"
              )
          end
      end
    end

    :ok
  end

  defp translate(%{ai: :recipe} = _descriptor, base, locale) do
    case RecipeTranslator.translate_recipe(base, Locale.write_code(locale)) do
      {:ok, %{title: title, description: description, steps: steps}} ->
        {:ok, %{title: title, description: description, steps: steps}}

      error ->
        error
    end
  end

  defp translate(%{ai: :fields} = descriptor, base, locale) do
    field_values =
      descriptor.fields
      |> Map.new(fn field -> {field, Map.get(base, field)} end)

    FieldTranslator.translate_fields(field_values, locale, hint: descriptor.ai_hint)
  end
end
