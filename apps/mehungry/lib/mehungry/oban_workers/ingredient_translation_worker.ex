defmodule Mehungry.IngredientTranslationWorker do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  import Ecto.Query

  alias Mehungry.AI.IngredientTranslator
  alias Mehungry.Food.Ingredient
  alias Mehungry.Food.IngredientTranslation
  alias Mehungry.Languages
  alias Mehungry.Repo

  @batch_size 50
  @language "el"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    ensure_greek_language()

    ingredients = fetch_untranslated_batch()

    case ingredients do
      [] ->
        Logger.info("IngredientTranslationWorker: all ingredients translated")
        :ok

      batch ->
        Logger.info("IngredientTranslationWorker: translating batch of #{length(batch)}")

        case IngredientTranslator.translate_to_greek(batch) do
          {:ok, id_to_greek} ->
            insert_translations(id_to_greek)
            enqueue_next_batch()
            :ok

          {:error, reason} ->
            Logger.warning("IngredientTranslationWorker: translation failed: #{reason}")
            {:error, reason}
        end
    end
  end

  defp fetch_untranslated_batch do
    translated_ids =
      from t in IngredientTranslation,
        where: t.language_name == @language,
        select: t.ingredient_id

    Repo.all(
      from i in Ingredient,
        where: i.id not in subquery(translated_ids),
        limit: @batch_size,
        select: %{id: i.id, name: i.name}
    )
  end

  defp insert_translations(id_to_greek) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      Enum.map(id_to_greek, fn {ingredient_id, greek_name} ->
        %{
          name: greek_name,
          language_name: @language,
          ingredient_id: ingredient_id,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(IngredientTranslation, rows,
      on_conflict: :nothing,
      conflict_target: [:ingredient_id, :language_name]
    )

    Logger.info("IngredientTranslationWorker: inserted #{length(rows)} translations")
  end

  defp ensure_greek_language do
    case Languages.get_language_by_name(@language) do
      nil -> Languages.create_language(%{name: @language})
      _ -> :ok
    end
  end

  defp enqueue_next_batch do
    %{} |> new() |> Oban.insert!()
  end
end
