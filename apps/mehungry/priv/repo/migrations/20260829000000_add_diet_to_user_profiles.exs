defmodule Mehungry.Repo.Migrations.AddDietToUserProfiles do
  use Ecto.Migration

  import Ecto.Query

  # Animal-product category keywords excluded by each base diet — a self-contained
  # copy of Mehungry.Food.Categories's vocabulary so the backfill doesn't depend on
  # app code that may change after this migration ships.
  @diet_keywords %{
    "vegan" => ~w(fish Poultry Dairy Pork Sausages Lamb Beef),
    "vegetarian" => ~w(fish Poultry Pork Sausages Lamb Beef)
  }

  def up do
    alter table(:user_profiles) do
      add :diet, :string, default: "omnivore"
      add :lactose_intolerant, :boolean, default: false
    end

    flush()

    backfill_diet()
  end

  def down do
    alter table(:user_profiles) do
      remove :diet
      remove :lactose_intolerant
    end
  end

  # Existing users expressed their diet only through excluded category rules. Seed
  # the new `diet` column from those rules so vegan/vegetarian users keep their
  # feed filter after diet_mode switches to reading the column.
  defp backfill_diet do
    repo = repo()

    category_names =
      from(c in "categories", select: {c.id, c.name})
      |> repo.all()
      |> Map.new()

    profiles = from(p in "user_profiles", select: p.id) |> repo.all()

    Enum.each(profiles, fn profile_id ->
      excluded_names =
        from(r in "user_category_rules",
          join: p in "user_profiles",
          on: p.user_id == r.user_id,
          where: p.id == ^profile_id,
          select: r.category_id
        )
        |> repo.all()
        |> Enum.map(&Map.get(category_names, &1))
        |> Enum.reject(&is_nil/1)

      diet = detect_diet(excluded_names)
      lactose = excludes_keyword?(excluded_names, "Dairy")

      from(p in "user_profiles", where: p.id == ^profile_id)
      |> repo.update_all(set: [diet: diet, lactose_intolerant: lactose])
    end)
  end

  defp detect_diet(excluded_names) do
    cond do
      covers?(excluded_names, @diet_keywords["vegan"]) -> "vegan"
      covers?(excluded_names, @diet_keywords["vegetarian"]) -> "vegetarian"
      true -> "omnivore"
    end
  end

  # A diet is inferred when every one of its keywords is matched by at least one
  # excluded category (substring, case-insensitive) — mirrors the grouped
  # detection in Mehungry.Food.Categories.
  defp covers?(excluded_names, keywords) do
    Enum.all?(keywords, &excludes_keyword?(excluded_names, &1))
  end

  defp excludes_keyword?(excluded_names, keyword) do
    down_kw = String.downcase(keyword)
    Enum.any?(excluded_names, fn name -> String.contains?(String.downcase(name), down_kw) end)
  end
end
