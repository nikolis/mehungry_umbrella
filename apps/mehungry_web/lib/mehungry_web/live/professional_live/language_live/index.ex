defmodule MehungryWeb.Professional.LanguageLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.Languages
  alias Mehungry.Languages.Language

  @impl true
  def mount(_params, _session, socket) do
    languages = Languages.list_languages()

    {:ok,
     stream_configure(socket, :languages, dom_id: & &1.name)
     |> stream(:languages, languages)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Language")
    |> assign(:language, Languages.get_language!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Language")
    |> assign(:language, %Language{})
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :language, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => name}, socket) do
    language = Languages.get_language!(name)

    case Languages.delete_language(language) do
      {:ok, _} ->
        {:noreply,
         socket
         |> stream_delete(:languages, language)
         |> put_flash(:info, "Language deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Cannot delete language — it may be in use.")}
    end
  end

  @impl true
  def handle_info({MehungryWeb.LanguageLive.FormComponent, {:saved, language}}, socket) do
    {:noreply, stream_insert(socket, :languages, language)}
  end
end
