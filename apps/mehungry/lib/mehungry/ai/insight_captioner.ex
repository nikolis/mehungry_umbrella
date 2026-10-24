defmodule Mehungry.AI.InsightCaptioner do
  @moduledoc """
  The AI step of the recipe insight social-graphic pipeline. Given a recipe and
  the priority-ranked insight candidates from `Mehungry.AI.RecipeInsight`, the
  model:

    1. **picks** the single most compelling characteristic to lead with, and
    2. **writes** a short branded `headline` (drawn on the graphic) plus a
       `caption` (the social post copy, with a few hashtags).

  This is the quota-metered AI feature (`"graphic_generation"`); it uses the
  shared `Mehungry.AI.Client` (never raw HTTP). On any AI failure the caller can
  fall back to `fallback/2`, which turns the top candidate into a headline/caption
  deterministically so a graphic can still be produced.
  """

  require Logger

  alias Mehungry.AI.Client

  @model "claude-haiku-4-5-20251001"

  @type result :: %{insight_type: String.t(), headline: String.t(), caption: String.t()}

  @doc """
  Returns `{:ok, %{insight_type, headline, caption}}` or `{:error, reason}`.

  `candidates` is the list from `RecipeInsight.candidates/1` (already ranked);
  the model may choose any of them but must keep its `type` as `insight_type`.
  """
  @spec generate(struct(), [map()]) :: {:ok, result()} | {:error, term()}
  def generate(recipe, candidates) do
    case Client.request(%{
           model: @model,
           system: system_prompt(),
           messages: [%{role: "user", content: user_message(recipe, candidates)}],
           max_tokens: 1024
         }) do
      {:ok, response} ->
        response |> Client.text_from() |> parse(candidates)

      error ->
        error
    end
  end

  @doc """
  Deterministic headline/caption from the top candidate — used when the AI call
  fails so the pipeline still produces a usable graphic.
  """
  @spec fallback(struct(), [map()]) :: result()
  def fallback(recipe, [top | _]) do
    %{
      insight_type: top.type,
      headline: top.headline_hint,
      caption: "#{recipe.title} — #{top.headline_hint}. #{default_tags()}"
    }
  end

  # ── prompt ─────────────────────────────────────────────────────────────────

  defp system_prompt do
    """
    You write short, punchy social-media copy for a healthy-recipe app called
    m3hungry. You are given a recipe and a ranked list of its standout
    nutritional characteristics (candidates). Pick the ONE most compelling
    candidate to lead with, then write copy for a shareable graphic.

    Rules:
    - Choose the single most attention-grabbing candidate. Prefer the earlier
      (higher-ranked) ones unless a later one is clearly more shareable.
    - "headline" is overlaid on the image: 2–5 words, title case, no emoji, no
      hashtags, no trailing punctuation. Base it on the chosen candidate's
      "headline_hint" but you may sharpen it.
    - "caption" is the post text: 1–2 upbeat sentences naming the dish, then
      3–5 relevant hashtags at the end. Keep it truthful to the candidate — do
      not invent nutrients or health claims not present in the candidate.
    - "insight_type" MUST be exactly the "type" of the candidate you chose.
    - Return ONLY valid JSON, no markdown fences, no explanation.

    Response format:
    {"insight_type": "...", "headline": "...", "caption": "..."}
    """
  end

  defp user_message(recipe, candidates) do
    Jason.encode!(%{
      recipe: %{title: recipe.title, description: to_string(recipe.description)},
      candidates: Enum.map(candidates, &Map.take(&1, [:type, :headline_hint, :detail]))
    })
  end

  # ── parse ──────────────────────────────────────────────────────────────────

  defp parse(text, candidates) do
    cleaned =
      text
      |> String.trim()
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, %{"insight_type" => type, "headline" => headline, "caption" => caption}}
      when is_binary(headline) and is_binary(caption) ->
        {:ok,
         %{
           insight_type: valid_type(type, candidates),
           headline: String.trim(headline),
           caption: String.trim(caption)
         }}

      {:ok, other} ->
        Logger.warning("InsightCaptioner: unexpected response shape: #{inspect(other)}")
        {:error, "Unexpected response format"}

      {:error, _} ->
        Logger.warning("InsightCaptioner: failed to parse JSON: #{inspect(text)}")
        {:error, "Could not parse caption response"}
    end
  end

  # Guard against the model returning a type not among the candidates.
  defp valid_type(type, candidates) do
    types = Enum.map(candidates, & &1.type)
    if type in types, do: type, else: List.first(types)
  end

  defp default_tags, do: "#healthyrecipes #m3hungry #eatwell"
end
