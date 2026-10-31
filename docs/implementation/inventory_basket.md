# Shopping Basket (`Mehungry.Inventory`)

The grocery/shopping-list feature: a user's baskets and their items, plus the two
"fill it for me" flows (import a recipe's or a meal's ingredients, and build a list for a
whole calendar week). Backed by `Mehungry.Inventory` and
`MehungryWeb.ShoppingBasketLive` (`/basket`).

---

## Data model

| Schema (table) | Role |
|---|---|
| `ShoppingBasket` (`shopping_baskets`) | a named list owned by a user |
| `BasketItem` (`basket_items`) | one line: name, quantity, unit, `in_storage` toggle, optional `recipe_id` / `usda_fdc_id` / nutrition payload |
| `BasketIngredient` (`basket_ingredients`) | the structured ingredient variant of a line |
| `BasketParams` (embedded) | form params for the add/edit flow |

A line can be a free-text/USDA-searched item **or** a resolved app ingredient; the
`in_storage` checkbox is the "already have it" toggle.

## Context API

- **Baskets:** `list_shopping_baskets_for_user/_`, `get_shopping_basket!/_`,
  `get_or_create_basket_for_user/_`, `create_/update_/delete_shopping_basket/_`,
  `delete_all_baskets_for_user/_`.
- **Items/ingredients:** `add_item/_`, `get_basket_item!/_`, `update_/delete_basket_item/_`;
  `create_/update_/delete_basket_ingredient/_`, `toggle_basket_ingredient/_`,
  `list_basket_ingredients/_`.
- **Imports (the value flows):**
  - `add_items_from_recipe/_` — add all of a recipe's ingredients (the recipe detail
    "add to shopping list").
  - `add_items_from_meal/_` — add a planned calendar meal's ingredients.
  - `aggregate_meal_ingredients/1` — **shared** ingredient-aggregation used by both the
    calendar and the basket so quantities combine identically on either surface (no
    divergent copy).

## "Shopping list for the week"

The calendar's one-click action → `create_basket_for_range/4`: builds (or re-opens) a
basket covering a date range by aggregating that week's meals. It is **non-duplicating** —
`get_basket_for_week/2` returns the week's existing list instead of making a second one;
the calendar lands the user on `/basket?basket_id=…` with a localized title. Driven from
[`history_calendar.md`](history_calendar.md); see memory *Calendar Self-Tracker Roadmap*.

## Surfaces

- **Web:** `/basket` (`ShoppingBasketLive`) — list management, USDA-search add, recipe/meal
  import, `in_storage` toggle.
- **Mobile API:** `/api/v1/basket*` — full mirror incl. `POST /basket/import/recipe/:id`
  and `/basket/import/meal/:id`, specified in
  [`new_dec_specs/mobile_api_spec.md`](new_dec_specs/mobile_api_spec.md) §10. The
  ingredient search that feeds it (`?source=local`) reuses `Food.IngredientSearch`.

## Related

- [`history_calendar.md`](history_calendar.md) — the calendar that drives the week flow and shares `aggregate_meal_ingredients/1`.
- [`food/ingredient_search.md`](food/ingredient_search.md) — the ingredient picker/search behind add-item.
