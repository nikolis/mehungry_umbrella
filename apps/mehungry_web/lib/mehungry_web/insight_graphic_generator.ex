defmodule MehungryWeb.InsightGraphicGenerator do
  @moduledoc """
  The full insight social-graphic generation pipeline as one call, shared by both
  trigger surfaces: the per-user `RecipeDetailsComponent` (via `start_async`) and
  the admin/bot `RecipeSocialGraphicWorker` (Oban).

  Select (`AI.RecipeInsight`) → caption (`AI.InsightCaptioner`, with deterministic
  fallback) → render (`InsightGraphic`) → upload (`Storage`) → persist
  (`Food.RecipeSocialGraphic`) → meter the quota (`Subscriptions.record_usage`).

  Always returns `{:ok, graphic} | {:error, reason}` — every exception (e.g.
  Storage not configured, a render failure) is caught and turned into an
  `{:error, message}` so callers never hang on a crash.
  """

  require Logger

  alias Mehungry.{Food, Storage, Subscriptions}
  alias Mehungry.AI.{InsightCaptioner, RecipeInsight}
  alias MehungryWeb.InsightGraphic

  @spec generate(integer(), integer() | nil) :: {:ok, struct()} | {:error, term()}
  def generate(recipe_id, user_id) do
    recipe = Food.get_recipe_no_caching!(recipe_id)
    candidates = RecipeInsight.candidates(recipe)
    macros = RecipeInsight.macros(recipe)

    meta =
      case InsightCaptioner.generate(recipe, candidates) do
        {:ok, meta} -> meta
        {:error, _} -> InsightCaptioner.fallback(recipe, candidates)
      end

    with {:ok, binary} <- InsightGraphic.render(recipe, %{headline: meta.headline, macros: macros}),
         key = "recipe_social_graphics/#{recipe_id}-#{System.system_time(:second)}.jpg",
         {:ok, %{url: url}} <- Storage.put(key, binary, content_type: "image/jpeg"),
         {:ok, graphic} <-
           Food.create_recipe_social_graphic(%{
             recipe_id: recipe_id,
             image_url: url,
             insight_type: meta.insight_type,
             headline: meta.headline,
             caption: meta.caption
           }) do
      if user_id, do: Subscriptions.record_usage(user_id, "graphic_generation")
      {:ok, graphic}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  rescue
    e ->
      Logger.error("InsightGraphicGenerator: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end
end
