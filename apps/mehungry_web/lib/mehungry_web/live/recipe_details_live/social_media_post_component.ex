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
    changeset =
      changeset = FacebookPost.change_facebook_post(socket.assigns.post, pages_params)

    #form = to_form(changeset)

    socket =
      socket
      |> assign(:changeset, changeset)

    {:noreply, socket}
  end

  @impl true
  def handle_event("post", params, socket) do
    Task.start(fn ->
      pages = String.split(params[:pages], ",")
      pages = Enum.map(pages, fn x -> Map.get(socket.assigns.user.facebook_token, x, nil) end)

      recipe = socket.assigns.recipe
      user = Accounts.get_user!(socket.assigns.user.id)

      pages =
        Enum.map(pages, fn x ->
          result = Facebook.post_recipe_container(user, recipe, x)

          case result do
            %HTTPoison.Response{status_code: status_code, body: body} ->
              {x["name"], status_code, body}
          end
        end)

      pages
      notify_parent(self(), %{post_result: pages})
    end)

    # notify_parent(%{post: "asfdafsd"})

    {:noreply,
     socket
     |> assign(:state, :posting)}
  end

  @impl true
  def handle_event("post", params, socket) do
    IO.inspect(params, label: "Params")
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    case assigns.state do
      :result ->
        ~H"""
        <div class="p-4 m-auto w-fit">
          <%= for {name, code, result} <- assigns.results do %>
            <div>
              <span class="text-base  font-semibold px-2"><%= name %></span>
              <%= if is_nil(result) do %>
                <span
                  class="inline-block bg-primary rounded-full"
                  style="min-width: 15px; min-height: 15px;"
                >
                </span>
              <% else %>
                <span><%= result %> (<span class="font-semibold"> <%= code %> </span>)</span>
              <% end %>
            </div>
          <% end %>
        </div>
        """

      :posting ->
        SvgComponents.get_loading(assigns)

      :normal ->
          ~H"""
          <div class="relative h-full" style="min-height: 55vh;">
          <h3 class="w-fit m-auto">Share on Facebook</h3>
          <%= case Enum.empty?(assigns.user.facebook_token) do %>
            <% true -> %>
              <div>Not Connected on Facebook</div>
            <% false -> %>
              <div class="text-base font-semibold">Select pages</div>
              <.form
                :let={form}
                for={@changeset}
                phx-change="validate"
                phx-submit="post"
                phx-target={@myself}
                phx-change="validate"
              >
                <.live_component
                  module={MehungryWeb.SelectComponent}
                  items={
                    Enum.map(Map.keys(assigns.user.facebook_token), fn x ->
                      {x, x}
                    end)
                }

                form={form}
                mode={:multi}
                id={@recipe.id}
                input_variable={:pages}
                />
                <button type="submit" class="primary_button absolute bottom-0 right-0">Post</button>
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
