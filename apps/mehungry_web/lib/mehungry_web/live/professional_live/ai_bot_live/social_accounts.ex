defmodule MehungryWeb.AiBotLive.SocialAccounts do
  use MehungryWeb, :live_view

  alias Mehungry.{AiBot, Accounts}
  alias Mehungry.Api.Pinterest

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    config = AiBot.get_active_config_for_month(today.month, today.year)

    if config do
      bot_user = Accounts.get_user!(config.bot_user_id)
      boards = Pinterest.get_boards(bot_user)

      {:ok,
       socket
       |> assign(:config, config)
       |> assign(:bot_user, bot_user)
       |> assign(:pinterest_boards, boards)
       |> assign(:page_title, "Bot Social Accounts")}
    else
      {:ok,
       socket
       |> assign(:config, nil)
       |> assign(:bot_user, nil)
       |> assign(:pinterest_boards, [])
       |> assign(:page_title, "Bot Social Accounts")}
    end
  end

  @impl true
  def handle_event("save_pinterest_board", %{"board_id" => board_id}, socket) do
    config = socket.assigns.config

    case AiBot.update_bot_config(config, %{pinterest_default_board_id: board_id}) do
      {:ok, updated_config} ->
        {:noreply,
         socket
         |> assign(:config, updated_config)
         |> put_flash(:info, "Default Pinterest board saved.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save Pinterest board.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center gap-4 mb-6">
        <.link navigate={~p"/professional/ai-bot"} class="btn btn-sm btn-ghost">← Config</.link>
        <h1 class="text-xl font-bold text-white">Bot Social Media Accounts</h1>
      </div>

      <%= if is_nil(@config) do %>
        <div class="alert alert-warning">
          No active bot configuration found for this month.
          <.link navigate={~p"/professional/ai-bot/new"} class="link">Create one</.link>.
        </div>
      <% else %>
        <div class="mb-4 bg-base-200 rounded-xl p-4">
          <p class="text-gray-300 text-sm">
            Managing social accounts for bot user:
            <strong class="text-white"><%= @bot_user.name || @bot_user.email %></strong>
          </p>
          <p class="text-xs text-gray-500 mt-1">
            Connect social accounts by clicking the links below. The OAuth flow will attach the token to the bot user, not your admin account.
          </p>
        </div>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-3">
          <!-- Instagram -->
          <div class="bg-base-200 rounded-xl p-4">
            <div class="flex items-center gap-3 mb-3">
              <div class="text-2xl">📸</div>
              <h2 class="font-semibold text-white">Instagram</h2>
            </div>
            <%= if map_non_empty?(@bot_user.instagram_token) do %>
              <div class="badge badge-success mb-3">Connected</div>
              <p class="text-xs text-gray-400">User ID: <%= Map.get(@bot_user.instagram_token, "user_id", "—") %></p>
            <% else %>
              <div class="badge badge-ghost mb-3">Not connected</div>
            <% end %>
            <a href={~p"/auth/bot/target/#{@bot_user.id}/instagram"}
               class="btn btn-sm btn-outline w-full mt-2">
              <%= if map_non_empty?(@bot_user.instagram_token), do: "Reconnect", else: "Connect" %>
            </a>
          </div>

          <!-- Facebook -->
          <div class="bg-base-200 rounded-xl p-4">
            <div class="flex items-center gap-3 mb-3">
              <div class="text-2xl">📘</div>
              <h2 class="font-semibold text-white">Facebook</h2>
            </div>
            <%= if map_non_empty?(@bot_user.facebook_token) do %>
              <div class="badge badge-success mb-3">Connected</div>
              <p class="text-xs text-gray-400">Pages: <%= map_size(@bot_user.facebook_token) %></p>
            <% else %>
              <div class="badge badge-ghost mb-3">Not connected</div>
            <% end %>
            <a href={~p"/auth/bot/target/#{@bot_user.id}/facebook"}
               class="btn btn-sm btn-outline w-full mt-2">
              <%= if map_non_empty?(@bot_user.facebook_token), do: "Reconnect", else: "Connect" %>
            </a>
          </div>

          <!-- Pinterest -->
          <div class="bg-base-200 rounded-xl p-4">
            <div class="flex items-center gap-3 mb-3">
              <div class="text-2xl">📌</div>
              <h2 class="font-semibold text-white">Pinterest</h2>
            </div>
            <%= if map_non_empty?(@bot_user.pinterest_token) do %>
              <div class="badge badge-success mb-3">Connected</div>
              <%= if @pinterest_boards != [] do %>
                <form phx-submit="save_pinterest_board" class="mt-2">
                  <label class="label text-xs text-gray-400">Default board</label>
                  <select name="board_id" class="select select-bordered select-sm w-full mb-2">
                    <option value="">— select board —</option>
                    <%= for board <- @pinterest_boards do %>
                      <option value={board["id"]}
                              selected={@config.pinterest_default_board_id == board["id"]}>
                        <%= board["name"] %>
                      </option>
                    <% end %>
                  </select>
                  <button type="submit" class="btn btn-sm btn-primary w-full">Save Board</button>
                </form>
              <% end %>
            <% else %>
              <div class="badge badge-ghost mb-3">Not connected</div>
            <% end %>
            <a href={~p"/auth/bot/target/#{@bot_user.id}/pinterest"}
               class="btn btn-sm btn-outline w-full mt-2">
              <%= if map_non_empty?(@bot_user.pinterest_token), do: "Reconnect", else: "Connect" %>
            </a>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp map_non_empty?(map) when is_map(map) and map_size(map) > 0, do: true
  defp map_non_empty?(_), do: false
end
