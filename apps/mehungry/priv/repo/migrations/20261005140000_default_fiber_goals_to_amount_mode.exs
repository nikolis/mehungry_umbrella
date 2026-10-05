defmodule Mehungry.Repo.Migrations.DefaultFiberGoalsToAmountMode do
  use Ecto.Migration

  import Ecto.Query

  # Fiber goals default to *amount* mode (≥25 g/day) now, because fiber's caloric
  # share is intrinsically tiny — even the ~25–38 g/day recommendation is only
  # ~2–3% of calories — so a %-of-calories chip reads as unresponsive. This
  # converts existing fiber goals still authored in pct mode over to amount mode
  # with the DRI default so they start tracking grams.
  #
  # Only pct-mode fiber goals are touched; a fiber goal the user already switched
  # to amount mode (with their own target) is left as-is.

  @fiber_amount 25

  def up do
    rows =
      from(b in "meal_blueprints",
        select: {
          b.id,
          b.required_nutrients,
          b.required_nutrient_pcts,
          b.required_nutrient_modes,
          b.avoid_nutrients,
          b.avoid_nutrient_pcts,
          b.avoid_nutrient_modes
        }
      )
      |> repo().all()

    Enum.each(rows, fn {id, req_names, req_pcts, req_modes, av_names, av_pcts, av_modes} ->
      {req_pcts2, req_modes2} = convert(req_names, req_pcts, req_modes)
      {av_pcts2, av_modes2} = convert(av_names, av_pcts, av_modes)

      changed? =
        req_pcts2 != norm(req_pcts) or req_modes2 != norm(req_modes) or
          av_pcts2 != norm(av_pcts) or av_modes2 != norm(av_modes)

      if changed? do
        from(b in "meal_blueprints", where: b.id == ^id)
        |> repo().update_all(
          set: [
            required_nutrient_pcts: req_pcts2,
            required_nutrient_modes: req_modes2,
            avoid_nutrient_pcts: av_pcts2,
            avoid_nutrient_modes: av_modes2
          ]
        )
      end
    end)
  end

  # Irreversible data correction; the prior pct state isn't worth restoring.
  def down, do: :ok

  defp norm(nil), do: %{}
  defp norm(map) when is_map(map), do: map

  defp convert(names, pcts, modes) do
    pcts = norm(pcts)
    modes = norm(modes)

    fiber_names =
      ((names || []) ++ Map.keys(pcts) ++ Map.keys(modes))
      |> Enum.uniq()
      |> Enum.filter(&fiber?/1)

    Enum.reduce(fiber_names, {pcts, modes}, fn name, {p, m} ->
      case Map.get(m, name, "pct") do
        "amount" -> {p, m}
        _ -> {Map.put(p, name, @fiber_amount), Map.put(m, name, "amount")}
      end
    end)
  end

  defp fiber?(name) do
    n = name |> to_string() |> String.downcase()
    String.contains?(n, "fiber") or String.contains?(n, "fibre")
  end
end
