defmodule Mehungry.ObanWorkers.PushNotificationWorker do
  @moduledoc """
  Delivers a notification to a recipient's registered devices via Expo push,
  off the request cycle on the `:mailers` queue. Enqueued by
  `MehungryWeb.Api.PushDispatch` only when the recipient is **not** currently
  connected (an in-app client already got the live `user:<id>` broadcast).

  The job args carry the already-rendered §4 notification payload (same object
  the channel and REST inbox serve), so the worker only needs the recipient's
  device tokens + title/body copy. Tokens Expo reports as `DeviceNotRegistered`
  are pruned. See `docs/implementation/notifications_system.md` §7.
  """
  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias Mehungry.Notifications

  @doc "Enqueue a push for `recipient_id` carrying the §4 `notification` payload."
  def enqueue(recipient_id, notification) do
    %{"recipient_id" => recipient_id, "notification" => notification}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"recipient_id" => recipient_id, "notification" => notification}}) do
    case Notifications.tokens_for_user(recipient_id) do
      [] ->
        :ok

      tokens ->
        {title, body} = copy_for(notification)
        # Unread count → app-icon badge (iOS sets `aps.badge`; Android launchers
        # that support numeric badges use it, otherwise show a dot). Includes the
        # just-persisted notification, so it matches the in-app badge.
        badge = Notifications.unread_count(recipient_id)

        messages =
          Enum.map(tokens, fn token ->
            %{to: token, title: title, body: body, data: notification, badge: badge}
          end)

        case client().push(messages) do
          {:ok, tickets} ->
            prune_dead_tokens(tokens, tickets)
            :ok

          {:error, reason} ->
            # Transport/HTTP failure — let Oban retry.
            {:error, reason}
        end
    end
  end

  # Expo returns one ticket per message, in order; drop tokens it rejects as
  # permanently unroutable so we stop pushing to uninstalled apps.
  defp prune_dead_tokens(tokens, tickets) do
    tokens
    |> Enum.zip(tickets)
    |> Enum.each(fn {token, ticket} ->
      if dead_token?(ticket), do: Notifications.delete_device_token(token)
    end)
  end

  defp dead_token?(%{"status" => "error", "details" => %{"error" => "DeviceNotRegistered"}}),
    do: true

  defp dead_token?(_), do: false

  # English push copy for now (localization is a later pass — §7).
  defp copy_for(%{"type" => type} = notification) do
    actor = actor_name(notification)
    title = notification |> Map.get("data", %{}) |> Map.get("recipe_title")

    case type do
      "follow" ->
        {"New follower", "#{actor} started following you"}

      "comment" ->
        {"New comment", comment_body(actor, title)}

      "comment_answer" ->
        {"New reply", "#{actor} replied to your comment"}

      "ai_ready" ->
        {"Your plan is ready", "Your AI meal plan is ready to view"}

      "invitation" ->
        {"New invitation", "#{actor} sent you an invitation"}

      _ ->
        {"M3Hungry", "You have a new notification"}
    end
  end

  defp comment_body(actor, nil), do: "#{actor} commented on your recipe"
  defp comment_body(actor, title), do: "#{actor} commented on #{title}"

  defp actor_name(%{"actor" => %{"alias" => alias}}) when is_binary(alias), do: alias
  defp actor_name(_), do: "Someone"

  defp client do
    Application.get_env(:mehungry, :expo_push_client, Mehungry.Notifications.ExpoPush)
  end
end
