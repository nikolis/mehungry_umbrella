defmodule Mehungry.FoodData.Usda.Importer do
  @moduledoc """
  Imports individual USDA FoodData Central foods into the shared ingredient
  catalogue by their known `fdc_id`, with full USDA detail (nutrients, portions,
  category).

  This is the single composition of "fetch one FDC food + persist it" shared by
  every by-id import surface — the admin Ingredients LiveView ("Import from
  USDA") and `Mehungry.Release.import_usda_ingredients/1` (eval-time backfill) —
  so they can never drift.

  The fetch goes through `FdcClient.fetch_food/1` (which transparently recovers
  Foundation foods the public `/food/{id}` endpoint 404s on via the USDA portal
  datastore), and persistence through the same `FoodParser.create_ingredient/2`
  path as bulk seeding, so imports are idempotent: re-importing an `fdc_id`
  updates the existing row (upsert on name) rather than duplicating it.
  """

  require Logger

  alias Mehungry.Food
  alias Mehungry.FoodData.Usda.{FdcClient, FoodParser}
  alias Mehungry.Repo

  @source "usda"

  @doc """
  Imports one USDA food by `fdc_id`. Returns `{:ok, ingredient}` with the
  persisted row, or `{:error, reason}` when the FDC fetch failed or the record
  carried no usable name.
  """
  @spec import_by_fdc_id(integer()) :: {:ok, struct()} | {:error, term()}
  def import_by_fdc_id(fdc_id) do
    case FdcClient.fetch_food(fdc_id) do
      {:ok, attrs, _meta} -> persist(attrs)
      {:error, _} = err -> err
    end
  end

  @doc """
  Imports several USDA foods by id, returning a per-id result list of
  `{fdc_id, :ok | :error, label}` where `label` is the ingredient name on
  success or the inspected error on failure. Does not stop on the first error —
  every id is attempted.
  """
  @spec import_by_fdc_ids([integer()]) :: [{integer(), :ok | :error, String.t()}]
  def import_by_fdc_ids(fdc_ids) when is_list(fdc_ids) do
    Enum.map(fdc_ids, fn fdc_id ->
      case import_by_fdc_id(fdc_id) do
        {:ok, ingredient} -> {fdc_id, :ok, ingredient.name}
        {:error, reason} -> {fdc_id, :error, inspect(reason)}
      end
    end)
  end

  defp persist(attrs) do
    case attrs["description"] do
      name when is_binary(name) and name != "" ->
        with :ok <- create_ingredient_atomically(attrs) do
          case Food.get_ingredient_by_name(name) do
            nil -> {:error, :not_persisted}
            ingredient -> {:ok, ingredient}
          end
        end

      _ ->
        {:error, :no_description}
    end
  end

  # `FoodParser.create_ingredient/2` persists the ingredient then its nutrients
  # and portions without a transaction of its own, and raises (via a `{:ok, _} =`
  # match) if a sparse/malformed USDA record fails a child changeset. Wrap it so
  # a bad record (a) can't leave a half-created ingredient behind and (b) surfaces
  # as a clean `{:error, reason}` instead of crashing the caller (the admin
  # LiveView or the eval-time backfill) with a raw MatchError.
  defp create_ingredient_atomically(attrs) do
    case Repo.transaction(fn -> FoodParser.create_ingredient(attrs, @source) end) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    error ->
      Logger.error(
        "[FoodData.Usda.Importer] import failed for fdc_id=#{inspect(attrs["fdcId"])}: " <>
          Exception.message(error)
      )

      {:error, Exception.message(error)}
  end
end
