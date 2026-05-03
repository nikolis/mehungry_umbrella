defmodule MehungryWeb.ProfessionalLive.LanguageLive.Show do
  use MehungryWeb, :live_view

  alias Mehungry.Languages

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:language, Languages.get_language!(id))
     |> assign(:page_title, "Show Language")}
  end
end
