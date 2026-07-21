defmodule MehungryWeb.SocialMediaPostComponent do
  @moduledoc """
    This component is ment to facilitate the Social Media Posts Integration 
  """
  use MehungryWeb, :live_component

  alias Mehungry.Accounts
  alias Mehungry.Social.Facebook
  alias Mehungry.Social.Pinterest
  alias MehungryWeb.SvgComponents

  import MehungryWeb.CoreComponents

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

    {pinterest_boards, pinterest_boards_error} =
      if Map.get(assigns, :social_media) == "pinterest" do
        user = Map.get(assigns, :user)
        if user, do: fetch_boards(user), else: {[], nil}
      else
        {[], nil}
      end

    socket =
      socket
      |> assign(assigns)
      |> assign(:changeset, changeset)
      |> assign(:post, %FacebookPost{})
      |> assign(:state, Map.get(assigns, :state, :normal))
      |> assign(:pinterest_boards, pinterest_boards)
      |> assign(:pinterest_boards_error, pinterest_boards_error)
      |> assign(:pinterest_board_id, nil)
      |> assign(:show_create_board, false)
      |> assign(:create_board_error, nil)

    {:ok, socket}
  end

  # Distinguishes an API/auth failure (surface "reconnect") from a genuinely
  # empty board list (surface "create your first board").
  defp fetch_boards(user) do
    case Pinterest.get_boards(user) do
      {:ok, boards} -> {boards, nil}
      {:error, :not_connected} -> {[], nil}
      {:error, _reason} -> {[], :fetch_failed}
    end
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
          case Facebook.post_recipe_container(user, recipe, x) do
            {:ok, _response} ->
              {x["name"], 200, nil}

            {:error, {:http_error, status, body}} ->
              {x["name"], status, body}

            {:error, reason} ->
              {x["name"], 0, Jason.encode!(%{"error" => %{"message" => inspect(reason)}})}
          end
        end)

      notify_parent(parent, %{post_result: pages})
    end)

    {:noreply, assign(socket, :state, :posting)}
  end

  @impl true
  def handle_event("select_pinterest_board", %{"board_id" => board_id}, socket) do
    {:noreply, assign(socket, :pinterest_board_id, board_id)}
  end

  @impl true
  def handle_event("toggle_create_board", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create_board, !socket.assigns.show_create_board)
     |> assign(:create_board_error, nil)}
  end

  @impl true
  def handle_event("create_pinterest_board", %{"board" => board_params}, socket) do
    user = Accounts.get_user!(socket.assigns.user.id)

    case Pinterest.create_board(user, board_params) do
      {:ok, board} ->
        {boards, boards_error} = fetch_boards(user)

        {:noreply,
         socket
         |> assign(:pinterest_boards, boards)
         |> assign(:pinterest_boards_error, boards_error)
         |> assign(:pinterest_board_id, board["id"])
         |> assign(:show_create_board, false)
         |> assign(:create_board_error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :create_board_error, reason)}
    end
  end

  @impl true
  def handle_event("post_pinterest", _params, socket) do
    board_id = socket.assigns.pinterest_board_id

    if is_nil(board_id) do
      {:noreply, socket}
    else
      parent = self()

      Task.start(fn ->
        user = Accounts.get_user!(socket.assigns.user.id)
        recipe = socket.assigns.recipe

        result =
          case Pinterest.create_pin(user, recipe, board_id) do
            {:ok, _pin} ->
              [{"Pinterest", 200, nil}]

            {:error, reason} ->
              [{"Pinterest", 0, Jason.encode!(%{"error" => %{"message" => reason}})}]
          end

        notify_parent(parent, %{post_result: result})
      end)

      {:noreply, assign(socket, :state, :posting)}
    end
  end

  @impl true
  def handle_event("post_instagram", _params, socket) do
    parent = self()

    Task.start(fn ->
      recipe = socket.assigns.recipe
      user = Accounts.get_user!(socket.assigns.user.id)

      result =
        case Mehungry.Social.Instagram.post_recipe(user, recipe) do
          {:ok, %{media_id: _}} ->
            [{"Instagram", 200, nil}]

          {:error, {:http_error, status, body}} ->
            [{"Instagram", status, Jason.encode!(%{"error" => %{"message" => inspect(body)}})}]

          {:error, reason} ->
            [{"Instagram", 0, Jason.encode!(%{"error" => %{"message" => inspect(reason)}})}]
        end

      notify_parent(parent, %{post_result: result})
    end)

    {:noreply, assign(socket, :state, :posting)}
  end

  @impl true
  def render(assigns) do
    case assigns.state do
      :result ->
        ~H"""
        <div class="space-y-5">
          <div class="flex items-center gap-3 pb-4 border-b border-ink-panel2">
            <h3 class="text-lg font-display font-medium text-parchment">Post Results</h3>
          </div>
          <div class="space-y-3">
            <%= for {name, code, result} <- @results do %>
              <div class="flex items-start gap-3 p-3 rounded-lg border border-ink-panel2 bg-black/20">
                <%= if is_nil(result) or (is_integer(code) and code >= 200 and code < 300) do %>
                  <div class="w-7 h-7 rounded-full bg-green-500/20 flex items-center justify-center flex-shrink-0 mt-0.5">
                    <.icon name="hero-check" class="h-4 w-4 text-green-400" />
                  </div>
                  <div>
                    <p class="text-sm font-semibold text-parchment">{name}</p>
                    <p class="text-xs text-parchment-dim">Posted successfully</p>
                  </div>
                <% else %>
                  <div class="w-7 h-7 rounded-full bg-red-500/20 flex items-center justify-center flex-shrink-0 mt-0.5">
                    <.icon name="hero-x-mark" class="h-4 w-4 text-red-400" />
                  </div>
                  <div>
                    <p class="text-sm font-semibold text-parchment">{name}</p>
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
              class="px-5 py-2 rounded-lg text-parchment-dim hover:text-parchment font-semibold transition-colors"
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
          <p class="text-parchment-dim text-sm">Posting…</p>
        </div>
        """

      :normal ->
        case assigns.social_media do
          "pinterest" ->
            ~H"""
            <div class="space-y-5">
              <div class="flex items-center gap-3 pb-4 border-b border-ink-panel2">
                <div class="w-10 h-10 rounded-xl bg-red-600 flex items-center justify-center flex-shrink-0">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="white" class="w-6 h-6">
                    <path d="M12 0C5.373 0 0 5.373 0 12c0 5.084 3.163 9.426 7.627 11.174-.105-.949-.2-2.405.042-3.441.218-.937 1.407-5.965 1.407-5.965s-.359-.719-.359-1.782c0-1.668.967-2.914 2.171-2.914 1.023 0 1.518.769 1.518 1.69 0 1.029-.655 2.568-.994 3.995-.283 1.194.599 2.169 1.777 2.169 2.133 0 3.772-2.249 3.772-5.495 0-2.873-2.064-4.882-5.012-4.882-3.414 0-5.418 2.561-5.418 5.207 0 1.031.397 2.138.893 2.738a.36.36 0 0 1 .083.345l-.333 1.36c-.053.22-.174.267-.402.161-1.499-.698-2.436-2.889-2.436-4.649 0-3.785 2.75-7.262 7.929-7.262 4.163 0 7.398 2.967 7.398 6.931 0 4.136-2.607 7.464-6.227 7.464-1.216 0-2.359-.632-2.75-1.378l-.748 2.853c-.271 1.043-1.002 2.35-1.492 3.146C9.57 23.812 10.763 24 12 24c6.627 0 12-5.373 12-12S18.627 0 12 0z" />
                  </svg>
                </div>
                <div>
                  <h3 class="text-lg font-display font-medium text-parchment">Pin to Pinterest</h3>
                  <p class="text-sm text-parchment-dim">Save this recipe to one of your boards</p>
                </div>
              </div>
              <%= if is_nil(@user.pinterest_token) or map_size(@user.pinterest_token) == 0 do %>
                <div class="flex items-center gap-3 p-4 rounded-lg border border-ink-panel2 bg-black/20">
                  <.icon name="hero-exclamation-circle" class="h-5 w-5 text-parchment-dim flex-shrink-0" />
                  <p class="text-sm text-parchment-dim">
                    No Pinterest account connected.
                    <.link navigate={~p"/profile?#{[tab: "connected_accounts"]}"} class="text-paprika-soft hover:text-paprika underline">Connect it in your profile settings.</.link>
                  </p>
                </div>
              <% else %>
                <%= if @pinterest_boards_error do %>
                  <div class="flex items-center gap-3 p-4 rounded-lg border border-ink-panel2 bg-black/20">
                    <.icon name="hero-exclamation-circle" class="h-5 w-5 text-amber-400 flex-shrink-0" />
                    <p class="text-sm text-parchment-dim">
                      Could not load your Pinterest boards — the connection is likely expired.
                      <.link navigate={~p"/profile?#{[tab: "connected_accounts"]}"} class="text-paprika-soft hover:text-paprika underline">Reconnect it in your profile settings.</.link>
                    </p>
                  </div>
                <% else %>
                <%= if @pinterest_boards == [] do %>
                  <div class="space-y-3">
                    <div class="flex items-center gap-3 p-4 rounded-lg border border-ink-panel2 bg-black/20">
                      <.icon name="hero-exclamation-circle" class="h-5 w-5 text-parchment-dim flex-shrink-0" />
                      <p class="text-sm text-parchment-dim">
                        No Pinterest boards found. Create your first board below.
                      </p>
                    </div>
                    <.create_board_form myself={@myself} error={@create_board_error} />
                  </div>
                <% else %>
                  <div class="space-y-3">
                    <p class="text-sm text-parchment-dim">
                      Pinning <span class="font-semibold text-parchment">{@recipe.title}</span> — choose a board:
                    </p>
                    <div class="grid gap-2 max-h-48 overflow-y-auto pr-1">
                      <%= for board <- @pinterest_boards do %>
                        <button
                          phx-click="select_pinterest_board"
                          phx-value-board_id={board["id"]}
                          phx-target={@myself}
                          class={[
                            "w-full text-left px-4 py-3 rounded-lg border text-sm transition",
                            if(@pinterest_board_id == board["id"],
                              do: "bg-paprika/20 border-paprika text-parchment",
                              else: "border-ink-panel2 bg-black/20 text-parchment-dim hover:border-parchment-dim"
                            )
                          ]}
                        >
                          {board["name"]}
                        </button>
                      <% end %>
                    </div>
                    <button
                      phx-click="toggle_create_board"
                      phx-target={@myself}
                      class="flex items-center gap-1.5 text-sm text-parchment-dim hover:text-parchment transition-colors"
                    >
                      <.icon name="hero-plus" class="h-4 w-4" /> New board
                    </button>
                    <%= if @show_create_board do %>
                      <.create_board_form myself={@myself} error={@create_board_error} />
                    <% end %>
                    <div class="flex justify-end pt-2">
                      <button
                        phx-click="post_pinterest"
                        phx-target={@myself}
                        disabled={is_nil(@pinterest_board_id)}
                        class={[
                          "flex items-center gap-2 px-5 py-2 rounded-lg font-bold transition-colors",
                          if(is_nil(@pinterest_board_id),
                            do: "bg-ink-panel2 text-parchment-dim cursor-not-allowed",
                            else: "bg-paprika hover:bg-paprika-soft text-ink"
                          )
                        ]}
                      >
                        <.icon name="hero-paper-airplane" class="h-4 w-4" /> Pin Recipe
                      </button>
                    </div>
                  </div>
                <% end %>
                <% end %>
              <% end %>
            </div>
            """

          "instagram" ->
            ~H"""
            <div class="space-y-5">
              <div class="flex items-center gap-3 pb-4 border-b border-ink-panel2">
                <div class="w-10 h-10 rounded-xl bg-gradient-to-br from-purple-500 via-pink-500 to-orange-400 flex items-center justify-center flex-shrink-0">
                  <img src="/images/instagram-svgrepo-com.svg" class="w-6 h-6 brightness-0 invert" />
                </div>
                <div>
                  <h3 class="text-lg font-display font-medium text-parchment">Share on Instagram</h3>
                  <p class="text-sm text-parchment-dim">Post this recipe to your Instagram account</p>
                </div>
              </div>
              <%= if is_nil(@user.instagram_token) or map_size(@user.instagram_token) == 0 do %>
                <div class="flex items-center gap-3 p-4 rounded-lg border border-ink-panel2 bg-black/20">
                  <.icon name="hero-exclamation-circle" class="h-5 w-5 text-parchment-dim flex-shrink-0" />
                  <p class="text-sm text-parchment-dim">
                    No Instagram account connected.
                    <.link navigate={~p"/profile?#{[tab: "connected_accounts"]}"} class="text-paprika-soft hover:text-paprika underline">Connect it in your profile settings.</.link>
                  </p>
                </div>
              <% else %>
                <div class="p-4 rounded-lg border border-ink-panel2 bg-black/20 text-sm text-parchment-dim">
                  This will post <span class="font-semibold text-parchment">{@recipe.title}</span>
                  as an image with the recipe caption to your connected Instagram account.
                </div>
                <div class="flex justify-end">
                  <button
                    phx-click="post_instagram"
                    phx-target={@myself}
                    class="flex items-center gap-2 bg-paprika hover:bg-paprika-soft text-ink px-5 py-2 rounded-lg font-bold transition-colors"
                  >
                    <.icon name="hero-paper-airplane" class="h-4 w-4" /> Post to Instagram
                  </button>
                </div>
              <% end %>
            </div>
            """

          _ ->
            ~H"""
            <div class="space-y-5 recipe-details-page">
              <div class="flex items-center gap-3 pb-4 border-b border-ink-panel2">
                <div class="w-10 h-10 rounded-full bg-blue-600 flex items-center justify-center flex-shrink-0">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="white" class="w-5 h-5">
                    <path d="M22 12c0-5.523-4.477-10-10-10S2 6.477 2 12c0 4.991 3.657 9.128 8.438 9.878V14.89h-2.54V12h2.54V9.797c0-2.506 1.492-3.89 3.777-3.89 1.094 0 2.238.195 2.238.195v2.46h-1.26c-1.243 0-1.63.771-1.63 1.562V12h2.773l-.443 2.89h-2.33v6.988C18.343 21.128 22 16.991 22 12z" />
                  </svg>
                </div>
                <div>
                  <h3 class="text-lg font-display font-medium text-parchment">Share on Facebook</h3>
                  <p class="text-sm text-parchment-dim">Post this recipe to your Facebook pages</p>
                </div>
              </div>
              <%= case Enum.empty?(@user.facebook_token) do %>
                <% true -> %>
                  <div class="flex items-center gap-3 p-4 rounded-lg border border-ink-panel2 bg-black/20">
                    <.icon name="hero-exclamation-circle" class="h-5 w-5 text-parchment-dim flex-shrink-0" />
                    <p class="text-sm text-parchment-dim">
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
                      <label class="text-sm font-medium text-parchment-dim">Select pages to post to</label>
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
                        class="flex items-center gap-2 bg-paprika hover:bg-paprika-soft text-ink px-5 py-2 rounded-lg font-bold transition-colors"
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
  end

  attr :myself, :any, required: true
  attr :error, :string, default: nil

  defp create_board_form(assigns) do
    ~H"""
    <form
      phx-submit="create_pinterest_board"
      phx-target={@myself}
      class="space-y-3 p-4 rounded-lg bg-black/20 border border-ink-panel2"
    >
      <p class="text-sm font-semibold text-parchment">Create a new board</p>
      <input
        type="text"
        name="board[name]"
        required
        maxlength="180"
        placeholder="Board name"
        class="w-full bg-ink-panel2 border border-ink-panel2 rounded-lg text-parchment text-sm px-3 py-2 placeholder-parchment-dim focus:border-paprika focus:outline-none"
      />
      <textarea
        name="board[description]"
        rows="2"
        maxlength="500"
        placeholder="Description (optional)"
        class="w-full bg-ink-panel2 border border-ink-panel2 rounded-lg text-parchment text-sm px-3 py-2 placeholder-parchment-dim focus:border-paprika focus:outline-none"
      ></textarea>
      <select
        name="board[privacy]"
        class="w-full bg-ink-panel2 border border-ink-panel2 rounded-lg text-parchment text-sm px-3 py-2 focus:border-paprika focus:outline-none"
      >
        <option value="PUBLIC">Public</option>
        <option value="SECRET">Secret</option>
      </select>
      <%= if @error do %>
        <p class="text-xs text-red-400">{@error}</p>
      <% end %>
      <div class="flex justify-end">
        <button
          type="submit"
          class="flex items-center gap-2 px-4 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink text-sm font-bold transition-colors"
        >
          <.icon name="hero-plus" class="h-4 w-4" /> Create Board
        </button>
      </div>
    </form>
    """
  end

  defp notify_parent(self, msg) do
    send(self, {MehungryWeb.SocialMediaPostComponent, msg})
  end
end
