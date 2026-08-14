# Ingredient Search

Two search engines — split by role, not duplicated — plus a shared scope module,
under `apps/mehungry/lib/mehungry/food/`:

| Module | File | Role |
|---|---|---|
| `Food.IngredientSearch` | `food/ingredient_search.ex` | Ranked **prefix + fuzzy** search over the local USDA DB. The **single path for all user-facing name search**. |
| `Food.IngredientQueries` | `food/ingredient_queries.ex` | The `search_ingredient*` family (FTS / trigram / **admin** / translated variants) plus recipe & hashtag search. |
| `Food.IngredientScope` | `food/ingredient_scope.ex` | **Shared query scopes** both paths compose — owner/friends visibility (`filter_by_owner/2`, `visible_owner_ids/1`), USDA food-class filtering (`maybe_filter_by_classes/2`), and second-layer category hiding (`second_layer_category_ids/0`, `exclude_secondary_categories/3`). |

Both are reachable through the permanent `Mehungry.Food` defdelegate facade. Entity
schemas (`Ingredient`, `IngredientTranslation`, `search_name`, …) are the canonical
[Ingredient card](../entities/ingredient.md); this doc covers **search behavior**, not
fields.

---

## `Food.IngredientSearch` — ranked prefix + fuzzy

The preferred, ranked search. Its public entry is `search/3`:

```elixir
search(search_term, classes \\ [], owner_id \\ nil)
```

### Strategy

1. **Normalize** the term via `Ingredient.normalize_string/1` (lowercase,
   punctuation-stripped) into the form stored on each row's `search_name`
   (e.g. `"Salt, table"` → `"salt table"`). Empty normalized term → `[]`.
2. **Primary — prefix query** (`run_prefix_query/4`) on `search_name`:
   - single-word → plain `search_name ILIKE 'word%'`;
   - multi-word → phrase-prefix **OR** all-words-any-order (so both
     `"Olive oil, salad or cooking"` and `"Oil, olive"` match `"olive oil"`).
3. **Fuzzy fallback** (`run_fuzzy_query/5`) fires only when the prefix query
   returns fewer than `@prefix_sufficient` (**10**) rows: pg_trgm
   `word_similarity(term, name) > @fuzzy_threshold` (**0.3**) on the GIN-trigram
   `name` column, excluding ids already returned, up to `@max_results` (**20**)
   total. This handles typos (`"olivve"` → `"Olive oil"`).

### Ranking (both queries)

1. Exact normalized match on `search_name`.
2. pg_trgm `word_similarity` (perfect match on `"salt"` in `"Salt, table"` = 1.0).
3. Shorter `search_name` first (less-qualified = more canonical).
4. USDA food-class preference: Foundation > SR Legacy > Survey (FNDDS) >
   Experimental > other.
5. Alphabetical tiebreak.

### Visibility & filtering

- `IngredientScope.filter_by_owner/2` — global rows (`user_id IS NULL`) always;
  plus the viewer's own private rows **and their friends'**
  (`visible_owner_ids/1` = `[owner_id | Mehungry.Friends.friend_ids(owner_id)]`)
  when an id is passed. `owner_id = nil` → global only, so private ingredients
  never leak.
- `IngredientScope.maybe_filter_by_classes/2` — restrict to given USDA food classes.
- Excludes USDA **Branded** rows (`food_class IS DISTINCT FROM 'Branded'`, which
  also lets the planner use the partial `ingredients_*_active_idx` indexes).
- `IngredientScope.exclude_secondary_categories/3` — hides the composite/prepared
  "second layer" USDA categories (resolved once per call via
  `second_layer_category_ids/0` and threaded to both the prefix and fuzzy queries),
  but never the viewer's own private ingredients.

### Other public functions

- `search_for_select/3` — same ranking, returns lightweight `%{id, name}` maps for
  select components.
