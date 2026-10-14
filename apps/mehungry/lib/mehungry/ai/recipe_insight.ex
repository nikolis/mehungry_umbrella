defmodule Mehungry.AI.RecipeInsight do
  @moduledoc """
  Derives a recipe's shareable "insights" from data the app already computes —
  the input to the insight social-graphic (`Mehungry.RecipeSocialGraphicWorker`).

  Two outputs:

    * `macros/1` — the per-serving macronutrient breakdown (protein / fat / carbs
      grams + calories) read straight from the cached `recipe.nutrients` jsonb
      map, divided by `servings`. This always drives the pie chart on the card.

    * `candidates/1` — a priority-ranked list of the recipe's most differentiated
      characteristics (`compound` → `health` → `macro` → `balanced` fallback),
      each `%{type, headline_hint, detail}`. The AI captioner picks the single
      most compelling one; the renderer draws it as the badge.

  Facts only — this reads existing nutrition / compound / health-flag data and
  never asserts anything new.
  """

  alias Mehungry.{Food, Health}

  # Per-serving thresholds for the macro "standout" heuristic.
  @high_protein_g 20
  @low_calorie_kcal 400
  @high_fiber_g 6

  @type macros :: %{
          calories: number(),
          protein_g: number(),
          fat_g: number(),
          carbs_g: number(),
          fiber_g: number() | nil
        }

  @type candidate :: %{type: String.t(), headline_hint: String.t(), detail: map()}

  @doc """
  Per-serving macro breakdown from the cached `recipe.nutrients` map. Returns
  zeros when a recipe has no computed nutrition.
  """
  @spec macros(struct()) :: macros()
  def macros(recipe) do
    servings = max(recipe.servings || 1, 1)
    n = recipe.nutrients || %{}

    %{
      calories: per_serving(amount(n, "Energy"), servings),
      protein_g: per_serving(amount(n, "Protein"), servings),
      fat_g: per_serving(amount(n, "Total Fat"), servings),
      carbs_g: per_serving(amount(n, "Carbohydrates"), servings),
      fiber_g: fiber_amount(n, servings)
    }
  end

  @doc """
  Priority-ranked insight candidates for a recipe. Always non-empty: the
  balanced-macros fallback is last so there is always something to render.
  """
  @spec candidates(struct()) :: [candidate()]
  def candidates(recipe) do
    macros = macros(recipe)

    (compound_candidates(recipe) ++
       health_candidates(recipe) ++
       macro_candidates(macros))
    |> case do
      [] -> [balanced_candidate(macros)]
      list -> list ++ [balanced_candidate(macros)]
    end
  end

  # ── compound candidates (ranked, polyphenol first) ─────────────────────────

  # Families ranked by social appeal: polyphenols lead, the rest follow the
  # registry's family vocabulary. The generic `"other"` bucket is excluded — a
  # "Rich in Other compounds" headline isn't compelling or specific.
  @family_rank ~w(polyphenol salicylate phytate oxalate lectin histamine fodmap purine)

  defp compound_candidates(recipe) do
    labels = Food.family_labels()

    recipe.id
    |> Food.compounds_for_recipe()
    |> Enum.reject(fn {type, _compounds} -> type == "other" end)
    |> Enum.sort_by(fn {type, _compounds} -> family_index(type) end)
    |> Enum.map(fn {type, compounds} ->
      label = Map.get(labels, type, "Compounds")

      %{
        type: "compound",
        headline_hint: "Rich in #{label}",
        detail: %{
          compound_type: type,
          family_label: label,
          compound_names: compounds |> Enum.map(& &1.name) |> Enum.take(5)
        }
      }
    end)
  end

  defp family_index(type) do
    case Enum.find_index(@family_rank, &(&1 == type)) do
      nil -> length(@family_rank)
      i -> i
    end
  end

  # ── health-flag candidates (anti-inflammatory etc.) ────────────────────────

  # `Health.flags_for_recipe/2` is condition-scoped; here we want the recipe's
  # intrinsic "good for" story regardless of any user opt-in, so we pass every
  # condition id. Only `"encourage"` recommendations read as a positive badge.
  defp health_candidates(recipe) do
    condition_ids = Health.list_conditions() |> Enum.map(& &1.id)

    recipe.id
    |> Health.flags_for_recipe(condition_ids)
    |> Enum.filter(&(&1.recommendation == "encourage"))
    |> Enum.uniq_by(& &1.condition.id)
    |> Enum.map(fn flag ->
      %{
        type: "health",
        headline_hint: flag.condition.name,
        detail: %{
          condition: flag.condition.name,
          severity: Map.get(flag, :severity)
        }
      }
    end)
  end

  # ── macro candidates (per-serving standouts) ───────────────────────────────

  defp macro_candidates(%{protein_g: p, calories: c, fiber_g: f}) do
    []
    |> maybe_macro(p >= @high_protein_g, "High Protein", %{protein_g: round_g(p)})
    |> maybe_macro(c > 0 and c <= @low_calorie_kcal, "Light & Low-Calorie", %{calories: round(c)})
    |> maybe_macro(is_number(f) and f >= @high_fiber_g, "High Fiber", %{fiber_g: round_g(f)})
  end

  defp maybe_macro(acc, false, _hint, _detail), do: acc

  defp maybe_macro(acc, true, hint, detail) do
    acc ++ [%{type: "macro", headline_hint: hint, detail: detail}]
  end

  defp balanced_candidate(macros) do
    %{type: "balanced", headline_hint: "Balanced Macros", detail: macros_detail(macros)}
  end

  defp macros_detail(%{protein_g: p, fat_g: ft, carbs_g: c}) do
    %{protein_g: round_g(p), fat_g: round_g(ft), carbs_g: round_g(c)}
  end

  # ── nutrients map helpers ──────────────────────────────────────────────────

  defp amount(nutrients, key) do
    case Map.get(nutrients, key) do
      %{"amount" => a} when is_number(a) -> a
      _ -> 0.0
    end
  end

  # Fiber lives nested under the "Carbohydrates" node's children ("Fiber,
  # total dietary"); fall back to nil when absent so it isn't treated as 0 fiber.
  defp fiber_amount(nutrients, servings) do
    with %{"children" => children} when is_list(children) <- Map.get(nutrients, "Carbohydrates"),
         %{"amount" => a} when is_number(a) <-
           Enum.find(children, &String.starts_with?(&1["name"] || "", "Fiber")) do
      per_serving(a, servings)
    else
      _ -> nil
    end
  end

  defp per_serving(amount, servings), do: amount / servings

  defp round_g(n) when is_number(n), do: Float.round(n / 1, 1)
  defp round_g(_), do: 0.0
end
