defmodule MehungryWeb.Api.V1.BasketSharingController do
  @moduledoc """
  Sharing a shopping list (spec §10.1): the owner invites, revokes and removes;
  an invitee lists, accepts and declines; a member leaves. All rules live in
  `Mehungry.Inventory.Sharing`; inviting goes through `MehungryWeb.BasketSharing`
  (the same function the `/basket` LiveView uses) so the link and email are
  identical on both clients.
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Inventory
  alias MehungryWeb.Api.V1.BasketJSON
  alias MehungryWeb.BasketSharing

  action_fallback MehungryWeb.Api.V1.FallbackController

  # ── owner ──────────────────────────────────────────────────────────────

  def invitations(conn, %{"id" => id}) do
    with {:ok, basket_id} <- int(id),
         %{} <- Inventory.get_user_shopping_basket(user(conn).id, basket_id) do
      pending = Inventory.list_pending_basket_invitations(basket_id)
      json(conn, data(Enum.map(pending, &BasketJSON.invitation/1)))
    else
      _ -> {:error, :not_found}
    end
  end

  def invite(conn, %{"id" => id} = params) do
    locale = Gettext.get_locale(MehungryWeb.Gettext)

    with {:ok, basket_id} <- int(id),
         {:ok, invitation, url} <-
           BasketSharing.invite(user(conn), basket_id, params["email"] || "", locale) do
      conn |> put_status(:created) |> json(data(BasketJSON.invitation(invitation, url)))
    else
      :error ->
        {:error, :not_found}

      {:error, reason} when is_atom(reason) and reason not in [:not_found, :rate_limited] ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: BasketSharing.error_message(reason), code: reason}})

      other ->
        other
    end
  end

  def revoke(conn, %{"id" => id, "invitation_id" => invitation_id}) do
    with {:ok, basket_id} <- int(id),
         {:ok, invitation_id} <- int(invitation_id),
         :ok <- Inventory.revoke_basket_invitation(user(conn), basket_id, invitation_id) do
      send_resp(conn, :no_content, "")
    else
      :error -> {:error, :not_found}
      other -> other
    end
  end

  # The owner removes a member, or a member removes themselves (leaves).
  def remove_member(conn, %{"id" => id, "user_id" => user_id}) do
    with {:ok, basket_id} <- int(id),
         {:ok, user_id} <- int(user_id),
         true <- Inventory.can_access_basket?(user(conn).id, basket_id),
         :ok <- Inventory.remove_basket_member(user(conn), basket_id, user_id) do
      send_resp(conn, :no_content, "")
    else
      {:error, :forbidden} -> {:error, :forbidden}
      _ -> {:error, :not_found}
    end
  end

  # ── invitee ────────────────────────────────────────────────────────────

  def incoming(conn, _params) do
    invitations = Inventory.list_basket_invitations_for_user(user(conn).id)
    json(conn, data(Enum.map(invitations, &BasketJSON.incoming_invitation/1)))
  end

  def accept(conn, %{"id" => id}) do
    with {:ok, invitation_id} <- int(id),
         {:ok, basket} <- Inventory.accept_basket_invitation(user(conn), invitation_id) do
      joined(conn, basket)
    else
      error -> invitation_error(conn, error)
    end
  end

  # Accept from an invitation link opened in the app: `{ "token": "…" }`.
  def accept_token(conn, %{"token" => token}) when is_binary(token) do
    case Inventory.accept_invitation_by_token(user(conn), token) do
      {:ok, basket} -> joined(conn, basket)
      error -> invitation_error(conn, error)
    end
  end

  def accept_token(_conn, _params), do: {:error, :bad_request}

  def decline(conn, %{"id" => id}) do
    with {:ok, invitation_id} <- int(id),
         :ok <- Inventory.decline_basket_invitation(user(conn), invitation_id) do
      send_resp(conn, :no_content, "")
    else
      _ -> {:error, :not_found}
    end
  end

  # ── helpers ────────────────────────────────────────────────────────────

  defp joined(conn, basket) do
    basket = Inventory.get_accessible_basket(user(conn).id, basket.id)
    aisles = Inventory.aisle_for_items(basket.basket_items)
    json(conn, BasketJSON.basket(basket, aisles, user(conn).id))
  end

  defp invitation_error(conn, {:error, :basket_full}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{detail: BasketSharing.error_message(:basket_full), code: :basket_full}})
  end

  # Unknown, used, revoked, expired, or not addressed to the caller.
  defp invitation_error(_conn, _error), do: {:error, :not_found}

  defp user(conn), do: conn.assigns.current_user

  defp int(value) when is_integer(value), do: {:ok, value}

  defp int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp int(_), do: :error
end
