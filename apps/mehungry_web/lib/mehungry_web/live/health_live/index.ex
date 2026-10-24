defmodule MehungryWeb.HealthLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.Health

  @impl true
  def mount(_params, session, socket) do
    language = socket.assigns[:current_language] || "en"

    {:ok,
     socket
     |> assign(:conditions, Health.list_conditions_for_presentation(language))
     |> assign(:base, conditions_base(session, language))
     |> assign_new(:locale, fn -> language end)
     |> assign(:page_title, gettext("Health Conditions & Dietary Guidance"))
     |> assign(
       :page_description,
       gettext(
         "Browse health conditions and their dietary guidance — which bioactive compounds to avoid or limit, and the foods that contain them."
       )
     )}
  end

  # Base path for condition links. Under the nutritionist panel the whole workflow
  # stays within `/nutritionist/conditions`; on the public site it is the
  # locale-prefixed `/:locale/conditions`.
  defp conditions_base(%{"nav_section" => "nutritionist"}, _language),
    do: "/nutritionist/conditions"

  defp conditions_base(_session, language), do: "/#{language}/conditions"
end
