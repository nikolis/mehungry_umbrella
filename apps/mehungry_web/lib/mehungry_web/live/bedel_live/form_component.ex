defmodule MehungryWeb.BedelLive.FormComponent do
  use MehungryWeb, :live_component

  alias Mehungry.Tobedel

  @impl true
  def update(%{bedel: bedel} = assigns, socket) do
    changeset = Tobedel.change_bedel(bedel)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"bedel" => bedel_params}, socket) do
    changeset =
      socket.assigns.bedel
      |> Tobedel.change_bedel(bedel_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"bedel" => bedel_params}, socket) do
    save_bedel(socket, socket.assigns.action, bedel_params)
  end

  defp save_bedel(socket, :edit, bedel_params) do
    case Tobedel.update_bedel(socket.assigns.bedel, bedel_params) do
      {:ok, _bedel} ->
        {:noreply,
         socket
         |> put_flash(:info, "Bedel updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_bedel(socket, :new, bedel_params) do
    case Tobedel.create_bedel(bedel_params) do
      {:ok, _bedel} ->
        {:noreply,
         socket
         |> put_flash(:info, "Bedel created successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end
end
