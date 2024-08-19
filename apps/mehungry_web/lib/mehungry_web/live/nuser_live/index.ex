defmodule MehungryWeb.NuserLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.NewsLetter
  alias Mehungry.NewsLetter.Nuser

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :nusers, NewsLetter.list_nusers())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Nuser")
    |> assign(:nuser, NewsLetter.get_nuser!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Nuser")
    |> assign(:nuser, %Nuser{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Nusers")
    |> assign(:nuser, nil)
  end

  @impl true
  def handle_info({MehungryWeb.NuserLive.FormComponent, {:saved, nuser}}, socket) do
    {:noreply, stream_insert(socket, :nusers, nuser)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    nuser = NewsLetter.get_nuser!(id)
    {:ok, _} = NewsLetter.delete_nuser(nuser)

    {:noreply, stream_delete(socket, :nusers, nuser)}
  end
end
