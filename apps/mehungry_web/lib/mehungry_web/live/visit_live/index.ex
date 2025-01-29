defmodule MehungryWeb.VisitLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.Meta
  # alias Mehungry.Meta.Visit

  @impl true
  def mount(_params, _session, socket) do
    visits =
      Meta.list_visits()

    # |> Enum.uniq_by(fn x -> x.ip_address end)
    # |> Enum.uniq_by(fn x -> {x.details["path"], x.ip_address, x.inserted_at} end)

    {:ok, stream(socket, :visits, visits)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Visits")
    |> assign(:visit, nil)
  end

  @impl true
  def handle_info({MehungryWeb.VisitLive.FormComponent, {:saved, visit}}, socket) do
    {:noreply, stream_insert(socket, :visits, visit)}
  end

  @impl true
  def handle_event("delete_all", _, socket) do
    Meta.delete_all_visits()
    socket = stream(socket, :visits, [], reset: true)
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    visit = Meta.get_visit!(id)
    {:ok, _} = Meta.delete_visit(visit)

    {:noreply, stream_delete(socket, :visits, visit)}
  end
end