- `search_in_language/3` — accent-insensitive search over `IngredientTranslation`
  for a language code, returning `%{id, name}` maps (drop-in for select dropdowns).
  Same visibility, Branded, and second-layer rules (the last inlined on the `[t, i]`
  binding since the ingredient isn't the first binding there).

---

## `Food.IngredientQueries` — the `search_ingredient*` family

The older/broader module. It also hosts recipe search, hashtag lookups, admin
query builders, pagination and count helpers. The ingredient-search functions:

| Function | Backing | Notes |
|---|---|---|
| `search_ingredient_search/3` | Postgres FTS (`searchable @@ websearch_to_tsquery`, ranked by `ts_rank_cd`) | The shared builder. Applies `IngredientScope.exclude_secondary_categories/3` (hides prepared "second-layer" USDA categories, but never the viewer's own), `filter_by_owner/2`, `maybe_filter_by_classes/2`. Limit 20. |
| `search_ingredient_alt_admin/3` | `search_ingredient_search` + `maybe_filter_by_data_types` | Admin. Returns `{query, pagenated, count}`; no Branded exclusion (admins can filter to Branded). |
| `search_ingredient_admin/3` | `search_ingredient_query` (trigram/ILIKE) + data-type filter | Admin `{query, pagenated, count}`. |
| `search_ingredient_admin_translated/4` | `IngredientTranslation` accent-insensitive ILIKE, ranked (exact-then-length) | Admin translated search; returns `{nil, {ingredients, nil}, total_count}`. |
| `search_ingredient/2` | `search_ingredient_query` + preload `[:category, :measurement_unit]` | Used by **tests** only. |
| `search_ingredient_query/2` | pg_trgm `%` operator OR ILIKE, `maybe_filter_by_classes`, limit 20 | Shared builder for the two above. |

Non-ingredient search in the same module: `search_recipe/2` (→
`Search.RecipeSearch`), `search_recipes_by_ingredient/1` (delegates ingredient
resolution to **`IngredientSearch.search`**), `search_hashtag/1`,
`search_hashtag1/1`, plus helpers `pagenate_query/1` (misspelling intentional),
`count_search_results/1`, `maybe_filter_by_classes/2`, `maybe_filter_by_data_types/2`,
`list_distinct_food_classes/0`, `list_distinct_data_types/0`.

---

## `IngredientSearch.search` vs `search_ingredient*` — how they differ

| | `IngredientSearch.search/3` | `IngredientQueries.search_ingredient_*_admin` (the FTS engine) |
|---|---|---|
| Matching engine | Prefix on `search_name` + pg_trgm `word_similarity` fuzzy fallback | Postgres FTS (`websearch_to_tsquery` on `searchable`) |
| Ranking | 5-tier (exact → word_similarity → length → food-class → alpha) | `ts_rank_cd` desc |
| Category hiding | `IngredientScope.exclude_secondary_categories/3` (shared) | `IngredientScope.exclude_secondary_categories/3` (shared) |
| Branded exclusion | Built into every query | Admin variants keep Branded (so admins can filter to it) |
| Owner/friends visibility | Yes (shared `IngredientScope`) | Yes (shared `IngredientScope`) |
| Result shape | Full `Ingredient` structs (or `%{id,name}` via `_for_select`) | `{query, page, count}` |
| Return on empty term | `[]` (guards) | Runs the query anyway |
| Role | **All user-facing name search** | **Admin** listing (pagination/count/data-types) + recipe/hashtag search |

**Why both survive — the split is by role, not duplication.** `IngredientQueries`
uniquely provides the admin listing's keyset pagination + total count + data-type
filtering + Branded-inclusive mode (none of which `IngredientSearch` has), plus
recipe and hashtag search — so it can't be deleted. `IngredientSearch` is the better
UX for type-as-you-go pickers (prefix + typo-tolerant fuzzy fallback). So user
name-search was **unified onto `IngredientSearch.search`** (calendar picker,
`recipe_generator`, and the `agent.ex` tool were repointed off `search_ingredient_alt`);
the FTS engine is now admin-only. With no callers left, the user-facing FTS wrapper
`search_ingredient_alt/3` and the `exclude_branded/1` helper it alone used were
**removed** (along with the facade delegate); the admin `search_ingredient_alt_admin/3`
keeps the FTS builder alive.

**Shared scopes (post-consolidation):** the owner/friends visibility helpers
(`filter_by_owner/2`, `visible_owner_ids/1`), `maybe_filter_by_classes/2`, and the
second-layer category helpers (`second_layer_category_ids/0`,
`exclude_secondary_categories/3`) used to be copy-pasted into both modules. They now
live once in `Food.IngredientScope` and both paths compose it. `IngredientQueries`
re-exports `maybe_filter_by_classes/2` and `get_second_layer_foods_ids/0` via
`defdelegate` so the `Mehungry.Food` facade and in-module callers are unchanged.
Unifying on `IngredientSearch` also made second-layer category hiding apply
consistently across every picker (it previously hid them only on the FTS path). The
dead legacy `search_ingredient2/1` and `search_ingredient3/1` (hard-coded category-id
exclusions, zero callers) were removed with their facade delegates.

---

## References across the codebase

### `IngredientSearch` (`search` / `search_for_select` / `search_in_language`)

| Caller | Call |
|---|---|
| `mehungry_web/live/create_recipe_live/ingredient_component.ex:69,84` | `search_in_language(term, "el", owner_id)` and `search(term, [], owner_id)` |
| `mehungry_web/live/calendar_live/components/ingredient_user_meal.html.heex:17` | `search(term, [], @current_user_id)` (calendar picker) |
| `mehungry_web/live/shopping_basket_live/index.ex:388` | `search(query, [], user_id)` |
| `mehungry_web/live/professional_live/ai_bot_live/setups.ex:98` | `search(query)` (seed-ingredient picker) |
| `mehungry/ai/agents/recipe_agent.ex:308,374` | `search(name)` (the `search_ingredient` tool handler + validation) |
| `mehungry/ai/recipe_generator.ex:117` | `search(name)` (ingredient resolution) |
| `mehungry/ai/agent.ex:26` | `search(name)` (the `search_ingredient` tool) |
| `mehungry/food_data/spoonacular_importer.ex:244` | `search(name)` (dedupe on import) |
| `mehungry/food/ingredient_queries.ex:50` | `search(ingredient_name)` inside `search_recipes_by_ingredient/1` |
| Tests | `friends_test.exs`, `user_ingredients_test.exs`, `ingredient_search_branded_test.exs` |

### `search_ingredient*` family (via `Mehungry.Food` facade)

| Caller | Call |
|---|---|
| `mehungry_web/live/professional_live/ingredients.ex:203,207,208` | `search_ingredient_admin_translated/4`, `search_ingredient_alt_admin/3`, `search_ingredient_admin/3` (admin listing, mode-switched) |
| Tests | `nutrient_test.exs`, `users_test.exs`, `seed_file_parser_test.exs`, `create_recipe_live_test.exs` (`search_ingredient/2`), `ingredient_search_branded_test.exs` (`search_ingredient_alt_admin/3`) |

The **admin ingredient listing is the only live consumer of the FTS family** — the
user-facing `search_ingredient_alt/3` was removed.

Note: `AI` code exposes a tool literally **named** `"search_ingredient"`
(`ai/agent.ex`, `ai/agents/recipe_agent.ex`) — that is the tool name shown to the
model, not the Elixir function. Both now back it with `Food.IngredientSearch.search`.

### Facade delegates (`apps/mehungry/lib/mehungry/food.ex`)

`search_ingredient_search`, `search_ingredient_alt_admin`, `search_ingredient_admin`,
`search_ingredient_admin_translated`, `search_ingredient`, `search_ingredient_query`
all `defdelegate … to: IngredientQueries`.
`IngredientSearch` is **not** delegated — callers use `Food.IngredientSearch.*`
directly.

---

## Related

- Ingredient schema & `search_name`: [`ingredients.md`](ingredients.md) ·
  [Ingredient entity](../entities/ingredient.md)
- Recipe full-text search: `Mehungry.Search.RecipeSearch`
- Species search (analogous prefix/translation search): `Food.SpeciesSearch`
- AI recipe agent tool wiring: [`../ai/ai.md`](../ai/ai.md)
