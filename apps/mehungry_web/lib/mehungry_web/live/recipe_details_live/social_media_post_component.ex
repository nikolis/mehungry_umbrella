defmodule MehungryWeb.SocialMediaPostComponent do
  @moduledoc """
    This component is ment to facilitate the Social Media Posts Integration 
  """
  use MehungryWeb, :live_component

  alias Mehungry.Accounts
  alias Mehungry.Api.Facebook
  alias MehungryWeb.SvgComponents

  import MehungryWeb.CoreComponents
  import MehungryWeb.RecipeComponents

  defmodule FacebookPost do
    defstruct [:pages]
    @types %{pages: :string}

    def change_facebook_post(data, params) do
      Ecto.Changeset.cast({data, @types}, params, Map.keys(@types))
    end
  end

  @impl true
  def update(assigns, socket) do
    changeset = FacebookPost.change_facebook_post(%FacebookPost{}, %{})

    socket =
      socket
      |> assign(assigns)
      |> assign(:changeset, changeset)
      |> assign(:post, %FacebookPost{})
      |> assign(:state, Map.get(assigns, :state, :normal))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", pages_params, socket) do
    inner = pages_params["facebook_post"] || %{}
    changeset = FacebookPost.change_facebook_post(socket.assigns.post, inner)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_event("close", _, socket) do
    notify_parent(self(), :close)
    {:noreply, socket}
  end

  @impl true
  def handle_event("post", params, socket) do
    parent = self()

    Task.start(fn ->
      pages_str = get_in(params, ["facebook_post", "pages"]) || ""
      pages = String.split(pages_str, ",", trim: true)
      pages = Enum.map(pages, fn x -> Map.get(socket.assigns.user.facebook_token, x, nil) end)

      recipe = socket.assigns.recipe
      user = Accounts.get_user!(socket.assigns.user.id)

      pages =
        Enum.map(pages, fn x ->
          result = Facebook.post_recipe_container(user, recipe, x)

          case result do
            {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
              {x["name"], status_code, body}

            {:error, %HTTPoison.Error{reason: reason}} ->
              {x["name"], 0, Jason.encode!(%{"error" => %{"message" => inspect(reason)}})}
          end
        end)

      notify_parent(parent, %{post_result: pages})
    end)

    {:noreply, assign(socket, :state, :posting)}
  end

  @impl true
  def render(assigns) do
    case assigns.state do
      :result ->
        ~H"""
        <div class="space-y-5">
          <div class="flex items-center gap-3 pb-4 border-b border-slate-700">
            <h3 class="text-lg font-semibold text-white">Post Results</h3>
          </div>
          <div class="space-y-3">
            <%= for {name, code, result} <- @results do %>
              <div class="flex items-start gap-3 p-3 rounded-lg bg-slate-700/50">
                <%= if is_nil(result) or (is_integer(code) and code >= 200 and code < 300) do %>
                  <div class="w-7 h-7 rounded-full bg-green-500/20 flex items-center justify-center flex-shrink-0 mt-0.5">
                    <.icon name="hero-check" class="h-4 w-4 text-green-400" />
                  </div>
                  <div>
                    <p class="text-sm font-semibold text-white">{name}</p>
                    <p class="text-xs text-slate-400">Posted successfully</p>
                  </div>
                <% else %>
                  <div class="w-7 h-7 rounded-full bg-red-500/20 flex items-center justify-center flex-shrink-0 mt-0.5">
                    <.icon name="hero-x-mark" class="h-4 w-4 text-red-400" />
                  </div>
                  <div>
                    <p class="text-sm font-semibold text-white">{name}</p>
                    <p class="text-xs text-red-400">{result}</p>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
          <div class="flex justify-end pt-2">
            <button
              phx-click="close"
              phx-target={@myself}
              class="px-5 py-2 rounded-lg bg-slate-700 hover:bg-slate-600 text-white font-semibold transition-colors"
            >
              Done
            </button>
          </div>
        </div>
        """

      :posting ->
        ~H"""
        <div class="flex flex-col items-center justify-center gap-4 py-10">
          {SvgComponents.get_loading(assigns)}
          <p class="text-slate-400 text-sm">Posting to Facebook…</p>
        </div>
        """

      :normal ->
        ~H"""
        <div class="space-y-5">
          <div class="flex items-center gap-3 pb-4 border-b border-slate-700">
            <div class="w-10 h-10 rounded-full bg-blue-600 flex items-center justify-center flex-shrink-0">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="white" class="w-5 h-5">
                <path d="M22 12c0-5.523-4.477-10-10-10S2 6.477 2 12c0 4.991 3.657 9.128 8.438 9.878V14.89h-2.54V12h2.54V9.797c0-2.506 1.492-3.89 3.777-3.89 1.094 0 2.238.195 2.238.195v2.46h-1.26c-1.243 0-1.63.771-1.63 1.562V12h2.773l-.443 2.89h-2.33v6.988C18.343 21.128 22 16.991 22 12z" />
              </svg>
            </div>
            <div>
              <h3 class="text-lg font-semibold text-white">Share on Facebook</h3>
              <p class="text-sm text-slate-400">Post this recipe to your Facebook pages</p>
            </div>
          </div>
          <%= case Enum.empty?(@user.facebook_token) do %>
            <% true -> %>
              <div class="flex items-center gap-3 p-4 rounded-lg bg-slate-700/50">
                <.icon name="hero-exclamation-circle" class="h-5 w-5 text-slate-400 flex-shrink-0" />
                <p class="text-sm text-slate-400">
                  No Facebook pages connected. Connect your account in settings.
                </p>
              </div>
            <% false -> %>
              <.form
                :let={form}
                for={@changeset}
                phx-change="validate"
                phx-submit="post"
                phx-target={@myself}
              >
                <div class="space-y-2 mb-6">
                  <label class="text-sm font-medium text-slate-300">Select pages to post to</label>
                  <.live_component
                    module={MehungryWeb.SelectComponent}
                    items={Enum.map(Map.keys(@user.facebook_token), fn x -> {x, x} end)}
                    form={form}
                    mode={:multi}
                    id={@recipe.id}
                    input_variable={:pages}
                  />
                </div>
                <div class="flex justify-end">
                  <button
                    type="submit"
                    class="flex items-center gap-2 bg-blue-600 hover:bg-blue-500 text-white px-5 py-2 rounded-lg font-semibold transition-colors"
                  >
                    <.icon name="hero-paper-airplane" class="h-4 w-4" /> Post
                  </button>
                </div>
              </.form>
          <% end %>
        </div>
        """
    end
  end

  defp notify_parent(self, msg) do
    send(self, {MehungryWeb.SocialMediaPostComponent, msg})
  end
end
