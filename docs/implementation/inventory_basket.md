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
| `BasketMember` (`shopping_basket_members`) | a person the list is shared with (the owner stays on `shopping_baskets.user_id` and has no row) |
| `BasketInvitation` (`shopping_basket_invitations`) | a single-use, expiring invitation; stores only the SHA-256 of its link token |

A line can be a free-text/USDA-searched item (`BasketItem`, with an optional
free-text `description` unit label when it has no `MeasurementUnit` row) **or** a
recipe-derived app ingredient (`BasketIngredient`, carries `ingredient` →
`category` + `ingredient_translation`). The `in_storage` boolean is the
"already have it / acquired" toggle on **both** schemas (there is no separate
`checked` column). USDA nutrition captured at add time is persisted in
`BasketItem.nutrition_data` (the changeset casts it). Both line schemas also
carry `added_by_id` / `acquired_by_id` (who added the line, who ticked it off) —
set by the context from the acting user, never cast from client params.

## Context API

- **Baskets:** `list_shopping_baskets_for_user/_` (owned **and shared-with-me**),
  `get_shopping_basket!/_` (unscoped — internal use only),
  `get_accessible_basket/2` (**owner-or-member** lookup — the one to use for
  reading a list or changing its items from a route param / event id),
  `get_user_shopping_basket/2` (**owner-only** lookup — for list-level changes:
  rename, delete, rebuild from the calendar, sharing), `basket_role/2`
  (`:owner | :member | nil`), `can_access_basket?/2`,
  `get_or_create_basket_for_user/_`, `create_/update_/delete_shopping_basket/_`,
  `delete_all_baskets_for_user/_`.
- **Items/ingredients:** `add_item/_`, `get_basket_item!/_`, `update_/delete_basket_item/_`;
  `create_/update_/delete_basket_ingredient/_`, `set_acquired/3`,
  `toggle_basket_ingredient/_`, `list_basket_ingredients/_`. The mutating ones take
  the acting user id (for attribution) and are written to be safe when two people
  edit at once — see § Sharing.
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

## Sharing (`Mehungry.Inventory.Sharing`)

Product rules: [`../features/shared_basket.md`](../features/shared_basket.md). All of
them are enforced in `Inventory.Sharing` (delegated from the `Inventory` facade), so
the LiveView, the REST API and the channel cannot diverge.

- **Access model.** Owner = `shopping_baskets.user_id`; members =
  `shopping_basket_members`. `get_accessible_basket/2` is the single read/item-write
  chokepoint; `get_user_shopping_basket/2` stays owner-only for list-level changes.
  Every basket loader uses one preload shape (`@basket_preloads`: items, ingredients,
  `user`, `members: :user`), so a basket struct is the same whichever loader produced it.
- **Invitations.** `invite/3` (owner + confirmed email + `RateLimit` 20/h + size
  limits) inserts a `BasketInvitation` and returns `{:ok, invitation, token}` — the raw
  token exists only in that return value (the row holds its hash), so the caller builds
  the link immediately. `MehungryWeb.BasketSharing.invite/4` is that caller for **both**
  web and REST: it builds `/basket/invitations/:token` and, when an email was given,
  sends `UserNotifier.deliver_basket_invitation/5` (EN/EL). If the email belongs to an
  account, `invitee_user_id` is set and a `basket_invitation` notification is emitted.
- **Answering.** `accept_by_token/2` (the link) and `accept/2` (in-app, only for the
  addressed user) share one transaction that locks the invitation **and** the basket
  row, so a link admits exactly one person and concurrent accepts cannot overshoot the
  6-person limit. `decline/2` is silent. `preview_invitation/1` exposes only the
  inviter's name and the list title.
- **Membership.** `remove_member/3` — the owner removes anyone, a member removes only
  themselves. `people/1` returns owner-first `%{id, name, avatar_url, role}`; `name` is
  the profile alias or account name, never an email.
- **Blocks.** `Moderation.block_user/2` calls `Sharing.handle_block/2`: each leaves the
  other's lists and pending invitations between them are revoked. An invitation to a
  blocked pair is stored but neither addressed, notified nor emailed, and `accept`
  refuses it.
- **Account deletion.** `Accounts.Admin.delete_user/1` calls
  `Sharing.transfer_shared_baskets/1` first: a list the user owns and shares goes to its
  longest-standing member; unshared lists are deleted as before.
