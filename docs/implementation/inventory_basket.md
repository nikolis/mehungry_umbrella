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

A line can be a free-text/USDA-searched item (`BasketItem`, with an optional
free-text `description` unit label when it has no `MeasurementUnit` row) **or** a
recipe-derived app ingredient (`BasketIngredient`, carries `ingredient` →
`category` + `ingredient_translation`). The `in_storage` boolean is the
"already have it / acquired" toggle on **both** schemas (there is no separate
`checked` column). USDA nutrition captured at add time is persisted in
`BasketItem.nutrition_data` (the changeset casts it).

## Context API

- **Baskets:** `list_shopping_baskets_for_user/_`, `get_shopping_basket!/_`,
  `get_user_shopping_basket/2` (**owner-scoped** lookup — returns `nil` for another
  user's id; use this for any id taken from a route param or LiveView event),
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

## Web UI (`ShoppingBasketLive`)

`/basket` is a sidebar of the user's lists + a main checklist panel + an add-item
modal (the shared `core_components` `<.modal>`, so it gets a real focus trap). The
LiveView is fully localized (EN/EL via Gettext; strings live in the catalogs under
`apps/mehungry_web/priv/gettext`) and themed on the `ink/paprika/basil/parchment`
design system; the `.basket-page` root class rethemes the shared `SelectComponent`
via CSS variables (`apps/mehungry_web/assets/css/basket.css`, which is now *only*
that retheme — layout + the mobile Lists drawer are Tailwind utilities).

- **Lists:** create / **rename** (inline `BasicFormComponent`, `:new`/`:edit`) /
  delete (with a `data-confirm`) / switch. All reads are owner-scoped via
  `get_user_shopping_basket/2`; deleting the active list falls back to another.
- **Items, grouped by grocery aisle:** entries are grouped with
  `Mehungry.PublishedPlans.GroceryAisle` (`classify/1`·`ordered/0`·`label/1` — the
  same aisle map the published-plan grocery list uses), in canonical shop order,
  acquired items sinking within each group. Recipe-derived vs manually-added lines
  carry a **provenance chip** ("From plan" / "Added"); a **progress bar** shows
  acquired/total. Each row has an `in_storage` check-off, inline **edit**
  (quantity, + name for `BasketItem`s) and **delete** (`data-confirm`). Items with
  no resolvable category (manual/USDA `BasketItem`s) fall into the **"Other"**
  aisle.
- **Add item:** one modal with three sources — USDA search (`SearchClient`, with a
  searching spinner + a "no matches → add manually" state), the user's own custom
  ingredients (reusing the USDA confirm panel), and manual entry (name + quantity +
  `SelectComponent` unit). The USDA quantity/unit come from the confirm **form's**
  submit params (not a pinned default), so the typed amount is what's added.
- **Deferred:** a "cart nutrition" macro donut was intentionally **not** built —
  nutrition today lives only on USDA `BasketItem`s, so a truthful total needs
  per-ingredient nutrition joins first. Tracked as a follow-up.

## Surfaces

- **Web:** `/basket` (`ShoppingBasketLive`) — see above.
- **Mobile API:** `/api/v1/basket*` — full mirror incl. `POST /basket/import/recipe/:id`
  and `/basket/import/meal/:id`, specified in
  [`new_dec_specs/mobile_api_spec.md`](new_dec_specs/mobile_api_spec.md) §10. The
  ingredient search that feeds it (`?source=local`) reuses `Food.IngredientSearch`.
  Each serialized item also carries an `aisle` key so the mobile client can group
  by grocery aisle exactly like this LiveView. Because `BasketItem` has no category
  association, the aisle is resolved at read time (`Inventory.aisle_for_items/1`):
  the category is looked up from the catalog by `usda_fdc_id` or the name's
  `search_name`, then classified with `GroceryAisle` — the same approach the
  published-plan list uses. Unmatched manual lines → `"other"`.

## Related

- [`history_calendar.md`](history_calendar.md) — the calendar that drives the week flow and shares `aggregate_meal_ingredients/1`.
- [`food/ingredient_search.md`](food/ingredient_search.md) — the ingredient picker/search behind add-item.
