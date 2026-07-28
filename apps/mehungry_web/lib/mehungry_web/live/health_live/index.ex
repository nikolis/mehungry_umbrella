defmodule MehungryWeb.HealthLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.Health

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:conditions, Health.list_conditions())
     |> assign(:page_title, "Health Conditions & Dietary Guidance")
     |> assign(
       :page_description,
       "Browse health conditions and their dietary guidance — which bioactive compounds to avoid or limit, and the foods that contain them."
     )}
  end
end