- **Live updates.** Every mutation broadcasts on the PubSub topic `basket:<id>` to
  everyone **except the calling process**. There are three messages
  (`Inventory.subscribe/1` documents them):
  - `{:basket_entry, id, %{op: :upsert | :delete, entry: entry, actor_id: id}}` — one
    line was added, changed, ticked or removed (`Inventory.broadcast_entry_change/4`,
    from `add_item`, `update_/delete_basket_item`, `set_acquired`,
    `create_/update_/delete_basket_ingredient`). It **carries the line**, so a
    subscriber patches its copy and runs no query.
  - `{:basket_changed, id}` — anything else (recipe/meal import, rename, members,
    invitations): a poke to re-read the list (`Inventory.broadcast_change/2`).
  - `{:basket_deleted, id}` — the list is gone.

  `ShoppingBasketLive.Index` subscribes to every list the user can see and applies
  entry events with `apply_entry/4` (it patches the list in the sidebar and the open
  panel; a line it cannot place from the event falls back to a re-read). The same
  helper applies the view's **own** item actions from the struct the context
  returns, so a tick is one `UPDATE` and no reload. `MehungryWeb.BasketChannel`
  joins the same topic for mobile, re-checks access on each message, and forwards
  entry events as `item_upserted` / `item_deleted` to clients that joined with
  `{"v": 2}` (a poke to older clients) — mobile spec §13.

  The message shapes must only change compatibly: nodes are clustered and two
  releases overlap during a rolling deploy.
- **Concurrent edits.** `set_acquired/3` writes an explicit state with a single
  `UPDATE` instead of flipping a possibly stale struct. Deletes use `allow_stale`
  (deleting an already-deleted line succeeds); updates use `stale_error_field` (an
  update to a deleted line returns `{:error, changeset}` instead of raising).

## Web UI (`ShoppingBasketLive`)

`/basket` is a sidebar of the user's lists + a main checklist panel + an add-item
modal (the shared `core_components` `<.modal>`, so it gets a real focus trap). The
LiveView is fully localized (EN/EL via Gettext; strings live in the catalogs under
`apps/mehungry_web/priv/gettext`) and themed on the `ink/paprika/basil/parchment`
design system; the `.basket-page` root class rethemes the shared `SelectComponent`
via CSS variables (`apps/mehungry_web/assets/css/basket.css`, which is now *only*
that retheme — layout + the mobile Lists drawer are Tailwind utilities).

- **Lists:** create / **rename** (inline `BasicFormComponent`, `:new`/`:edit`) /
  delete (with a `data-confirm`) / switch. Reads go through
  `get_accessible_basket/2` (owned or shared); rename / delete / calendar rebuild
  through the owner-only `get_user_shopping_basket/2`. Deleting the active list
  falls back to another. A list someone else owns shows "Shared by …" and a
  **Leave** button in place of the owner controls.
- **Sharing:** the header **Share** button opens a `core_components` modal
  (`share_panel/1`): invite form (email optional), the freshly created link with a
  `Copy` hook, pending invitations (revoke) and the people on the list (remove /
  leave). Invitations addressed to the signed-in user appear above the list
  (`my_invitations/1`, Join / Decline). The link itself lands on
  `ShoppingBasketLive.Invitation` (`/basket/invitations/:token`, authenticated).
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
  [`new_dec_specs/mobile_api_spec.md`](new_dec_specs/mobile_api_spec.md) §10; sharing
  (`/baskets`, invitations, members, the `basket:<id>` channel) is §10.1 / §13. The
  ingredient search that feeds it (`?source=local`) reuses `Food.IngredientSearch`.
  Each serialized item also carries an `aisle` key so the mobile client can group
  by grocery aisle exactly like this LiveView. Because `BasketItem` has no category
  association, the aisle is resolved at read time (`Inventory.aisle_for_items/1`):
  the category is looked up from the catalog by `usda_fdc_id` or the name's
  `search_name`, then classified with `GroceryAisle` — the same approach the
  published-plan list uses. Unmatched manual lines → `"other"`.

## Related

- [`../features/shared_basket.md`](../features/shared_basket.md) — the product rules for sharing a list.
- [`history_calendar.md`](history_calendar.md) — the calendar that drives the week flow and shares `aggregate_meal_ingredients/1`.
- [`food/ingredient_search.md`](food/ingredient_search.md) — the ingredient picker/search behind add-item.
