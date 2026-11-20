defmodule MehungryWeb.Api.V1.ModerationController do
  @moduledoc """
  Report user-generated content and block users (spec §20; App Store Guideline
  1.2). Backed by `Mehungry.Moderation`. Reports are reviewed by the admin in
  `/professional/moderation`; the reported user is never told who reported them.
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Moderation

  action_fallback MehungryWeb.Api.V1.FallbackController

  @doc "POST /api/v1/reports — `{target_type, target_id, reason, note?}`."
  def report(conn, params) do
    with {:ok, report, outcome} <- Moderation.create_report(conn.assigns.current_user, params) do
      conn
      |> put_status(if(outcome == :created, do: :created, else: :ok))
      |> json(data(%{id: report.id, status: report.status}))
    end
  end

  @doc "POST /api/v1/users/:id/block"
  def block(conn, %{"id" => id}) do
    with {:ok, target} <- parse_id(id),
         :ok <- Moderation.block_user(conn.assigns.current_user, target) do
      json(conn, data(%{blocked: true}))
    end
  end

  @doc "DELETE /api/v1/users/:id/block"
  def unblock(conn, %{"id" => id}) do
    with {:ok, target} <- parse_id(id),
         :ok <- Moderation.unblock_user(conn.assigns.current_user, target) do
      json(conn, data(%{blocked: false}))
    end
  end

  @doc "GET /api/v1/me/blocks — the users the caller has blocked, newest first."
  def blocks(conn, _params) do
    blocks =
      conn.assigns.current_user
      |> Moderation.list_blocks()
      |> Enum.map(fn %{user: user, alias: user_alias, blocked_at: at} ->
        %{id: user.id, alias: user_alias, avatar_url: user.profile_pic, blocked_at: utc(at)}
      end)

    json(conn, data(blocks))
  end

  defp parse_id(id) when is_integer(id), do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :not_found}
    end
  end
end
