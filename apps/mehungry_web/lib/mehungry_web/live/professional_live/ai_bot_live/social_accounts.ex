defmodule MehungryWeb.AiBotLive.SocialAccounts do
  use MehungryWeb, :live_view
  import MehungryWeb.FormatHelpers, only: [month_name: 1]

  alias Mehungry.{AiBot, Accounts, Languages}
  alias Mehungry.Api.Pinterest

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    config = AiBot.get_active_config_for_month(today.month, today.year)
    languages = Languages.list_languages()

    if config do
      bot_user = Accounts.get_user!(config.bot_user_id)
      {boards, boards_error} = fetch_boards(bot_user)

      {:ok,
       socket
       |> assign(:config, config)
       |> assign(:bot_user, bot_user)
       |> assign(:languages, languages)
       |> assign(:pinterest_boards, boards)
       |> assign(:pinterest_boards_error, boards_error)
       |> assign(:show_create_board, false)
       |> assign(:page_title, "Bot Social Accounts")}
    else
      {:ok,
       socket
       |> assign(:config, nil)
       |> assign(:bot_user, nil)
       |> assign(:languages, languages)
       |> assign(:pinterest_boards, [])
       |> assign(:pinterest_boards_error, nil)
       |> assign(:show_create_board, false)
       |> assign(:page_title, "Bot Social Accounts")}
    end
  end

  # Distinguishes an API/auth failure (surface "reconnect") from a genuinely
  # empty board list (surface "create your first board").
  defp fetch_boards(bot_user) do
    case Pinterest.get_boards(bot_user) do
      {:ok, boards} -> {boards, nil}
      {:error, :not_connected} -> {[], nil}
      {:error, _reason} -> {[], :fetch_failed}
    end
  end

  @impl true
  def handle_event("save_facebook_pages", %{"facebook_pages" => pages}, socket) do
    config = socket.assigns.config
    clean = Map.reject(pages, fn {_, v} -> v == "" end)

    case AiBot.update_bot_config(config, %{facebook_page_ids: clean}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:config, updated)
         |> put_flash(:info, "Facebook pages saved.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save Facebook pages.")}
    end
  end

  @impl true
  def handle_event("save_pinterest_boards", %{"pinterest_boards" => boards}, socket) do
    config = socket.assigns.config
    clean = Map.reject(boards, fn {_, v} -> v == "" end)

    case AiBot.update_bot_config(config, %{pinterest_board_ids: clean}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:config, updated)
         |> put_flash(:info, "Pinterest boards saved.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save Pinterest boards.")}
    end
  end

  @impl true
  def handle_event("toggle_create_board", _params, socket) do
    {:noreply, assign(socket, :show_create_board, !socket.assigns.show_create_board)}
  end

  @impl true
  def handle_event("create_pinterest_board", %{"board" => board_params}, socket) do
    bot_user = socket.assigns.bot_user

    case Pinterest.create_board(bot_user, board_params) do
      {:ok, board} ->
        {boards, boards_error} = fetch_boards(bot_user)

        {:noreply,
         socket
         |> assign(:pinterest_boards, boards)
         |> assign(:pinterest_boards_error, boards_error)
         |> assign(:show_create_board, false)
         |> put_flash(:info, "Pinterest board \"#{board["name"]}\" created.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create board: #{reason}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center gap-3 mb-6">
        <.link
          navigate={~p"/professional/ai-bot"}
          class="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition-colors"
        >
          <.icon name="hero-arrow-left" class="h-5 w-5" />
        </.link>
        <div>
          <h1 class="text-xl font-bold text-white">Bot Social Accounts</h1>
          <p class="text-sm text-slate-400 mt-0.5">
            Connection status and per-language publish targets
          </p>
        </div>
      </div>

      <%= if is_nil(@config) do %>
        <div class="bg-amber-500/10 border border-amber-500/30 rounded-xl px-4 py-3 text-amber-300 text-sm">
          No active bot configuration found for this month. <.link
            navigate={~p"/professional/ai-bot/new"}
            class="underline ml-1"
          >Create one</.link>.
        </div>
      <% else %>
        <div class="mb-5 bg-slate-800 border border-slate-700/60 rounded-xl px-4 py-3 text-sm text-slate-300">
          Configuring accounts for bot user:
          <strong class="text-white">{@bot_user.name || @bot_user.email}</strong>
          <span class="text-slate-500 ml-1">({@config.theme} · {month_name(@config.month)} {@config.year})</span>
        </div>

        <!-- Connection status cards -->
        <div class="grid grid-cols-3 gap-4 mb-8">
          <.platform_card
            name="Instagram"
            icon="📸"
            connected={Mehungry.Instagram.token_status(@bot_user) in [:connected, :expiring]}
            detail={instagram_detail(@bot_user)}
            connect_url={~p"/auth/bot/target/#{@bot_user.id}/instagram"}
          />
          <.platform_card
            name="Facebook"
            icon="📘"
            connected={map_non_empty?(@bot_user.facebook_token)}
            detail={facebook_detail(@bot_user)}
            connect_url={~p"/auth/bot/target/#{@bot_user.id}/facebook"}
          />
          <.platform_card
            name="Pinterest"
            icon="📌"
            connected={map_non_empty?(@bot_user.pinterest_token)}
            detail={
              cond do
                @pinterest_boards_error -> "Could not load boards — reconnect"
                @pinterest_boards != [] -> "#{length(@pinterest_boards)} board(s) available"
                true -> nil
              end
            }
            connect_url={~p"/auth/bot/target/#{@bot_user.id}/pinterest"}
          />
        </div>

        <!-- Facebook per-language page selector -->
        <%= if map_non_empty?(@bot_user.facebook_token) do %>
          <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-5 mb-5">
            <h2 class="text-sm font-semibold text-white mb-1">Facebook — Page per Language</h2>
            <p class="text-xs text-slate-500 mb-4">
              Choose which Facebook page to post to for each language. Leave blank to skip that language.
            </p>
            <form phx-submit="save_facebook_pages" class="space-y-3">
              <%= for lang <- @languages do %>
                <div class="flex items-center gap-3">
                  <span class="w-10 text-xs font-semibold text-slate-400 uppercase flex-shrink-0">
                    {lang.name}
                  </span>
                  <select
                    name={"facebook_pages[#{lang.name}]"}
                    class="flex-1 bg-slate-700 border border-slate-600 rounded-lg text-slate-200 text-sm px-3 py-2 focus:border-primary-500 focus:outline-none"
                  >
                    <option value="">— not set —</option>
                    <%= for {page_name, page} <- @bot_user.facebook_token do %>
                      <option
                        value={page["id"]}
                        selected={get_in(@config.facebook_page_ids || %{}, [lang.name]) == page["id"]}
                      >
                        {page_name} ({page["id"]})
                      </option>
                    <% end %>
                  </select>
                  <%= if get_in(@config.facebook_page_ids || %{}, [lang.name]) do %>
                    <.icon name="hero-check-circle" class="h-4 w-4 text-emerald-400 flex-shrink-0" />
                  <% else %>
                    <.icon name="hero-minus-circle" class="h-4 w-4 text-slate-600 flex-shrink-0" />
                  <% end %>
                </div>
              <% end %>
              <div class="pt-2">
                <button
                  type="submit"
                  class="flex items-center gap-1.5 px-4 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium transition-colors"
                >
                  <.icon name="hero-check" class="h-4 w-4" /> Save Facebook Pages
                </button>
              </div>
            </form>
          </div>
        <% end %>

        <!-- Pinterest per-language board selector -->
        <%= if map_non_empty?(@bot_user.pinterest_token) and @pinterest_boards_error do %>
          <div class="bg-slate-800 border border-amber-700/60 rounded-xl p-5 mb-5">
            <h2 class="text-sm font-semibold text-white mb-1">Pinterest — Boards</h2>
            <p class="text-xs text-amber-400 mb-4">
              Could not load boards from Pinterest — the token is likely expired or invalid.
              Reconnect the account to continue.
            </p>
            <.link
              href={~p"/auth/bot/target/#{@bot_user.id}/pinterest"}
              class="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium transition-colors"
            >
              Reconnect Pinterest
            </.link>
          </div>
        <% end %>

        <%= if map_non_empty?(@bot_user.pinterest_token) and is_nil(@pinterest_boards_error) and
              @pinterest_boards == [] do %>
          <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-5 mb-5">
            <h2 class="text-sm font-semibold text-white mb-1">Pinterest — Boards</h2>
            <p class="text-xs text-slate-500 mb-4">
              No boards on this account yet. Create one to configure per-language pinning.
            </p>
            <.create_board_form />
          </div>
        <% end %>

        <%= if map_non_empty?(@bot_user.pinterest_token) and @pinterest_boards != [] do %>
          <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-5 mb-5">
            <h2 class="text-sm font-semibold text-white mb-1">Pinterest — Board per Language</h2>
            <p class="text-xs text-slate-500 mb-4">
              Choose which Pinterest board to pin to for each language. Leave blank to skip that language.
            </p>
            <form phx-submit="save_pinterest_boards" class="space-y-3">
              <%= for lang <- @languages do %>
                <div class="flex items-center gap-3">
                  <span class="w-10 text-xs font-semibold text-slate-400 uppercase flex-shrink-0">
                    {lang.name}
                  </span>
                  <select
                    name={"pinterest_boards[#{lang.name}]"}
                    class="flex-1 bg-slate-700 border border-slate-600 rounded-lg text-slate-200 text-sm px-3 py-2 focus:border-primary-500 focus:outline-none"
                  >
                    <option value="">— not set —</option>
                    <%= for board <- @pinterest_boards do %>
                      <option
                        value={board["id"]}
                        selected={
                          get_in(@config.pinterest_board_ids || %{}, [lang.name]) == board["id"]
                        }
                      >
                        {board["name"]}
                      </option>
                    <% end %>
                  </select>
                  <%= if get_in(@config.pinterest_board_ids || %{}, [lang.name]) do %>
                    <.icon name="hero-check-circle" class="h-4 w-4 text-emerald-400 flex-shrink-0" />
                  <% else %>
                    <.icon name="hero-minus-circle" class="h-4 w-4 text-slate-600 flex-shrink-0" />
                  <% end %>
                </div>
              <% end %>
              <div class="pt-2">
                <button
                  type="submit"
                  class="flex items-center gap-1.5 px-4 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium transition-colors"
                >
                  <.icon name="hero-check" class="h-4 w-4" /> Save Pinterest Boards
                </button>
              </div>
            </form>
            <div class="mt-4 pt-4 border-t border-slate-700/60">
              <button
                phx-click="toggle_create_board"
                class="flex items-center gap-1.5 text-sm text-slate-400 hover:text-white transition-colors"
              >
                <.icon name="hero-plus" class="h-4 w-4" /> New board
              </button>
              <%= if @show_create_board do %>
                <div class="mt-3">
                  <.create_board_form />
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <!-- Pinterest not connected notice -->
        <%= if not map_non_empty?(@bot_user.pinterest_token) do %>
          <div class="bg-slate-800/50 border border-slate-700/40 rounded-xl p-5 mb-5 text-slate-500 text-sm">
            Connect Pinterest to configure per-language boards.
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :icon, :string, required: true
  attr :connected, :boolean, required: true
  attr :detail, :string, default: nil
  attr :connect_url, :string, required: true

  defp platform_card(assigns) do
    ~H"""
    <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4">
      <div class="flex items-center gap-2 mb-3">
        <span class="text-xl">{@icon}</span>
        <h3 class="font-semibold text-white text-sm">{@name}</h3>
        <span class={[
          "ml-auto inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-semibold border",
          if(@connected,
            do: "bg-emerald-500/20 text-emerald-400 border-emerald-500/30",
            else: "bg-slate-700/50 text-slate-500 border-slate-600/40"
          )
        ]}>
          {if @connected, do: "Connected", else: "Not connected"}
        </span>
      </div>
      <%= if @detail do %>
        <p class="text-xs text-slate-400 mb-3">{@detail}</p>
      <% end %>
      <a
        href={@connect_url}
        class="flex items-center justify-center gap-1.5 px-3 py-1.5 rounded-lg border border-slate-600 text-slate-300 hover:text-white hover:border-slate-500 text-xs font-medium transition-colors w-full"
      >
        {if @connected, do: "Reconnect", else: "Connect"}
      </a>
    </div>
    """
  end

  defp create_board_form(assigns) do
    ~H"""
    <form phx-submit="create_pinterest_board" class="space-y-3 max-w-md">
      <input
        type="text"
        name="board[name]"
        required
        maxlength="180"
        placeholder="Board name"
        class="w-full bg-slate-700 border border-slate-600 rounded-lg text-slate-200 text-sm px-3 py-2 placeholder-slate-500 focus:border-primary-500 focus:outline-none"
      />
      <textarea
        name="board[description]"
        rows="2"
        maxlength="500"
        placeholder="Description (optional)"
        class="w-full bg-slate-700 border border-slate-600 rounded-lg text-slate-200 text-sm px-3 py-2 placeholder-slate-500 focus:border-primary-500 focus:outline-none"
      ></textarea>
      <select
        name="board[privacy]"
        class="w-full bg-slate-700 border border-slate-600 rounded-lg text-slate-200 text-sm px-3 py-2 focus:border-primary-500 focus:outline-none"
      >
        <option value="PUBLIC">Public</option>
        <option value="SECRET">Secret</option>
      </select>
      <button
        type="submit"
        class="flex items-center gap-1.5 px-4 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium transition-colors"
      >
        <.icon name="hero-plus" class="h-4 w-4" /> Create Board
      </button>
    </form>
    """
  end

  defp instagram_detail(bot_user) do
    token = bot_user.instagram_token || %{}
    user_id = Map.get(token, "user_id")

    case Mehungry.Instagram.token_status(bot_user) do
      :connected ->
        case Mehungry.Instagram.Token.expires_at(token) do
          nil -> user_id && "User ID: #{user_id}"
          expires_at -> "User ID: #{user_id} — token expires #{Date.to_string(DateTime.to_date(expires_at))}"
        end

      :expiring ->
        days = DateTime.diff(Mehungry.Instagram.Token.expires_at(token), DateTime.utc_now(), :day)
        "User ID: #{user_id} — token expires in #{days} day(s)"

      status when status in [:stale, :error] ->
        "Token expired/invalid — reconnect"

      :not_connected ->
        nil
    end
  end

  defp facebook_detail(bot_user) do
    pages = bot_user.facebook_token || %{}
    count = map_size(pages)

    if count > 0,
      do: "#{count} page(s): #{Enum.map_join(pages, ", ", fn {name, _} -> name end)}",
      else: nil
  end

  defp map_non_empty?(map) when is_map(map) and map_size(map) > 0, do: true
  defp map_non_empty?(_), do: false

end
