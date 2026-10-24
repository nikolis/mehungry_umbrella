# Notification System

**Status:** Phase 1 (in-app, durable) **and** Phase 2 backend (Expo OS push) implemented.
Mobile-side `expo-notifications` registration (requesting permission + calling
`POST /me/devices`) is the remaining client work.
**Scope:** user-facing activity notifications for the mobile app (`mehungry_android`,
Expo / React Native) backed by the Phoenix umbrella. Live types: **a comment on your
recipe**, **a reply to your comment**, and **a new follower**. Tapping a notification
deep-links to the relevant screen.

The REST/channel contract lives in `docs/new_dec_specs/mobile_api_spec.md` (§5.1 inbox,
§13 `user:<id>` channel) — that is the client contract and must not drift from the
implementation.

---

## 1. Core principle

**The database is the source of truth. The channel is a live "poke". OS push is the
offline fallback (Phase 2).** All deliveries carry the *same* enriched payload (§4), so
the mobile client has one render + route path regardless of how a notification arrived.

The live channel event is treated as an *invalidation signal* (prepend to the
React-Query cache + bump the badge), never the sole record — the inbox always reloads
from REST.

## 2. Data model — `Mehungry.Notifications` (core app)

Table `notifications` (migration `20261021090000_create_notifications.exs`):

| column | type | notes |
|---|---|---|
| `recipient_id` | FK users (delete_all) | who sees it |
| `actor_id` | FK users (nilify), null | who caused it (null = system/ai) |
| `type` | string | `follow` \| `comment` \| `comment_answer` \| `ai_ready` \| `invitation` |
| `subject_type` / `subject_id` | string / bigint, null | deep-link target |
| `data` | map (jsonb) | denormalized render bits (`recipe_title`, `preview`) |
| `read_at` | utc, null | nil until inbox opened |

Indexes: `(recipient_id, inserted_at)` (inbox); partial `(recipient_id) where read_at
IS NULL` (badge). Context (`lib/mehungry/notifications.ex`) is pure domain — never
broadcasts:
- `create/3` — insert; returns `:ignored` for self-notifications (`actor_id ==
  recipient_id`) and duplicate unread follows.
- `emit/3` — `create/3` then hand the persisted row to the configured **dispatcher**
  for delivery (channel + push). This is the single trigger contexts call.
- `list/2` (newest first, `:limit`/`:before` cursor, preloads `:actor`),
  `unread_count/1`, `mark_read/2`, `mark_all_read/1`.

## 3. Emission — triggered **in the context**, delivered via a dispatcher seam

Emission lives **inside the domain functions that create the resource**, so every client
— LiveView, REST, and the channel — fires a notification from one place (the
REST↔LiveView parity rule). Earlier the trigger lived in the `/api/v1` controllers only,
so web-client (LiveView) comments/follows produced nothing — that bug is why this moved
down.

`Notifications.emit/3` persists (`create/3`) then calls `dispatcher().deliver(notification)`.
The dispatcher is a config seam (`:notification_dispatcher`, like `:instagram_client`):
- default `Mehungry.Notifications.NoopDispatcher` keeps the core app web-free;
- the running app wires `MehungryWeb.Api.NotificationDispatcher`, which renders the §4
  payload, `Endpoint.broadcast`-es it to `user:<id>`, and calls `PushDispatch.enqueue/2`
  (presence-gated Expo push). It no-ops when the endpoint isn't running (core-only tests),
  leaving the already-persisted row as the record.

Trigger sites (context):
- **Comment on your recipe** — `Mehungry.Posts.create_comment/1` → `emit(recipe.user_id,
  "comment", actor_id: comment.user_id, subject: recipe, data: %{recipe_title, preview})`.
- **Reply to your comment** — `Posts.create_comment_answer/1` → `emit(comment.user_id,
  "comment_answer", actor_id: answer.user_id, subject: the recipe, data: %{preview})`.
- **New follower** — `Accounts.UserContent.save_user_follow/2` → `emit(target, "follow",
  actor_id: follower, subject: follower's user)`.

The `/api/v1` controllers and the LiveView components no longer emit — they just call the
context functions above.

## 4. Contract (shared by REST + channel + push)

Serialized by `Api.V1.NotificationJSON.render/1`:

```jsonc
{
  "id": 12345,
  "type": "comment",
  "actor": { "id": 42, "alias": "Maria", "avatar_url": "https://…" },  // null for system
  "subject": { "type": "recipe", "id": 987 },                          // deep-link target, nullable
  "data": { "recipe_title": "Fasolada", "preview": "Looks delicious!" },
  "read": false,
  "inserted_at": "2026-10-20T10:12:00Z"
}
```

## 5. REST inbox (authenticated, `/api/v1`)

Source of truth (`NotificationController`):
```
GET  /me/notifications               → { data: [Notification], meta: { page, page_size, has_more } }
GET  /me/notifications/unread_count   → { data: { count } }
POST /me/notifications/read           → mark all (body { id } for one) → { data: { unread_count } }
```

## 6. Mobile (`mehungry_android`)

- `types/api.ts` — the §4 `Notification` contract (`actor`, `subject`, `read`, `inserted_at`).
- `hooks/useNotifications.ts` — `useNotifications` (infinite inbox, persisted cache =
  offline inbox), `useUnreadCount`, `useMarkAllRead`.
- `hooks/useRealtime.ts` `useNotificationsRealtime` — on `"notification"`: prepend to the
  `qk.notifications` cache, invalidate `qk.unreadCount`, toast via the store.
- `store/notifications.ts` — slimmed to the live unread counter + latest (toast), seeded
  from the server count.
- `lib/routeForNotification.ts` `navigateToNotification` — `recipe` → `RecipeDetail`,
  `user`/`follow` → `PublicProfile`.
- `screens/profile/NotificationsScreen.tsx` — server-backed `FlatList`, infinite scroll,
  tap → deep-link, mark-all-read on mount.
- `navigation/TabNavigator.tsx` — unread badge on the Profile tab.

## 7. Phase 2 — OS push (Expo), backend implemented

Device tokens live in `user_devices` (migration `20261021100000`), managed by
`Mehungry.Notifications.{register_device,delete_device,delete_device_token,tokens_for_user}`
and the REST endpoints `POST /me/devices` / `DELETE /me/devices/:token`
(`Api.V1.DeviceController`). A token is unique and **moves** to whichever user last
registered it (shared hardware).

`MehungryWeb.Api.PushDispatch.enqueue/2` (called by `Broadcaster.dispatch/5`) is now real:
- **Presence-gated** — if `MehungryWeb.Presence.list("user:#{id}")` is non-empty the
  recipient is connected (tracked on `UserChannel` join) and already got the live
  broadcast, so no push is enqueued.
- Otherwise it enqueues `Mehungry.ObanWorkers.PushNotificationWorker` (`:mailers` queue),
  which loads the recipient's device tokens and sends one Expo message per token
  (`%{to, title, body, data: <§4 contract>}`) via the `Mehungry.Notifications.ExpoPushClient`
  seam (real impl `ExpoPush` → `https://exp.host/--/api/v2/push/send`, stubbed in tests
  via `:expo_push_client`). Title/body copy is English for now (`copy_for/1`); localization
  is a later pass. Tokens Expo reports as `DeviceNotRegistered` are pruned.

Optional runtime config `:expo_access_token` (`EXPO_ACCESS_TOKEN`) is sent as a bearer
when set. **Remaining client work**: `expo-notifications` in the RN app to obtain the
token + call `POST /me/devices` on login and `DELETE` on logout.
