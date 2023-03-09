defmodule MehungryWeb.BedelLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.Tobedel
  alias Mehungry.Tobedel.Bedel

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :bedels, list_bedels())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Bedel")
    |> assign(:bedel, Tobedel.get_bedel!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Bedel")
    |> assign(:bedel, %Bedel{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Bedels")
    |> assign(:bedel, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    bedel = Tobedel.get_bedel!(id)
    {:ok, _} = Tobedel.delete_bedel(bedel)

    {:noreply, assign(socket, :bedels, list_bedels())}
  end

  defp list_bedels do
    Tobedel.list_bedels()
  end
end
