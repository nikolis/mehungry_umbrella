defmodule MehungryWeb.HealthLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.Health

  @impl true
  def mount(_params, _session, socket) do
    language = socket.assigns[:current_language] || "en"

    {:ok,
     socket
     |> assign(:conditions, Health.list_conditions_for_presentation(language))
     |> assign(:page_title, gettext("Health Conditions & Dietary Guidance"))
     |> assign(
       :page_description,
       gettext(
         "Browse health conditions and their dietary guidance — which bioactive compounds to avoid or limit, and the foods that contain them."
       )
     )}
  end
end
