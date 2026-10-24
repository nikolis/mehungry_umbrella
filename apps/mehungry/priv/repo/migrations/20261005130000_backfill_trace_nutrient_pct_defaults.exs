defmodule Mehungry.Repo.Migrations.BackfillTraceNutrientPctDefaults do
  use Ecto.Migration

  import Ecto.Query

  # Before this release every nutrient goal was auto-seeded with a flat 10%-of-
  # calories threshold (`Blueprint.default_nutrient_pct/0`). That floor is
  # physiologically unreachable for energy-dense trace fats (Omega-3/6/9, PUFA,
  # MUFA) and for fiber, so those goals could never read as met. We now default
  # them per nutrient (`Blueprint.default_nutrient_pct/1`); this backfills the
  # stale stored `10` so existing blueprints are fixed without the user having to
  # re-add the goal.
  #
  # Scope is deliberately narrow: only a stored value of exactly 10 — the single
  # value the old seeding could produce — on a trace-category nutrient is
  # rewritten. A deliberate 10 on a macro (protein/carbs/fat) is untouched, and
  # any value the user typed themselves (anything other than 10) is preserved.

  def up do
    rows =
      from(b in "meal_blueprints",
        select: {b.id, b.required_nutrient_pcts, b.avoid_nutrient_pcts}
      )
      |> repo().all()

    Enum.each(rows, fn {id, required, avoid} ->
      new_required = remap(required)
      new_avoid = remap(avoid)

      if new_required != (required || %{}) or new_avoid != (avoid || %{}) do
        from(b in "meal_blueprints", where: b.id == ^id)
        |> repo().update_all(
          set: [required_nutrient_pcts: new_required, avoid_nutrient_pcts: new_avoid]
        )
      end
    end)
  end

  # Irreversible data correction — the prior flat-10 state is not worth restoring.
  def down, do: :ok

  defp remap(nil), do: %{}

  defp remap(map) when is_map(map) do
    Map.new(map, fn {name, value} ->
      case {old_default?(value), trace_default(name)} do
        {true, pct} when is_number(pct) -> {name, pct}
        _ -> {name, value}
      end
    end)
  end

  defp old_default?(10), do: true
  defp old_default?(10.0), do: true
  defp old_default?(_), do: false

  # Mirrors `Mehungry.MealBlueprints.Blueprint.default_nutrient_pct/1`, inlined so
  # the migration stays stable if that function later changes. Returns nil for a
  # nutrient the flat 10% still suits (the macros), leaving it untouched.
  defp trace_default(name) do
    n = name |> to_string() |> String.downcase()

    cond do
      String.contains?(n, "omega-3") -> 0.5
      String.contains?(n, "omega-6") -> 2
      String.contains?(n, "omega-9") -> 1
      String.contains?(n, "omega") -> 1
      String.contains?(n, "pufa") -> 5
      String.contains?(n, "mufa") -> 5
      String.contains?(n, "fiber") or String.contains?(n, "fibre") -> 2
      true -> nil
    end
  end
end
