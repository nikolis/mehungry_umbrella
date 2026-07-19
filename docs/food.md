# Food context

`Mehungry.Food` is a permanent defdelegate facade; the implementation lives in
eight sub-modules under `apps/mehungry/lib/mehungry/food/`:

| Module | Owns |
|---|---|
| `Food.Recipes` | Recipe CRUD, `get_recipe!/1,2` (cached), list/count families, hashtag extraction from descriptions, nutrition enrichment on save (`put_nutrient_info/2`), Oban enqueues on create/update |
| `Food.Ingredients` | Ingredient CRUD and lookups (id/name/slug/translation), portions, ingredient nutrients, paginated listings, `delete_ingredients_without_nutrients/0` (large cascading cleanup) |
| `Food.IngredientQueries` | The `search_ingredient*` family (full-text, trigram, admin, translated variants), recipe search (`search_recipe/2` via `Search.RecipeSearch`), hashtag search, `pagenate_query/1` |
| `Food.Nutrients` | Nutrient records, key-nutrient listing, nutrient interactions, recalculation enqueues |
| `Food.Measurements` | Measurement units + translations, ingredient portions bridge, unit search |
| `Food.Categories` | Category CRUD/search, food restriction types (canonical `list_food_restriction_types/0`) |
| `Food.Localization` | Recipe translations (`AiBot.RecipeTranslation`), ingredient/category/unit translations, `localize_recipes/2` bulk localization, translation stats/upserts |
| `Food.Engagement` | Likes, recipe comments, annotations |

Standalone modules in `food/`: schemas, `Food.IngredientSearch` (ranked
prefix+fuzzy DB search), `Food.NutrientCalculation`, `Food.NutrientManager`,
`Food.NutrientHierarchyBuilder`, `Food.NutrientInteractions`,
`Food.NutrientMerger`, `Food.NutrientMapper` (display-name humanization,
moved from the web app), `Recipe.Query`, `RecipeUtils`.

## Recipes cache

`get_recipe!/1` reads/writes `:recipes_cache` under key `{Mehungry.Food, id}`.
The namespace is pinned (not `__MODULE__`) because
`RecipePutNutrientsWorker` invalidates entries under exactly that key.
`update_recipe/2` refreshes the entry; `delete_recipe/1` does not (LRU +
worker invalidation cover it).

## USDA clients — two, deliberately

- `Mehungry.FoodData.Usda.SearchClient` (`food_data/usda/search_client.ex`) — Req-based FoodData Central client used by the
  shopping-basket USDA item flow.
- `Mehungry.FoodData.Usda.FdcClient` (`food_data/usda/fdc_client.ex`) — HTTPoison-based client
  used by the AI recipe agent tool path.

They differ in HTTP stack, retry and parsing semantics; unifying them is a
behavior change and was deliberately deferred.

## Known quirks kept on purpose (behavior-preserving)

- `Food.NutrientNameNormilizer` — module name typo kept to avoid rename churn.
- Two divergent `normalize_nutrient_name/1` implementations
  (`Mehungry.NutrientUtils` fuzzy-fallback vs `Food.NutrientManager`
  capitalize-fallback) — cross-referenced in comments, not unified.
- `pagenate_query/1`, `find_ri_allias/2`, `get_user_category_rulles/1` —
  misspelled public names kept (call sites depend on them).
