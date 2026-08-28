defmodule MehungryWeb.NutritionistLive.Articles do
  @moduledoc """
  The nutritionist's article list: every article they've authored (draft +
  published) with quick actions, plus a "New article" button that creates a blank
  draft and drops the author straight into the editor.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Professionals

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    profile = Professionals.get_professional_profile(user.id)

    {:ok,
     socket
     |> assign(:page_title, "My Articles")
     |> assign(:profile, profile)
     |> assign(:articles, list_articles(profile))}
  end

  @impl true
  def handle_event("new_article", _params, %{assigns: %{profile: nil}} = socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Set up your professional profile before writing articles.")
     |> push_navigate(to: ~p"/nutritionist/profile")}
  end

  @impl true
  def handle_event("new_article", _params, socket) do
    case Professionals.create_article(%{
           "professional_profile_id" => socket.assigns.profile.id,
           "title" => "Untitled article"
         }) do
      {:ok, article} ->
        {:noreply, push_navigate(socket, to: ~p"/nutritionist/articles/#{article.id}/edit")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not create the article.")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    article = Professionals.get_article!(id)

    if article.professional_profile_id == socket.assigns.profile.id do
      {:ok, _} = Professionals.delete_article(article)

      {:noreply,
       socket
       |> put_flash(:info, "Article deleted.")
       |> assign(:articles, list_articles(socket.assigns.profile))}
    else
      {:noreply, socket}
    end
  end

  defp list_articles(nil), do: []
  defp list_articles(profile), do: Professionals.list_articles_for_profile(profile.id)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto pb-16">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-display font-bold text-parchment">My Articles</h1>
        <button
          phx-click="new_article"
          class="px-4 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-semibold text-sm transition"
        >
          + New article
        </button>
      </div>

      <p :if={@profile == nil} class="text-parchment-dim">
        You need a professional profile first.
        <.link navigate={~p"/nutritionist/profile"} class="text-paprika hover:text-paprika-soft">
          Set it up →
        </.link>
      </p>

      <div :if={@articles == []} class="text-parchment-dim text-center py-16">
        No articles yet. Write your first evidence-based article for your public profile.
      </div>

      <ul class="space-y-3">
        <li
          :for={article <- @articles}
          class="bg-ink-panel border border-ink-panel2 rounded-xl p-4 flex items-center justify-between gap-4"
        >
          <div class="min-w-0">
            <div class="flex items-center gap-2">
              <span class="font-semibold text-parchment truncate">{article.title}</span>
              <span class={[
                "text-xs px-2 py-0.5 rounded-full",
                article.status == "published" && "bg-basil/20 text-basil",
                article.status == "draft" && "bg-ink-panel2 text-parchment-dim"
              ]}>
                {article.status}
              </span>
            </div>
            <p :if={article.summary} class="text-parchment-dim text-sm truncate mt-1">
              {article.summary}
            </p>
          </div>

          <div class="flex items-center gap-3 shrink-0">
            <a
              :if={article.status == "published" && @profile && @profile.slug}
              href={~p"/nutritionists/#{@profile.slug}/articles/#{article.slug}"}
              target="_blank"
              class="text-sm text-parchment-dim hover:text-parchment"
            >
              View →
            </a>
            <.link
              navigate={~p"/nutritionist/articles/#{article.id}/edit"}
              class="text-sm text-paprika hover:text-paprika-soft"
            >
              Edit
            </.link>
            <button
              phx-click="delete"
              phx-value-id={article.id}
              data-confirm="Delete this article? This cannot be undone."
              class="text-sm text-parchment-dim hover:text-red-400"
            >
              Delete
            </button>
          </div>
        </li>
      </ul>
    </div>
    """
  end
end
