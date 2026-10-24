defmodule MehungryWeb.Api.V1.BlueprintMatchJSON do
  @moduledoc """
  Serializes a `MealBlueprints.PlanCompatibility` entity report (the
  `%{matches: [entry], violations: [entry]}` returned by `match_recipes/2` /
  `match_ingredients/2`) into the `blueprint_match` block embedded on recipe and
  ingredient responses when the request carries `?blueprint_slug=`.

  The block tells the mobile client how a recipe/ingredient lines up with a
  blueprint's compound + nutrient targets:

      "blueprint_match": {
        "blueprint_id": 12, "blueprint_slug": "ibs-low-fodmap-ab12", "condition": "IBS",
        "match_count": 2, "violation_count": 1,
        "matches": [
          {"kind":"compound","name":"Polyphenols","direction":"required","via":"family"},
          {"kind":"nutrient","name":"Fiber","direction":"required","via":"direct","mode":"amount","target":25,"amount":30}
        ],
        "violations": [
          {"kind":"nutrient","name":"Sodium","direction":"avoid","via":"direct","mode":"per_100g","per_100g":480.0,"threshold":400.0}
        ]
      }

  Entry fields beyond `kind`/`name`/`direction`/`via` are present only when the
  underlying entry carries them (nutrient entries only): `mode` (`"pct"` caloric
  share · `"amount"` per-serving total · `"per_100g"` ingredient content), and the
  matching measured/`target`/`threshold` values.
  """

  @doc "The serialized `blueprint_match` block for one entity against `blueprint`."
  def block(blueprint, %{matches: matches, violations: violations}) do
    %{
      blueprint_id: blueprint.id,
      blueprint_slug: blueprint.slug,
      condition: condition_name(blueprint),
      match_count: length(matches),
      violation_count: length(violations),
      matches: Enum.map(matches, &entry/1),
      violations: Enum.map(violations, &entry/1)
    }
  end

  # ── parts ────────────────────────────────────────────────────────────────

  defp entry(e) do
    %{
      kind: to_string(e.kind),
      name: e.name,
      direction: to_string(e.direction),
      via: to_string(e.via)
    }
    |> put_optional(:mode, e[:mode] && to_string(e.mode))
    |> put_optional(:target, e[:target])
    |> put_optional(:pct, e[:pct])
    |> put_optional(:amount, e[:amount])
    |> put_optional(:per_100g, e[:per_100g])
    |> put_optional(:threshold, e[:threshold])
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp condition_name(%{condition: %{name: name}}), do: name
  defp condition_name(_), do: nil
end
