defmodule MehungryWeb.Api.RequireNutritionistPlug do
  @moduledoc """
  Gates the `/api/v1/nutritionist/**` surface (spec §14) to users on the
  nutritionist (`"pro"`) tier. Runs after `AuthPlug`, so `:current_user` is set.
  """
  import Plug.Conn

  alias Mehungry.Subscriptions

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user]

    if user && Subscriptions.nutritionist?(user.id) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(403, Jason.encode!(%{errors: %{detail: "forbidden", upgrade: true}}))
      |> halt()
    end
  end
end
