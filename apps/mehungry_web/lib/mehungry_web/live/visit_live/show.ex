defmodule MehungryWeb.VisitLive.Show do
  use MehungryWeb, :live_view

  alias Mehungry.Meta

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"ip_address" => id}, _, socket) do
    visits =
      Meta.list_visits(id)
      |> Enum.uniq_by(fn x -> {x.details["path"], x.ip_address, x.inserted_at} end)

    visits2 = Enum.chunk_by(visits, fn x -> x.inserted_at.day end)
    visit = Enum.at(visits, 0, nil)

    {:noreply,
     socket
     |> assign(:visit, visit)
     |> assign(:visits2, visits2)
     |> stream(:visits, visits)
     |> assign(:ip_address, id)}
  end

  def remove_hostname(url) do
    url = String.replace(url, MehungryWeb.Endpoint.url() <> "/", "")

    case url do
      "" ->
        "Home"

      anyth ->
        anyth
    end
  end

  @impl true
  def handle_event("delete_all", _, socket) do
    Meta.delete_all_visits(socket.assigns.ip_address)
    socket = stream(socket, :visits, [], reset: true)
    {:noreply, socket}
  end
end
