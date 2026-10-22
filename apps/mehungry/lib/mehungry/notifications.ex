defmodule Mehungry.Notifications do
  @moduledoc """
  Durable activity notifications (comment-on-your-recipe, new-follower, …).

  The database is the source of truth: the web layer persists a row here, then
  the live channel / OS push are best-effort deliveries of the *same* record
  (see `MehungryWeb.Api.Broadcaster` and `docs/notifications_system.md`). This
  context is web-agnostic — it never broadcasts.

  Two guards live in `create/3`:

    * self-notification suppression — you never get told about your own action;
    * follow de-dupe — an unread "X followed you" isn't stacked on unfollow/
      refollow.
  """
  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Notifications.Device
  alias Mehungry.Notifications.Notification

  @default_limit 20

  @doc """
  Insert a notification for `recipient_id`.

  Options: `:actor_id`, `:subject_type`, `:subject_id`, `:data`.

  Returns `{:ok, notification}` on insert, `:ignored` when the event is a
  self-notification or a duplicate unread follow, or `{:error, changeset}`.
  """
  def create(recipient_id, type, opts \\ []) do
    actor_id = opts[:actor_id]

    cond do
      actor_id != nil and actor_id == recipient_id ->
        :ignored

      type == "follow" and duplicate_unread_follow?(recipient_id, actor_id) ->
        :ignored

      true ->
        %Notification{}
        |> Notification.changeset(%{
          recipient_id: recipient_id,
          actor_id: actor_id,
          type: type,
          subject_type: opts[:subject_type],
          subject_id: opts[:subject_id],
          data: opts[:data] || %{}
        })
        |> Repo.insert()
    end
  end

  @doc """
  Persist a notification (`create/3`) and deliver it to the outside world via
  the configured dispatcher (channel push + OS push). This is the single entry
  point contexts call when a relevant resource is created, so every client —
  LiveView, REST, channel — triggers a notification. Delivery is a no-op in the
  core app (no web layer); the running web app wires the real dispatcher.

  Returns the same values as `create/3` (`:ignored` for suppressed events).
  """
  def emit(recipient_id, type, opts \\ []) do
    case create(recipient_id, type, opts) do
      {:ok, notification} ->
        dispatcher().deliver(notification)
        {:ok, notification}

      other ->
        other
    end
  end

  defp dispatcher do
    Application.get_env(:mehungry, :notification_dispatcher, Mehungry.Notifications.NoopDispatcher)
  end

  @doc """
  List a recipient's notifications, newest first, with the actor preloaded.

  Options: `:limit` (default #{@default_limit}), `:before` — a `{inserted_at, id}`
  cursor (exclusive) for pagination.
  """
  def list(recipient_id, opts \\ []) do
    limit = opts[:limit] || @default_limit

    Notification
    |> where([n], n.recipient_id == ^recipient_id)
    |> apply_cursor(opts[:before])
    |> order_by([n], desc: n.inserted_at, desc: n.id)
    |> limit(^limit)
    |> preload(:actor)
    |> Repo.all()
  end

  @doc "Count a recipient's unread notifications."
  def unread_count(recipient_id) do
    Notification
    |> where([n], n.recipient_id == ^recipient_id and is_nil(n.read_at))
    |> Repo.aggregate(:count, :id)
  end

  @doc "Mark a single notification read (scoped to its recipient). Returns `:ok`."
  def mark_read(recipient_id, id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Notification
    |> where([n], n.recipient_id == ^recipient_id and n.id == ^id and is_nil(n.read_at))
    |> Repo.update_all(set: [read_at: now])

    :ok
  end

  @doc "Mark all of a recipient's unread notifications read. Returns `:ok`."
  def mark_all_read(recipient_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Notification
    |> where([n], n.recipient_id == ^recipient_id and is_nil(n.read_at))
    |> Repo.update_all(set: [read_at: now])

    :ok
  end

  defp duplicate_unread_follow?(_recipient_id, nil), do: false

  defp duplicate_unread_follow?(recipient_id, actor_id) do
    Notification
    |> where(
      [n],
      n.recipient_id == ^recipient_id and n.actor_id == ^actor_id and
        n.type == "follow" and is_nil(n.read_at)
    )
    |> Repo.exists?()
  end

  defp apply_cursor(query, nil), do: query

  defp apply_cursor(query, {inserted_at, id}) do
    where(
      query,
      [n],
      n.inserted_at < ^inserted_at or (n.inserted_at == ^inserted_at and n.id < ^id)
    )
  end

  # ── devices (OS push) ──────────────────────────────────────────────────────

  @doc """
  Register (or refresh) a device's Expo push token for `user_id`. Upserts on the
  token so a device re-registering — including under a different user — moves to
  the current owner. Bumps `last_seen_at`.
  """
  def register_device(user_id, expo_token, platform) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Device{}
    |> Device.changeset(%{
      user_id: user_id,
      expo_token: expo_token,
      platform: platform,
      last_seen_at: now
    })
    |> Repo.insert(
      on_conflict: [set: [user_id: user_id, platform: platform, last_seen_at: now, updated_at: now]],
      conflict_target: :expo_token
    )
  end

  @doc "Remove a device token owned by `user_id` (device logout). Returns `:ok`."
  def delete_device(user_id, expo_token) do
    Device
    |> where([d], d.user_id == ^user_id and d.expo_token == ^expo_token)
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Remove a device token regardless of owner — used by the push worker to prune a
  token Expo reports as `DeviceNotRegistered`. Returns `:ok`.
  """
  def delete_device_token(expo_token) do
    Device
    |> where([d], d.expo_token == ^expo_token)
    |> Repo.delete_all()

    :ok
  end

  @doc "All Expo push tokens registered for `user_id`."
  def tokens_for_user(user_id) do
    Device
    |> where([d], d.user_id == ^user_id)
    |> select([d], d.expo_token)
    |> Repo.all()
  end
end
