defmodule MehungryWeb.Api.V1.NotificationController do
  @moduledoc """
  The notification inbox (spec §13). The durable source of truth for the mobile
  inbox + unread badge; the `user:<id>` channel delivers the same records live.
  Backed by `Mehungry.Notifications`.
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Notifications
  alias MehungryWeb.Api.Pagination
  alias MehungryWeb.Api.V1.NotificationJSON

  action_fallback MehungryWeb.Api.V1.FallbackController

  @doc "GET /me/notifications — paginated inbox, newest first."
  def index(conn, params) do
    uid = conn.assigns.current_user.id
    {page, page_size} = Pagination.params(params)

    # Over-fetch one page to compute has_more without a count query.
    rows = Notifications.list(uid, limit: page * page_size + 1)
    {page_rows, meta} = Pagination.paginate_list(rows, {page, page_size})

    json(conn, data(Enum.map(page_rows, &NotificationJSON.render/1), meta))
  end

  @doc "GET /me/notifications/unread_count — badge count."
  def unread_count(conn, _params) do
    json(conn, data(%{count: Notifications.unread_count(conn.assigns.current_user.id)}))
  end

  @doc "POST /me/notifications/read — mark all read, or one when `id` is given."
  def read(conn, params) do
    uid = conn.assigns.current_user.id

    case params["id"] do
      nil -> Notifications.mark_all_read(uid)
      id -> Notifications.mark_read(uid, to_int(id))
    end

    json(conn, data(%{unread_count: Notifications.unread_count(uid)}))
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
end
