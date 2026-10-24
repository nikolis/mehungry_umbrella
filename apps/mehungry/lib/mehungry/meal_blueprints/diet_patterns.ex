defmodule Mehungry.MealBlueprints.DietPatterns do
  @moduledoc """
  Ready-made "diet pattern" starter blueprints — named eating patterns (rather
  than the demographic `Presets`) a nutritionist or user can instantiate in one
  click: the Mediterranean and Low-FODMAP patterns plus the common named diets
  (Ketogenic, Paleo, Vegan, DASH, …). The full list is `@keys`/`all/0`.

  Each pattern is a **self-contained meal blueprint** — it carries its own
  required/avoid compound + nutrient tags and preferred/avoid food lists, so it
  needs no backing `Health.Condition`. `attrs_for/2` builds the
  `create_blueprint/1` attrs from a descriptor; `create_for_user/2` and
  `create_missing_for_user/1` instantiate them into a user's account.

  The nutritionist blueprint library and the user's blueprint page (the "Seed /
  add diet patterns" buttons) call **`sync_for_user/1`**, the re-seed path: it
  creates missing patterns *and* refreshes copies the user hasn't edited to the
  latest template, leaving edited copies alone. This works via two provenance
  columns stamped at seed time — `seeded_pattern_key` (the join back to the
  template) and `seed_signature` (a content hash; current content ≠ signature ⇒
  user-edited ⇒ skip). Legacy copies seeded before provenance existed are matched
  by name, adopted (key set, signature left nil), and never auto-overwritten.
  Everything is driven off `all/0`, so adding a new pattern here surfaces it in
  every button automatically.

  Patterns take one of two shapes, chosen so they stay meaningful against the data
  we actually have (macro splits + food lists always apply; nutrient tags resolve
  through the populated USDA nutrient tree; compound tags use known families only):

    * *Encourage* patterns (e.g. **Mediterranean**, **DASH**, **MIND**): encouraged
      nutrients/compounds + preferred foods, with a macro split tuned to the pattern.
    * *Avoidance* patterns (e.g. **Low-FODMAP**, **Vegan**, **Gluten-Free**): the
      defining lever is `avoid_foods` (onion, garlic, wheat…), enforced during
      generation by `Mehungry.AI.Agents.MealPlanAgent`.

  ## Usage

      Mehungry.MealBlueprints.DietPatterns.all()                  # descriptors (for a picker)
      {:ok, bp} = Mehungry.MealBlueprints.DietPatterns.create_for_user(user_id, :low_fodmap)
  """

  alias Mehungry.History.MealType
  alias Mehungry.MealBlueprints

  @keys [
    :mediterranean,
    :low_fodmap,
    :ketogenic,
    :low_carb,
    :high_protein,
    :low_fat,
    :zone,
    :atkins,
    :dash,
    :mind,
    :nordic,
    :whole_food_plant_based,
    :vegan,
    :vegetarian,
    :pescatarian,
    :paleo,
    :whole30,
    :gluten_free,
    :dairy_free,
    :low_sodium,
    :low_glycemic
  ]

  @doc "All diet-pattern descriptors (for rendering a picker)."
  def all, do: Enum.map(@keys, &build/1)

  @doc "The descriptor for a pattern key (`:mediterranean | :low_fodmap`)."
  def get(key) when key in @keys, do: build(key)

  @doc "The supported pattern keys."
  def keys, do: @keys

  # ── per-user instantiation ─────────────────────────────────────────────────

  @doc """
  Full `MealBlueprints.create_blueprint/1` attrs for `user_id` from a descriptor
  (or a pattern key). The blueprint is self-contained — it carries its own
  compound/nutrient tags and food lists and links to no condition.
  """
  def attrs_for(%{days: _} = preset, user_id) do
    preset
    |> Map.take([
      :name,
      :description,
      :required_nutrients,
      :avoid_nutrients,
      :required_compounds,
      :avoid_compounds,
      :preferred_foods,
      :avoid_foods,
      :days
    ])
    |> Map.put(:user_id, user_id)
  end

  def attrs_for(key, user_id) when key in @keys, do: attrs_for(get(key), user_id)

  @doc """
  Instantiates a diet pattern into `user_id`'s account, stamping it with seed
  provenance (`seeded_pattern_key` + `seed_signature`) so `sync_for_user/1` can
  later refresh it in place while leaving user edits alone.
  """
  def create_for_user(user_id, key) when key in @keys do
    user_id
    |> seeded_attrs_for(key)
    |> MealBlueprints.create_blueprint()
  end

  @doc """
  Instantiates every diet pattern the user doesn't already own (matched by name),
  so the button is safe to click repeatedly. Returns `{:ok, created_count}`.

  Prefer `sync_for_user/1`, which additionally refreshes unedited copies.
  """
  def create_missing_for_user(user_id) do
    existing = user_id |> MealBlueprints.list_blueprints_for_user() |> MapSet.new(& &1.name)

    created =
      for %{key: key, name: name} <- all(), not MapSet.member?(existing, name) do
        create_for_user(user_id, key)
      end

    {:ok, Enum.count(created, &match?({:ok, _}, &1))}
  end

  @doc """
  Re-seeds the diet patterns for `user_id`, the "click again" path:

    * **missing** patterns → created;
    * patterns already present and **unedited since seeding** → overwritten with
      the latest template (so changes to a pattern's definition propagate);
    * patterns the user has **edited** → left untouched;
    * **legacy** copies (instantiated before provenance existed, matched by name)
      → adopted (`seeded_pattern_key` set) but never auto-refreshed, since we
      can't prove they're unedited.

  "Unedited" means the blueprint's current content hashes to the
  `seed_signature` captured when it was last seeded. Returns
  `{:ok, %{created:, refreshed:, skipped:, adopted:}}`.
  """
  def sync_for_user(user_id) do
    existing = MealBlueprints.list_blueprints_for_sync(user_id)
    by_key = Map.new(seeded(existing), &{&1.seeded_pattern_key, &1})
    by_name = Map.new(existing, &{&1.name, &1})

    tally =
      Enum.reduce(all(), %{created: 0, refreshed: 0, skipped: 0, adopted: 0}, fn descriptor, acc ->
        key = Atom.to_string(descriptor.key)

        cond do
          tracked = Map.get(by_key, key) ->
            sync_tracked(tracked, descriptor, user_id, acc)

          legacy = unseeded_name_match(by_name, descriptor.name) ->
            {:ok, _} = MealBlueprints.set_blueprint_provenance(legacy, key, nil)
            bump(acc, :adopted)

          true ->
            {:ok, _} = create_for_user(user_id, descriptor.key)
            bump(acc, :created)
        end
      end)

    {:ok, tally}
  end

  @doc """
  A one-line human summary of a `sync_for_user/1` tally, for a flash message.
  """
  def sync_summary(%{created: created, refreshed: refreshed}) do
    parts =
      []
      |> maybe_part(created, "added #{created}")
      |> maybe_part(refreshed, "refreshed #{refreshed}")
      |> Enum.reverse()

    case parts do
      [] -> "Diet patterns are already up to date."
      _ -> "Diet patterns synced — " <> Enum.join(parts, ", ") <> "."
    end
  end

  defp maybe_part(parts, 0, _text), do: parts
  defp maybe_part(parts, _n, text), do: [text | parts]

  # Refresh a key-tracked copy. Overwrite only when (a) it still matches its seed
  # signature — i.e. the user hasn't edited it — AND (b) the template has actually
  # changed since it was seeded. A nil signature (adopted legacy) is never
  # refreshed; an edited or already-up-to-date copy is skipped.
  defp sync_tracked(blueprint, descriptor, user_id, acc) do
    attrs = attrs_for(descriptor.key, user_id)
    template_signature = content_signature_from_attrs(attrs)

    cond do
      is_nil(blueprint.seed_signature) ->
        bump(acc, :skipped)

      content_signature_from_blueprint(blueprint) != blueprint.seed_signature ->
        # User-edited since seeding — leave it alone.
        bump(acc, :skipped)

      template_signature == blueprint.seed_signature ->
        # Unedited and already on the latest template — nothing to do.
        bump(acc, :skipped)

      true ->
        stamped =
          Map.merge(attrs, %{
            seeded_pattern_key: Atom.to_string(descriptor.key),
            seed_signature: template_signature
          })

        {:ok, _} = MealBlueprints.update_blueprint(blueprint, stamped)
        bump(acc, :refreshed)
    end
  end

  defp seeded(blueprints), do: Enum.filter(blueprints, &(&1.seeded_pattern_key not in [nil, ""]))

  defp unseeded_name_match(by_name, name) do
    case Map.get(by_name, name) do
      %{seeded_pattern_key: k} = bp when k in [nil, ""] -> bp
      _ -> nil
    end
  end

  defp bump(acc, key), do: Map.update!(acc, key, &(&1 + 1))

  # Template attrs plus the provenance stamp (key + content signature of those
  # exact attrs), so a freshly-seeded blueprint reloads to the same signature.
  defp seeded_attrs_for(user_id, key) do
    attrs = attrs_for(key, user_id)

    Map.merge(attrs, %{
      seeded_pattern_key: Atom.to_string(key),
      seed_signature: content_signature_from_attrs(attrs)
    })
  end

  # ── descriptor construction ──────────────────────────────────────────────

  defp build(:mediterranean) do
    spec = %{
      name: "Mediterranean Diet",
      description:
        "A Mediterranean eating pattern: olive oil as the main fat, plenty of " <>
          "vegetables, legumes, whole grains and fish, moderate dairy, little red meat.",
      compounds: [
        {"Polyphenols", "polyphenol", "encourage", "moderate", harvard_med_ref()},
        {"Flavonoids", "polyphenol", "encourage", "moderate", harvard_med_ref()}
      ],
      nutrients: [
        {"Omega-3", "encourage", "strong", harvard_med_ref()},
        {"Fiber", "encourage", "moderate", harvard_med_ref()},
        {"Monounsaturated Fat", "encourage", "strong", harvard_med_ref()},
        {"Saturated Fat", "limit", "moderate", harvard_med_ref()},
        {"Added Sugar", "limit", "moderate", harvard_med_ref()},
        {"Sodium", "limit", "limited", harvard_med_ref()}
      ]
    }

    descriptor(:mediterranean, spec, %{
      preferred_foods: [
        "olive oil",
        "fish",
        "legumes",
        "whole grains",
        "vegetables",
        "fruit",
        "nuts",
        "Greek yogurt"
      ],
      avoid_foods: [],
      macro_split: %{protein_pct: 20, carbs_pct: 45, fats_pct: 35}
    })
  end

  defp build(:low_fodmap) do
    spec = %{
      name: "Low-FODMAP Diet",
      description:
        "A low-FODMAP eating pattern (commonly used for IBS): avoid high-FODMAP " <>
          "foods such as onion, garlic, wheat and certain fruits and legumes.",
      compounds: [
        {"FODMAP", "fodmap", "limit", "moderate", monash_ref()}
      ],
      nutrients: []
    }

    descriptor(:low_fodmap, spec, %{
      preferred_foods: [
        "rice",
        "oats",
        "firm tofu",
        "eggs",
        "carrots",
        "zucchini",
        "spinach",
        "strawberries",
        "blueberries",
        "lactose-free yogurt",
        "hard cheese"
      ],
      avoid_foods: [
        "onion",
        "garlic",
        "wheat",
        "rye",
        "apple",
        "pear",
        "watermelon",
        "honey",
        "cashews",
        "pistachios",
        "beans",
        "lentils",
        "chickpeas",
        "milk"
      ],
      macro_split: %{protein_pct: 25, carbs_pct: 45, fats_pct: 30}
    })
  end

  defp build(:ketogenic) do
    spec = %{
      name: "Ketogenic Diet",
      description:
        "A very-low-carb, high-fat eating pattern: cut grains, sugar and starchy " <>
          "vegetables right down and get most calories from fats and moderate protein.",
      compounds: [],
      nutrients: [
        {"Saturated Fat", "limit", "moderate", harvard_diet_ref("ketogenic-diet")},
        {"Added Sugars", "limit", "strong", harvard_diet_ref("ketogenic-diet")}
      ]
    }

    descriptor(:ketogenic, spec, %{
      preferred_foods: [
        "eggs",
        "avocado",
        "olive oil",
        "salmon",
        "cheese",
        "nuts",
        "leafy greens",
        "butter"
      ],
      avoid_foods: [
        "bread",
        "pasta",
        "rice",
        "potato",
        "sugar",
        "honey",
        "banana",
        "beans",
        "oats",
        "oatmeal",
        "cereal",
        "corn",
        "fruit juice",
        "chips"
      ],
      macro_split: %{protein_pct: 20, carbs_pct: 5, fats_pct: 75}
    })
  end

  defp build(:low_carb) do
    spec = %{
      name: "Low-Carb Diet",
      description:
        "A reduced-carbohydrate eating pattern: fewer refined carbs and sugary " <>
          "foods, more protein and healthy fats, without going fully ketogenic.",
      compounds: [],
      nutrients: [
        {"Added Sugars", "limit", "strong", harvard_diet_ref("low-carbohydrate-diets")}
      ]
    }

    descriptor(:low_carb, spec, %{
      preferred_foods: [
        "eggs",
        "chicken",
        "fish",
        "non-starchy vegetables",
        "nuts",
        "olive oil",
        "Greek yogurt"
      ],
      avoid_foods: [
        "bread",
        "pasta",
        "rice",
        "potato",
        "sugar",
        "sugary drinks",
        "fruit juice",
        "honey",
        "corn",
        "cereal",
        "candy",
        "pastries"
      ],
      macro_split: %{protein_pct: 30, carbs_pct: 20, fats_pct: 50}
    })
  end

  defp build(:high_protein) do
    spec = %{
      name: "High-Protein Diet",
      description:
        "A protein-forward eating pattern: a generous share of calories from lean " <>
          "protein at every meal to support satiety and muscle maintenance.",
      compounds: [],
      nutrients: [
        {"Protein", "encourage", "strong", harvard_protein_ref()}
      ]
    }

    descriptor(:high_protein, spec, %{
      preferred_foods: [
        "chicken breast",
        "eggs",
        "fish",
        "Greek yogurt",
        "cottage cheese",
        "legumes",
        "tofu",
        "lean beef"
      ],
      avoid_foods: [],
      macro_split: %{protein_pct: 40, carbs_pct: 35, fats_pct: 25}
    })
  end

  defp build(:low_fat) do
    spec = %{
      name: "Low-Fat Diet",
      description:
        "A reduced-fat eating pattern: lean proteins, whole grains and plenty of " <>
          "produce, keeping total and saturated fat low.",
      compounds: [],
      nutrients: [
        {"Total Fat", "limit", "moderate", harvard_fat_ref()},
        {"Saturated Fat", "limit", "strong", harvard_fat_ref()}
      ]
    }

    descriptor(:low_fat, spec, %{
      preferred_foods: [
        "skinless poultry",
        "white fish",
        "legumes",
        "whole grains",
        "vegetables",
        "fruit",
        "low-fat dairy"
      ],
      avoid_foods: [
        "fried foods",
        "butter",
        "fatty cuts of meat",
        "cream",
        "full-fat cheese"
      ],
      macro_split: %{protein_pct: 25, carbs_pct: 60, fats_pct: 15}
    })
  end

  defp build(:zone) do
    spec = %{
      name: "Zone Diet",
      description:
        "A balanced 40/30/30-style eating pattern: lean protein, controlled " <>
          "low-glycemic carbs and healthy fats in roughly even proportion at each meal.",
      compounds: [],
      nutrients: [
        {"Added Sugars", "limit", "moderate", zone_ref()}
      ]
    }

    descriptor(:zone, spec, %{
      preferred_foods: [
        "chicken",
        "fish",
        "eggs",
        "vegetables",
        "fruit",
        "olive oil",
        "nuts",
        "legumes"
      ],
      avoid_foods: [
        "white bread",
        "white rice",
        "sugar",
        "sugary drinks"
      ],
      macro_split: %{protein_pct: 30, carbs_pct: 40, fats_pct: 30}
    })
  end

  defp build(:atkins) do
    spec = %{
      name: "Atkins Diet",
      description:
        "A low-carbohydrate eating pattern that starts very low in carbs and " <>
          "reintroduces them gradually, with high protein and fat throughout.",
      compounds: [],
      nutrients: [
        {"Added Sugars", "limit", "strong", harvard_diet_ref("low-carbohydrate-diets")}
      ]
    }

    descriptor(:atkins, spec, %{
      preferred_foods: [
        "eggs",
        "meat",
        "fish",
        "cheese",
        "non-starchy vegetables",
        "nuts",
        "olive oil"
      ],
      avoid_foods: [
        "bread",
        "pasta",
        "rice",
        "potato",
        "sugar",
        "fruit juice"
      ],
      macro_split: %{protein_pct: 30, carbs_pct: 10, fats_pct: 60}
    })
  end

  defp build(:dash) do
    spec = %{
      name: "DASH Diet",
      description:
        "Dietary Approaches to Stop Hypertension: rich in vegetables, fruit, whole " <>
          "grains and low-fat dairy, deliberately low in sodium, saturated fat and added sugar.",
      compounds: [],
      nutrients: [
        {"Fiber", "encourage", "strong", dash_ref()},
        {"Sodium", "limit", "strong", dash_ref()},
        {"Saturated Fat", "limit", "moderate", dash_ref()},
        {"Added Sugars", "limit", "moderate", dash_ref()}
      ]
    }

    descriptor(:dash, spec, %{
      preferred_foods: [
        "vegetables",
        "fruit",
        "whole grains",
        "low-fat dairy",
        "legumes",
        "nuts",
        "fish",
        "skinless poultry"
      ],
      avoid_foods: [
        "cured meats",
        "canned soup",
        "salty snacks",
        "sugary drinks",
        "fatty red meat"
      ],
      macro_split: %{protein_pct: 18, carbs_pct: 55, fats_pct: 27}
    })
  end

  defp build(:mind) do
    spec = %{
      name: "MIND Diet",
      description:
        "A brain-health eating pattern blending Mediterranean and DASH: leafy greens, " <>
          "berries, nuts, whole grains, olive oil and fish, limiting butter and sweets.",
      compounds: [
        {"Polyphenols", "polyphenol", "encourage", "moderate", mind_ref()}
      ],
      nutrients: [
        {"Omega-3", "encourage", "moderate", mind_ref()},
        {"Fiber", "encourage", "moderate", mind_ref()},
        {"Saturated Fat", "limit", "moderate", mind_ref()}
      ]
    }

    descriptor(:mind, spec, %{
      preferred_foods: [
        "leafy greens",
        "berries",
        "nuts",
        "whole grains",
        "olive oil",
        "fish",
        "poultry",
        "legumes"
      ],
      avoid_foods: [
        "butter",
        "fried foods",
        "pastries",
        "sweets",
        "fatty red meat"
      ],
      macro_split: %{protein_pct: 20, carbs_pct: 50, fats_pct: 30}
    })
  end

  defp build(:nordic) do
    spec = %{
      name: "Nordic Diet",
      description:
        "The New Nordic eating pattern: rye and oats, berries, root vegetables, " <>
          "fatty fish and rapeseed (canola) oil, low in added sugar.",
      compounds: [
        {"Polyphenols", "polyphenol", "encourage", "moderate", nordic_ref()}
      ],
      nutrients: [
        {"Omega-3", "encourage", "moderate", nordic_ref()},
        {"Fiber", "encourage", "moderate", nordic_ref()},
        {"Added Sugars", "limit", "moderate", nordic_ref()}
      ]
    }

    descriptor(:nordic, spec, %{
      preferred_foods: [
        "rye bread",
        "oats",
        "berries",
        "root vegetables",
        "cabbage",
        "fatty fish",
        "rapeseed oil",
        "legumes"
      ],
      avoid_foods: [
        "sugary drinks",
        "sweets",
        "processed meat"
      ],
      macro_split: %{protein_pct: 18, carbs_pct: 52, fats_pct: 30}
    })
  end

  defp build(:whole_food_plant_based) do
    spec = %{
      name: "Whole-Food Plant-Based Diet",
      description:
        "Minimally processed plant foods only: vegetables, fruit, whole grains, " <>
          "legumes, nuts and seeds, with no animal products and little to no added oil.",
      compounds: [],
      nutrients: [
        {"Fiber", "encourage", "strong", harvard_diet_ref("vegetarian-diet")}
      ]
    }

    descriptor(:whole_food_plant_based, spec, %{
      preferred_foods: [
        "vegetables",
        "fruit",
        "whole grains",
        "legumes",
        "nuts",
        "seeds",
        "tofu"
      ],
      avoid_foods: [
        "meat",
        "poultry",
        "fish",
        "dairy",
        "eggs",
        "oil",
        "refined sugar"
      ],
      macro_split: %{protein_pct: 15, carbs_pct: 60, fats_pct: 25}
    })
  end

  defp build(:vegan) do
    spec = %{
      name: "Vegan Diet",
      description:
        "An entirely plant-based eating pattern: no meat, fish, dairy, eggs or honey " <>
          "— protein from legumes, soy, nuts, seeds and whole grains.",
      compounds: [],
      nutrients: [
        {"Fiber", "encourage", "moderate", harvard_diet_ref("vegetarian-diet")}
      ]
    }

    descriptor(:vegan, spec, %{
      preferred_foods: [
        "legumes",
        "tofu",
        "tempeh",
        "whole grains",
        "vegetables",
        "fruit",
        "nuts",
        "seeds"
      ],
      avoid_foods: [
        "meat",
        "poultry",
        "fish",
        "dairy",
        "eggs",
        "honey"
      ],
      macro_split: %{protein_pct: 18, carbs_pct: 55, fats_pct: 27}
    })
  end

  defp build(:vegetarian) do
    spec = %{
      name: "Vegetarian Diet",
      description:
        "A meat-free eating pattern that still includes dairy and eggs, with protein " <>
          "from legumes, dairy, eggs, soy, nuts and whole grains.",
      compounds: [],
      nutrients: [
        {"Fiber", "encourage", "moderate", harvard_diet_ref("vegetarian-diet")}
      ]
    }

    descriptor(:vegetarian, spec, %{
      preferred_foods: [
        "legumes",
        "eggs",
        "dairy",
        "tofu",
        "whole grains",
        "vegetables",
        "fruit",
        "nuts"
      ],
      avoid_foods: [
        "meat",
        "poultry",
        "fish"
      ],
      macro_split: %{protein_pct: 18, carbs_pct: 55, fats_pct: 27}
    })
  end

  defp build(:pescatarian) do
    spec = %{
      name: "Pescatarian Diet",
      description:
        "A vegetarian pattern that also includes fish and seafood, so protein comes " <>
          "from fish, legumes, dairy, eggs and soy rather than meat or poultry.",
      compounds: [],
      nutrients: [
        {"Omega-3", "encourage", "moderate", harvard_diet_ref("pescatarian-flexitarian-diet")}
      ]
    }

    descriptor(:pescatarian, spec, %{
      preferred_foods: [
        "fish",
        "seafood",
        "legumes",
        "eggs",
        "dairy",
        "whole grains",
        "vegetables",
        "nuts"
      ],
      # Pescatarian is the one "no-meat" pattern that does NOT get the
      # vegan/vegetarian category filter (see MealPlanAgent.diet_mode_from_blueprint/1),
      # so the literal substring avoid-list is the *only* flesh gate — it must name
      # the specific meats, not just the category words "meat"/"poultry".
      avoid_foods: [
        "meat",
        "poultry",
        "beef",
        "pork",
        "lamb",
        "chicken",
        "turkey",
        "bacon",
        "sausage"
      ],
      macro_split: %{protein_pct: 22, carbs_pct: 50, fats_pct: 28}
    })
  end

  defp build(:paleo) do
    spec = %{
      name: "Paleo Diet",
      description:
        "A \"paleolithic\" eating pattern: meat, fish, eggs, vegetables, fruit, nuts " <>
          "and seeds, excluding grains, legumes, dairy and refined sugar.",
      compounds: [],
      nutrients: [
        {"Added Sugars", "limit", "moderate", harvard_diet_ref("paleo-diet")}
      ]
    }

    descriptor(:paleo, spec, %{
      preferred_foods: [
        "meat",
        "fish",
        "eggs",
        "vegetables",
        "fruit",
        "nuts",
        "seeds"
      ],
      # Paleo gets no category diet filter, so the grain/legume *category* words
      # alone ("grains", "legumes") leak specific foods — name the common ones so
      # the literal substring gate actually catches rice/oats/beans/soy. (Bare
      # "beans" also excludes green beans, a conservative over-exclusion.)
      avoid_foods: [
        "grains",
        "rice",
        "oats",
        "oatmeal",
        "quinoa",
        "corn",
        "bread",
        "pasta",
        "cereal",
        "legumes",
        "beans",
        "lentils",
        "chickpeas",
        "peanut",
        "soy",
        "tofu",
        "dairy",
        "refined sugar",
        "processed foods"
      ],
      macro_split: %{protein_pct: 30, carbs_pct: 35, fats_pct: 35}
    })
  end

  defp build(:whole30) do
    spec = %{
      name: "Whole30 Diet",
      description:
        "A 30-day elimination pattern: whole foods only — meat, seafood, eggs, " <>
          "vegetables and fruit — with no grains, legumes, dairy, added sugar or alcohol.",
      compounds: [],
      nutrients: [
        {"Added Sugars", "limit", "strong", whole30_ref()}
      ]
    }

    descriptor(:whole30, spec, %{
      preferred_foods: [
        "meat",
        "seafood",
        "eggs",
        "vegetables",
        "fruit",
        "nuts",
        "olive oil"
      ],
      # Same category-word leak as paleo (no diet filter for Whole30): name the
      # specific grains/legumes, plus Whole30's total added-sugar ban (honey,
      # maple) which the bare "sugar" substring doesn't cover.
      avoid_foods: [
        "grains",
        "rice",
        "oats",
        "oatmeal",
        "quinoa",
        "corn",
        "bread",
        "pasta",
        "cereal",
        "legumes",
        "beans",
        "lentils",
        "chickpeas",
        "peanut",
        "soy",
        "tofu",
        "dairy",
        "sugar",
        "honey",
        "maple syrup",
        "alcohol",
        "processed foods"
      ],
      macro_split: %{protein_pct: 30, carbs_pct: 35, fats_pct: 35}
    })
  end

  defp build(:gluten_free) do
    spec = %{
      name: "Gluten-Free Diet",
      description:
        "Excludes gluten-containing grains (wheat, barley, rye) — essential for " <>
          "celiac disease — with carbs from rice, corn, potato, quinoa and oats.",
      compounds: [],
      nutrients: []
    }

    descriptor(:gluten_free, spec, %{
      preferred_foods: [
        "rice",
        "quinoa",
        "corn",
        "potato",
        "gluten-free oats",
        "vegetables",
        "fruit",
        "eggs",
        "fish"
      ],
      avoid_foods: [
        "wheat",
        "barley",
        "rye",
        "spelt",
        "farro",
        "bulgur",
        "semolina",
        "seitan",
        "bread",
        "pasta",
        "couscous",
        "beer"
      ],
      macro_split: %{protein_pct: 20, carbs_pct: 50, fats_pct: 30}
    })
  end

  defp build(:dairy_free) do
    spec = %{
      name: "Dairy-Free Diet",
      description:
        "Excludes all dairy (milk, cheese, yogurt, butter, cream) — for lactose " <>
          "intolerance or milk allergy — using plant milks and other calcium sources.",
      compounds: [],
      nutrients: []
    }

    descriptor(:dairy_free, spec, %{
      preferred_foods: [
        "plant milk",
        "leafy greens",
        "tofu",
        "legumes",
        "nuts",
        "seeds",
        "fish",
        "fruit"
      ],
      avoid_foods: [
        "milk",
        "cheese",
        "yogurt",
        "butter",
        "cream",
        "ice cream"
      ],
      macro_split: %{protein_pct: 20, carbs_pct: 50, fats_pct: 30}
    })
  end

  defp build(:low_sodium) do
    spec = %{
      name: "Low-Sodium Diet",
      description:
        "A reduced-salt eating pattern for blood-pressure and heart health: fresh, " <>
          "minimally processed foods, avoiding cured, canned and packaged salty items.",
      compounds: [],
      nutrients: [
        {"Sodium", "limit", "strong", aha_sodium_ref()}
      ]
    }

    descriptor(:low_sodium, spec, %{
      preferred_foods: [
        "fresh vegetables",
        "fruit",
        "unsalted nuts",
        "whole grains",
        "fresh fish",
        "skinless poultry",
        "legumes"
      ],
      avoid_foods: [
        "cured meats",
        "canned soup",
        "salty snacks",
        "soy sauce",
        "processed cheese",
        "pickles"
      ],
      macro_split: %{protein_pct: 20, carbs_pct: 52, fats_pct: 28}
    })
  end

  defp build(:low_glycemic) do
    spec = %{
      name: "Low-Glycemic Diet",
      description:
        "A blood-sugar-friendly eating pattern (useful for diabetes and insulin " <>
          "resistance): low-glycemic whole foods, limiting sugar and refined carbs.",
      compounds: [],
      nutrients: [
        {"Fiber", "encourage", "moderate", ada_ref()},
        {"Added Sugars", "limit", "strong", ada_ref()}
      ]
    }

    descriptor(:low_glycemic, spec, %{
      preferred_foods: [
        "legumes",
        "whole grains",
        "non-starchy vegetables",
        "berries",
        "nuts",
        "Greek yogurt",
        "fish",
        "eggs"
      ],
      avoid_foods: [
        "sugar",
        "white bread",
        "white rice",
        "sugary drinks",
        "sweets",
        "fruit juice"
      ],
      macro_split: %{protein_pct: 25, carbs_pct: 45, fats_pct: 30}
    })
  end

  # Assembles a descriptor; the blueprint's compound/nutrient tag arrays are
  # *derived* from the pattern spec so direction stays consistent.
  defp descriptor(key, spec, %{
         preferred_foods: preferred_foods,
         avoid_foods: avoid_foods,
         macro_split: macro_split
       }) do
    %{
      key: key,
      name: spec.name,
      description: spec.description,
      required_compounds: compound_names(spec, ["encourage"]),
      avoid_compounds: compound_names(spec, ["avoid", "limit", "caution"]),
      required_nutrients: nutrient_names(spec, ["encourage"]),
      avoid_nutrients: nutrient_names(spec, ["avoid", "limit", "caution"]),
      preferred_foods: preferred_foods,
      avoid_foods: avoid_foods,
      days: days(macro_split)
    }
  end

  defp compound_names(%{compounds: compounds}, directions) do
    for {name, _type, rec, _ev, _ref} <- compounds, rec in directions, do: name
  end

  defp nutrient_names(%{nutrients: nutrients}, directions) do
    for {name, rec, _ev, _ref} <- nutrients, rec in directions, do: name
  end

  # 7 identical days; each carries the 5 meal slots with the same macro split
  # (a ratio, not an amount). Diet patterns set no per-day calorie aim.
  defp days(macro_split) do
    meals = Enum.map(MealType.values(), &Map.put(macro_split, :meal_type, &1))

    for day_index <- 1..7 do
      %{day_index: day_index, meals: meals}
    end
  end

  # ── content signature (edit detection for sync_for_user/1) ─────────────────

  @doc """
  Content hash of a template's `attrs_for/2` output, with the schema defaults a
  created blueprint carries applied (visibility "private", empty pct/mode maps,
  nil notes/calorie targets) so an unedited seeded copy hashes identically via
  `content_signature_from_blueprint/1`.
  """
  def content_signature_from_attrs(attrs) do
    signature(%{
      name: Map.get(attrs, :name),
      description: Map.get(attrs, :description),
      visibility: Map.get(attrs, :visibility, "private"),
      required_nutrients: Map.get(attrs, :required_nutrients, []),
      avoid_nutrients: Map.get(attrs, :avoid_nutrients, []),
      required_compounds: Map.get(attrs, :required_compounds, []),
      avoid_compounds: Map.get(attrs, :avoid_compounds, []),
      preferred_foods: Map.get(attrs, :preferred_foods, []),
      avoid_foods: Map.get(attrs, :avoid_foods, []),
      required_nutrient_pcts: Map.get(attrs, :required_nutrient_pcts, %{}),
      avoid_nutrient_pcts: Map.get(attrs, :avoid_nutrient_pcts, %{}),
      required_nutrient_modes: Map.get(attrs, :required_nutrient_modes, %{}),
      avoid_nutrient_modes: Map.get(attrs, :avoid_nutrient_modes, %{}),
      days: Map.get(attrs, :days, [])
    })
  end

  @doc """
  Content hash of a loaded blueprint (its `days: :meals` tree must be preloaded).
  Equal to the stored `seed_signature` exactly when the user hasn't edited the
  copy since it was seeded.
  """
  def content_signature_from_blueprint(blueprint) do
    signature(%{
      name: blueprint.name,
      description: blueprint.description,
      visibility: blueprint.visibility || "private",
      required_nutrients: blueprint.required_nutrients || [],
      avoid_nutrients: blueprint.avoid_nutrients || [],
      required_compounds: blueprint.required_compounds || [],
      avoid_compounds: blueprint.avoid_compounds || [],
      preferred_foods: blueprint.preferred_foods || [],
      avoid_foods: blueprint.avoid_foods || [],
      required_nutrient_pcts: blueprint.required_nutrient_pcts || %{},
      avoid_nutrient_pcts: blueprint.avoid_nutrient_pcts || %{},
      required_nutrient_modes: blueprint.required_nutrient_modes || %{},
      avoid_nutrient_modes: blueprint.avoid_nutrient_modes || %{},
      days: blueprint.days || []
    })
  end

  defp signature(content) do
    canonical = [
      content.name,
      content.description,
      content.visibility,
      Enum.sort(content.required_nutrients),
      Enum.sort(content.avoid_nutrients),
      Enum.sort(content.required_compounds),
      Enum.sort(content.avoid_compounds),
      Enum.sort(content.preferred_foods),
      Enum.sort(content.avoid_foods),
      canon_map(content.required_nutrient_pcts),
      canon_map(content.avoid_nutrient_pcts),
      canon_map(content.required_nutrient_modes),
      canon_map(content.avoid_nutrient_modes),
      canon_days(content.days)
    ]

    :crypto.hash(:sha256, :erlang.term_to_binary(canonical)) |> Base.encode16(case: :lower)
  end

  defp canon_map(m) when is_map(m), do: m |> Map.to_list() |> Enum.sort()
  defp canon_map(_), do: []

  defp canon_days(days) when is_list(days) do
    days
    |> Enum.map(fn d ->
      {field(d, :day_index), field(d, :total_calorie_target), canon_meals(field(d, :meals))}
    end)
    |> Enum.sort()
  end

  defp canon_days(_), do: []

  defp canon_meals(meals) when is_list(meals) do
    meals
    |> Enum.map(fn m ->
      {field(m, :meal_type), field(m, :protein_pct), field(m, :carbs_pct), field(m, :fats_pct),
       field(m, :note)}
    end)
    |> Enum.sort()
  end

  defp canon_meals(_), do: []

  # Reads a field from either a template map (atom keys, some absent) or a loaded
  # Ecto struct; absent keys default to nil so both representations align.
  defp field(x, key), do: Map.get(x, key)

  defp harvard_med_ref do
    %{
      "label" => "Harvard T.H. Chan — The Mediterranean Diet",
      "url" =>
        "https://nutritionsource.hsph.harvard.edu/healthy-weight/diet-reviews/mediterranean-diet/"
    }
  end

  defp monash_ref do
    %{"label" => "Monash University — Low FODMAP diet", "url" => "https://www.monashfodmap.com/"}
  end

  # Harvard T.H. Chan "Diet Review" pages share a stable slug-based URL.
  defp harvard_diet_ref(slug) do
    %{
      "label" => "Harvard T.H. Chan — Diet Review",
      "url" => "https://nutritionsource.hsph.harvard.edu/healthy-weight/diet-reviews/#{slug}/"
    }
  end

  defp harvard_protein_ref do
    %{
      "label" => "Harvard T.H. Chan — Protein",
      "url" => "https://nutritionsource.hsph.harvard.edu/what-should-you-eat/protein/"
    }
  end

  defp harvard_fat_ref do
    %{
      "label" => "Harvard T.H. Chan — Types of Fat",
      "url" => "https://nutritionsource.hsph.harvard.edu/what-should-you-eat/fats-and-cholesterol/types-of-fat/"
    }
  end

  defp zone_ref do
    %{
      "label" => "Harvard T.H. Chan — Diet Review: Zone Diet",
      "url" => "https://nutritionsource.hsph.harvard.edu/healthy-weight/diet-reviews/zone-diet/"
    }
  end

  defp dash_ref do
    %{
      "label" => "NHLBI — DASH Eating Plan",
      "url" => "https://www.nhlbi.nih.gov/education/dash-eating-plan"
    }
  end

  defp mind_ref do
    %{
      "label" => "Harvard T.H. Chan — Diet Review: MIND Diet",
      "url" => "https://nutritionsource.hsph.harvard.edu/healthy-weight/diet-reviews/mind-diet/"
    }
  end

  defp nordic_ref do
    %{
      "label" => "Harvard T.H. Chan — Diet Review: Nordic Diet",
      "url" => "https://nutritionsource.hsph.harvard.edu/healthy-weight/diet-reviews/nordic-diet/"
    }
  end

  defp whole30_ref do
    %{"label" => "Whole30 Program", "url" => "https://whole30.com/whole30-program-rules/"}
  end

  defp aha_sodium_ref do
    %{
      "label" => "American Heart Association — How much sodium",
      "url" =>
        "https://www.heart.org/en/healthy-living/healthy-eating/eat-smart/sodium/how-much-sodium-should-i-eat-per-day"
    }
  end

  defp ada_ref do
    %{
      "label" => "American Diabetes Association — Eating Well",
      "url" => "https://diabetes.org/food-nutrition"
    }
  end
end
