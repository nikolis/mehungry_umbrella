defmodule MehungryWeb.ProfessionalLive.LanguageLive.FormComponent do
  use MehungryWeb, :live_component

  alias Mehungry.Languages

  @impl true
  def update(%{language: language} = assigns, socket) do
    changeset = Languages.change_language(language, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("save", %{"language" => params}, socket) do
    save_language(socket, socket.assigns.action, params)
  end

  defp save_language(socket, :edit, params) do
    case Languages.update_language(socket.assigns.language, params) do
      {:ok, language} ->
        notify_parent({:saved, language})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_language(socket, :new, params) do
    case Languages.create_language(params) do
      {:ok, language} ->
        notify_parent({:saved, language})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
