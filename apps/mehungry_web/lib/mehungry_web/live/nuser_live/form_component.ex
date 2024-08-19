defmodule MehungryWeb.NuserLive.FormComponent do
  use MehungryWeb, :live_component

  alias Mehungry.NewsLetter

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage nuser records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="nuser-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:email]} type="text" label="Email" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Nuser</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{nuser: nuser} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(NewsLetter.change_nuser(nuser))
     end)}
  end

  @impl true
  def handle_event("validate", %{"nuser" => nuser_params}, socket) do
    changeset = NewsLetter.change_nuser(socket.assigns.nuser, nuser_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"nuser" => nuser_params}, socket) do
    save_nuser(socket, socket.assigns.action, nuser_params)
  end

  defp save_nuser(socket, :edit, nuser_params) do
    case NewsLetter.update_nuser(socket.assigns.nuser, nuser_params) do
      {:ok, nuser} ->
        notify_parent({:saved, nuser})

        {:noreply,
         socket
         |> put_flash(:info, "Nuser updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_nuser(socket, :new, nuser_params) do
    case NewsLetter.create_nuser(nuser_params) do
      {:ok, nuser} ->
        notify_parent({:saved, nuser})

        {:noreply,
         socket
         |> put_flash(:info, "Nuser created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
