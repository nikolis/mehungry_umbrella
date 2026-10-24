defmodule MehungryWeb.ProfessionalLive.ImportReviewComponents do
  @moduledoc """
  Shared UI + builders for the admin recipe-import review screens (MyPlate /
  Gutenberg / UniTools), so all three reviewers are **identical**: the left column
  is the editable `RecipeFormComponent`, the right column is this reference panel —
  every source ingredient line (the matched ones resolved to their DB ingredient,
  the unmatched ones badged so the admin sees what still needs a hand-match), then
  the source steps.

  The builders are pure and consume the `{attrs, unmatched}` pair every importer's
  `build_recipe_attrs/*` returns (all importers share `RecipeIngredientResolver`,
  so the shapes are the same: matched recipe_ingredients carry `:ingredient_id` +
  `:ingredient_allias`, unmatched are `%{original, reason, …}`, and `attrs.steps`
  is `[%{index, description}]`).
  """

  use Phoenix.Component

  import MehungryWeb.CoreComponents, only: [icon: 1]

  @doc "The right-column reference panel: ingredient overview + source steps."
  attr :overview, :list, required: true
  attr :steps, :list, required: true

  def ingredient_reference(assigns) do
    ~H"""
    <div class="space-y-5">
      <div>
        <div class="flex items-center gap-2 mb-2">
          <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] font-semibold uppercase tracking-wider bg-ink-panel2 text-parchment-dim border border-ink-panel2">
            <.icon name="hero-list-bullet" class="w-3.5 h-3.5 text-basil" /> Ingredients
          </span>
          <span class="text-xs text-parchment-dim">Source lines — badged if not matched</span>
        </div>
        <ul class="space-y-1.5 max-h-[45vh] overflow-auto custom-scrollbar pr-1">
          <li
            :for={row <- @overview}
            class={[
              "flex items-start justify-between gap-2 px-3 py-2 rounded-lg border",
              if(row.matched,
                do: "bg-ink-panel border-ink-panel2",
                else: "bg-amber-500/10 border-amber-500/30"
              )
            ]}
          >
            <div class="min-w-0">
              <p class="text-sm text-parchment">{row.original}</p>
              <p :if={row.resolved} class="text-[11px] text-basil truncate">
                → {row.resolved}
              </p>
              <p :if={row.reason} class="text-[11px] text-amber-300/80">
                {row.reason}
              </p>
            </div>
            <span
              :if={not row.matched}
              class="shrink-0 inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-semibold bg-amber-500/20 text-amber-300 border border-amber-500/30"
            >
              unmatched
            </span>
          </li>
          <li :if={@overview == []} class="text-sm text-parchment-dim px-1">
            No ingredients parsed from the source.
          </li>
        </ul>
      </div>

      <div :if={@steps != []}>
        <div class="flex items-center gap-2 mb-2">
          <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] font-semibold uppercase tracking-wider bg-ink-panel2 text-parchment-dim border border-ink-panel2">
            <.icon name="hero-queue-list" class="w-3.5 h-3.5 text-basil" /> Steps
          </span>
          <span class="text-xs text-parchment-dim">Source directions</span>
        </div>
        <ol class="space-y-1.5">
          <li
            :for={{step, i} <- Enum.with_index(@steps, 1)}
            class="flex items-start gap-2.5 px-3 py-2 rounded-lg bg-ink-panel border border-ink-panel2"
          >
            <span class="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-ink-panel2 text-[11px] font-bold tabular-nums text-basil">
              {i}
            </span>
            <p class="text-sm text-parchment">{step}</p>
          </li>
        </ol>
      </div>
    </div>
    """
  end

  @doc """
  Builds the ingredient-overview rows from an importer's `attrs` + `unmatched`:
  the matched source lines (resolved to their DB ingredient name via `ingredients`)
  followed by the unmatched lines (flagged with their reason).
  """
  def build_overview(attrs, unmatched, ingredients) do
    names = Map.new(ingredients, fn ing -> {ing.id, ing.name} end)

    matched =
      Enum.map(attrs.recipe_ingredients, fn ri ->
        %{
          original: Map.get(ri, :ingredient_allias),
          resolved: Map.get(names, Map.get(ri, :ingredient_id)),
          matched: true,
          reason: nil
        }
      end)

    unmatched =
      Enum.map(unmatched, fn info ->
        %{
          original: Map.get(info, :original),
          resolved: nil,
          matched: false,
          reason: Map.get(info, :reason)
        }
      end)

    matched ++ unmatched
  end

  @doc "The source step descriptions from an importer's `attrs` (drops blanks)."
  def source_steps(attrs) do
    attrs
    |> Map.get(:steps, [])
    |> Enum.map(&Map.get(&1, :description))
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
  end
end
