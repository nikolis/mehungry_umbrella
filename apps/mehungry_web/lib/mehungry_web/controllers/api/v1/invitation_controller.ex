defmodule MehungryWeb.Api.V1.InvitationController do
  @moduledoc """
  Consumer-side nutritionist invitations (spec §13/§14) — the Notifications
  screen. List pending invitations and accept/decline them. Backed by
  `Mehungry.Professionals`.
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Professionals

  action_fallback MehungryWeb.Api.V1.FallbackController

  def index(conn, _params) do
    invitations = Professionals.list_pending_invitations_for_client(uid(conn))
    json(conn, data(Enum.map(invitations, &invitation_json/1)))
  end

  def accept(conn, %{"id" => id}) do
    with {:ok, _assignment} <- Professionals.accept_invitation(to_int(id), uid(conn)) do
      json(conn, data(%{id: to_int(id), status: "accepted"}))
    end
  end

  def decline(conn, %{"id" => id}) do
    with {:ok, _inv} <- Professionals.decline_invitation(to_int(id), uid(conn)) do
      json(conn, data(%{id: to_int(id), status: "declined"}))
    end
  end

  defp invitation_json(inv) do
    professional = assoc(inv.professional)

    %{
      id: inv.id,
      status: inv.status,
      message: inv.message,
      professional:
        professional && %{id: professional.id, alias: professional.name || professional.email}
    }
  end

  defp assoc(%Ecto.Association.NotLoaded{}), do: nil
  defp assoc(value), do: value

  defp uid(conn), do: conn.assigns.current_user.id
  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
end
