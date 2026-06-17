defmodule MehungryWeb.AiBotLive.Config do
  use MehungryWeb, :live_view

  alias Mehungry.{AiBot, Accounts, Languages}
  alias Mehungry.AiBot.AiBotConfig

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> stream(:configs, AiBot.list_bot_configs())
     |> assign(:users, Accounts.list_users())
     |> assign(:languages, Languages.list_languages())
     |> assign(:meal_types, AiBotConfig.meal_types())
     |> assign(:form, nil)
     |> assign(:show_create_user_modal, false)
     |> assign(:create_user_form, to_form(%{"name" => "", "email" => "", "profile_pic" => ""}))
     |> assign(:page_title, "AI Bot Configuration")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :form, nil)
  end

  defp apply_action(socket, :new, _params) do
    assign(socket, :form, to_form(AiBot.change_bot_config(%AiBotConfig{})))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    config = AiBot.get_bot_config!(id)
    assign(socket, :form, to_form(AiBot.change_bot_config(config)))
  end

  @impl true
  def handle_event("validate", %{"ai_bot_config" => params}, socket) do
    form =
      case socket.assigns.live_action do
        :new -> AiBot.change_bot_config(%AiBotConfig{}, params)
        :edit -> AiBot.change_bot_config(socket.assigns.form.source.data, params)
      end
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("save", %{"ai_bot_config" => params}, socket) do
    result =
      case socket.assigns.live_action do
        :new -> AiBot.create_bot_config(params)
        :edit -> AiBot.update_bot_config(socket.assigns.form.source.data, params)
      end

    case result do
      {:ok, config} ->
        {:noreply,
         socket
         |> stream_insert(:configs, config)
         |> put_flash(:info, "Configuration saved.")
         |> push_patch(to: ~p"/professional/ai-bot")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    config = AiBot.get_bot_config!(String.to_integer(id))

    case AiBot.delete_bot_config(config) do
      {:ok, _} ->
        {:noreply,
         socket
         |> stream_delete(:configs, config)
         |> put_flash(:info, "Configuration deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Cannot delete configuration with existing recipes.")}
    end
  end

  @impl true
  def handle_event("show_create_user_modal", _, socket) do
    {:noreply, assign(socket, :show_create_user_modal, true)}
  end

  @impl true
  def handle_event("hide_create_user_modal", _, socket) do
    {:noreply, assign(socket, :show_create_user_modal, false)}
  end

  @impl true
  def handle_event("create_bot_user", %{"user" => params}, socket) do
    case Accounts.register_3rd_party_user(params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:users, Accounts.list_users())
         |> assign(:show_create_user_modal, false)
         |> put_flash(:info, "Bot user #{user.email} created and confirmed.")}

      {:error, changeset} ->
        errors = Enum.map(changeset.errors, fn {field, {msg, _}} -> "#{field}: #{msg}" end)
        {:noreply, put_flash(socket, :error, "Error: #{Enum.join(errors, ", ")}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <!-- Top nav strip -->
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="text-xl font-bold text-white">AI Bot</h1>
        <p class="text-sm text-slate-400 mt-0.5">Manage monthly themes and publish schedules</p>
      </div>
      <div class="flex items-center gap-2">
        <.link navigate={~p"/professional/ai-bot/review"} class="flex items-center gap-1.5 px-3 py-2 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 border border-slate-700/60 text-sm transition-colors">
          <.icon name="hero-queue-list" class="h-4 w-4" /> Review Queue
        </.link>
        <.link navigate={~p"/professional/ai-bot/social"} class="flex items-center gap-1.5 px-3 py-2 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 border border-slate-700/60 text-sm transition-colors">
          <.icon name="hero-share" class="h-4 w-4" /> Social Accounts
        </.link>
      </div>
    </div>

    <div class="flex gap-6">
      <!-- Configs list -->
      <div class="w-80 flex-shrink-0">
        <div class="flex items-center justify-between mb-3">
          <span class="text-xs font-semibold text-slate-500 uppercase tracking-wider">Monthly Themes</span>
          <.link patch={~p"/professional/ai-bot/new"} class="flex items-center gap-1 px-2.5 py-1.5 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-xs font-medium transition-colors">
            <.icon name="hero-plus" class="h-3.5 w-3.5" /> New
          </.link>
        </div>
        <div id="configs" phx-update="stream" class="space-y-2">
          <div :for={{id, config} <- @streams.configs} id={id}
               class="bg-slate-800 border border-slate-700/60 rounded-xl p-4 hover:border-slate-600 transition-colors group">
            <div class="flex items-start justify-between gap-2">
              <div class="min-w-0 flex-1">
                <div class="font-semibold text-white truncate text-sm"><%= config.theme %></div>
                <div class="text-xs text-slate-400 mt-0.5"><%= month_name(config.month) %> <%= config.year %></div>
              </div>
              <div class="flex items-center gap-1 flex-shrink-0 mt-0.5">
                <span class={[
                  "inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-semibold border",
                  if(config.active,
                    do: "bg-emerald-500/20 text-emerald-400 border-emerald-500/30",
                    else: "bg-slate-700/50 text-slate-500 border-slate-600/40")
                ]}>
                  <%= if config.active, do: "Active", else: "Off" %>
                </span>
              </div>
            </div>
            <div class="flex gap-1 mt-3 opacity-0 group-hover:opacity-100 transition-opacity">
              <.link patch={~p"/professional/ai-bot/#{config.id}/edit"}
                     class="flex items-center gap-1 px-2 py-1 rounded-md text-slate-400 hover:text-white hover:bg-slate-700 text-xs transition-colors">
                <.icon name="hero-pencil-square" class="h-3.5 w-3.5" /> Edit
              </.link>
              <button phx-click="delete" phx-value-id={config.id}
                      data-confirm="Delete this configuration?"
                      class="flex items-center gap-1 px-2 py-1 rounded-md text-slate-400 hover:text-red-400 hover:bg-red-500/10 text-xs transition-colors">
                <.icon name="hero-trash" class="h-3.5 w-3.5" /> Delete
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Form panel -->
      <div class="flex-1 min-w-0">
        <%= if @form do %>
          <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-6">
            <h2 class="text-base font-semibold text-white mb-5">
              <%= if @live_action == :new, do: "New Configuration", else: "Edit Configuration" %>
            </h2>
            <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-5">
              <!-- Basic info -->
              <div>
                <p class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3">Basic Info</p>
                <div class="space-y-3">
                  <div>
                    <label class="block text-xs text-slate-400 mb-1">Theme</label>
                    <.input field={@form[:theme]} type="text" placeholder="e.g. Mediterranean Summer"
                            class="w-full bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-2 focus:border-primary-500 focus:outline-none" />
                  </div>
                  <div class="grid grid-cols-2 gap-3">
                    <div>
                      <label class="block text-xs text-slate-400 mb-1">Month</label>
                      <.input field={@form[:month]} type="number" min="1" max="12"
                              class="w-full bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-2 focus:border-primary-500 focus:outline-none" />
                    </div>
                    <div>
                      <label class="block text-xs text-slate-400 mb-1">Year</label>
                      <.input field={@form[:year]} type="number" min="2024"
                              class="w-full bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-2 focus:border-primary-500 focus:outline-none" />
                    </div>
                  </div>
                </div>
              </div>

              <div class="border-t border-slate-700/60 pt-5">
                <p class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3">Bot Identity</p>
                <div class="space-y-3">
                  <div>
                    <label class="block text-xs text-slate-400 mb-1">Bot User</label>
                    <div class="flex gap-2">
                      <.input field={@form[:bot_user_id]} type="select"
                        options={Enum.map(@users, &{"#{&1.name || &1.email}", &1.id})}
                        class="flex-1 bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-2 focus:border-primary-500 focus:outline-none" />
                      <button type="button" phx-click="show_create_user_modal"
                              class="flex items-center gap-1.5 px-3 py-2 rounded-lg border border-slate-600 text-slate-300 hover:text-white hover:border-slate-500 text-xs whitespace-nowrap transition-colors">
                        <.icon name="hero-plus" class="h-3.5 w-3.5" /> New User
                      </button>
                    </div>
                  </div>
                  <div>
                    <label class="block text-xs text-slate-400 mb-1">Pinterest Default Board ID</label>
                    <.input field={@form[:pinterest_default_board_id]} type="text"
                            placeholder="board_id from Pinterest"
                            class="w-full bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-2 focus:border-primary-500 focus:outline-none" />
                  </div>
                  <div class="flex items-center gap-3">
                    <.input field={@form[:active]} type="checkbox" class="w-4 h-4 rounded border-slate-600 bg-slate-700 text-primary-500 focus:ring-primary-500" />
                    <label class="text-sm text-slate-300">Active configuration</label>
                  </div>
                </div>
              </div>

              <!-- Publish times grid -->
              <div class="border-t border-slate-700/60 pt-5">
                <p class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3">Publish Times (UTC)</p>
                <div class="overflow-x-auto">
                  <div class="min-w-max">
                    <!-- Header row -->
                    <div class="grid gap-2 mb-2"
                         style={"grid-template-columns: 140px repeat(#{length(@languages)}, minmax(120px, 1fr))"}>
                      <div class="text-xs text-slate-500 font-medium px-1">Meal</div>
                      <%= for lang <- @languages do %>
                        <div class="text-center">
                          <span class="inline-block px-2 py-0.5 rounded-md bg-slate-700 text-slate-300 text-xs font-semibold uppercase">
                            <%= lang.name %>
                          </span>
                        </div>
                      <% end %>
                    </div>
                    <!-- Data rows -->
                    <%= for meal <- @meal_types do %>
                      <div class="grid gap-2 mb-2 items-center"
                           style={"grid-template-columns: 140px repeat(#{length(@languages)}, minmax(120px, 1fr))"}>
                        <div class="text-xs text-slate-300 font-medium px-1 capitalize">
                          <%= String.replace(meal, "_", " ") %>
                        </div>
                        <%= for lang <- @languages do %>
                          <div>
                            <input type="time"
                                   name={"ai_bot_config[publish_times][#{meal}][#{lang.name}]"}
                                   value={get_in(@form[:publish_times].value || %{}, [meal, lang.name]) || ""}
                                   class="w-full bg-slate-700 border border-slate-600 rounded-lg text-white text-xs px-2 py-1.5 focus:border-primary-500 focus:outline-none" />
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>

              <div class="flex gap-2 pt-1">
                <button type="submit" class="flex items-center gap-1.5 px-4 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium transition-colors">
                  <.icon name="hero-check" class="h-4 w-4" /> Save
                </button>
                <.link patch={~p"/professional/ai-bot"} class="px-4 py-2 rounded-lg text-slate-400 hover:text-white hover:bg-slate-700 text-sm transition-colors">
                  Cancel
                </.link>
              </div>
            </.form>
          </div>
        <% else %>
          <div class="flex flex-col items-center justify-center h-64 text-center">
            <div class="w-14 h-14 rounded-full bg-slate-800 border border-slate-700/60 flex items-center justify-center mb-4">
              <.icon name="hero-cpu-chip" class="h-7 w-7 text-slate-500" />
            </div>
            <p class="text-slate-400 text-sm">Select a configuration to edit</p>
            <p class="text-slate-600 text-xs mt-1">or create a new one with the button above</p>
          </div>
        <% end %>
      </div>
    </div>

    <!-- Create Bot User Modal -->
    <.modal :if={@show_create_user_modal} id="create-bot-user-modal" show
            on_cancel={JS.push("hide_create_user_modal")}>
      <h3 class="text-base font-semibold text-white mb-5">Create Bot User</h3>
      <form phx-submit="create_bot_user" class="space-y-4">
        <div>
          <label class="block text-xs text-slate-400 mb-1">Name</label>
          <input type="text" name="user[name]" value="m3hungry ai"
                 class="w-full bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-2 focus:border-primary-500 focus:outline-none" required />
        </div>
        <div>
          <label class="block text-xs text-slate-400 mb-1">Email</label>
          <input type="email" name="user[email]" placeholder="bot@m3hungry.com"
                 class="w-full bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-2 focus:border-primary-500 focus:outline-none" required />
        </div>
        <div x-data="{ pic: '' }">
          <label class="block text-xs text-slate-400 mb-1">Profile Picture</label>
          <div class="flex gap-2 mb-2">
            <button type="button"
                    @click="pic = '/images/logo2.svg'"
                    class="flex items-center gap-2 px-3 py-2 rounded-lg bg-slate-700 hover:bg-slate-600 border border-slate-600 hover:border-primary-500/50 text-slate-300 hover:text-white text-xs font-medium transition-colors">
              <img src="/images/logo2.svg" class="w-5 h-5 rounded" />
              Use App Logo
            </button>
          </div>
          <div class="flex items-center gap-3">
            <img x-bind:src="pic" x-show="pic" class="w-10 h-10 rounded-full object-cover border border-slate-600 flex-shrink-0" />
            <div class="w-10 h-10 rounded-full bg-slate-700 border border-slate-600 flex items-center justify-center flex-shrink-0" x-show="!pic">
              <.icon name="hero-user" class="h-5 w-5 text-slate-500" />
            </div>
            <input x-model="pic" type="text" name="user[profile_pic]" placeholder="https://... or use the button above"
                   class="flex-1 bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-2 focus:border-primary-500 focus:outline-none" />
          </div>
        </div>
        <div class="flex gap-2 pt-1">
          <button type="submit" class="flex items-center gap-1.5 px-4 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium transition-colors">
            <.icon name="hero-user-plus" class="h-4 w-4" /> Create User
          </button>
          <button type="button" phx-click="hide_create_user_modal"
                  class="px-4 py-2 rounded-lg text-slate-400 hover:text-white hover:bg-slate-700 text-sm transition-colors">
            Cancel
          </button>
        </div>
      </form>
    </.modal>
    """
  end

  defp month_name(1), do: "January"
  defp month_name(2), do: "February"
  defp month_name(3), do: "March"
  defp month_name(4), do: "April"
  defp month_name(5), do: "May"
  defp month_name(6), do: "June"
  defp month_name(7), do: "July"
  defp month_name(8), do: "August"
  defp month_name(9), do: "September"
  defp month_name(10), do: "October"
  defp month_name(11), do: "November"
  defp month_name(12), do: "December"
  defp month_name(_), do: "Unknown"
end
