defmodule MehungryWeb.AiBotLive.Config do
  use MehungryWeb, :live_view
  import MehungryWeb.FormatHelpers, only: [month_name: 1]

  alias Mehungry.{Accounts, Languages}
  alias Mehungry.AI.Bot
  alias Mehungry.AI.Bot.AiBotConfig

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> stream(:configs, Bot.list_bot_configs())
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
    socket
    |> assign(:form, nil)
    |> assign(:bot_user_social, nil)
    |> assign(:week_configs, [])
    |> assign(:day_configs, [])
    |> assign(:editing_config_id, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:form, to_form(Bot.change_bot_config(%AiBotConfig{})))
    |> assign(:bot_user_social, nil)
    |> assign(:week_configs, [])
    |> assign(:day_configs, [])
    |> assign(:editing_config_id, nil)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    config = Bot.get_bot_config!(id)
    bot_user = Accounts.get_user!(config.bot_user_id)

    socket
    |> assign(:form, to_form(Bot.change_bot_config(config)))
    |> assign(:bot_user_social, bot_user)
    |> assign(:week_configs, Bot.list_week_configs(config.id))
    |> assign(:day_configs, Bot.list_day_configs(config.id))
    |> assign(:editing_config_id, config.id)
  end

  @impl true
  def handle_event("validate", %{"ai_bot_config" => params}, socket) do
    form =
      case socket.assigns.live_action do
        :new -> Bot.change_bot_config(%AiBotConfig{}, params)
        :edit -> Bot.change_bot_config(socket.assigns.form.source.data, params)
      end
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("save", %{"ai_bot_config" => params}, socket) do
    result =
      case socket.assigns.live_action do
        :new -> Bot.create_bot_config(params)
        :edit -> Bot.update_bot_config(socket.assigns.form.source.data, params)
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
    config = Bot.get_bot_config!(String.to_integer(id))

    case Bot.delete_bot_config(config) do
      {:ok, _} ->
        {:noreply,
         socket
         |> stream_delete(:configs, config)
         |> put_flash(:info, "Configuration deleted.")}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "Cannot delete configuration with existing recipes.")}
    end
  end

  @impl true
  def handle_event("save_week_themes", %{"week_themes" => themes}, socket) do
    config_id = socket.assigns.editing_config_id

    results =
      Enum.map(themes, fn {week_str, theme} ->
        week_number = String.to_integer(week_str)
        theme = String.trim(theme)

        if theme == "" do
          case Bot.get_week_config(config_id, week_number) do
            nil -> :ok
            wc -> Bot.delete_week_config(wc)
          end
        else
          Bot.upsert_week_config(%{
            bot_config_id: config_id,
            week_number: week_number,
            theme: theme
          })
        end
      end)

    if Enum.any?(results, &match?({:error, _}, &1)) do
      {:noreply, put_flash(socket, :error, "Some week themes could not be saved.")}
    else
      {:noreply,
       socket
       |> assign(:week_configs, Bot.list_week_configs(config_id))
       |> put_flash(:info, "Week themes saved.")}
    end
  end

  @impl true
  def handle_event("save_day_config", %{"day_config" => params}, socket) do
    config_id = socket.assigns.editing_config_id

    attrs = %{
      bot_config_id: config_id,
      date: params["date"],
      focus_hint: String.trim(params["focus_hint"] || "")
    }

    if attrs.focus_hint == "" or attrs.date == "" do
      {:noreply, put_flash(socket, :error, "Date and focus hint are required.")}
    else
      case Bot.upsert_day_config(attrs) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:day_configs, Bot.list_day_configs(config_id))
           |> put_flash(:info, "Day focus saved.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not save day focus.")}
      end
    end
  end

  @impl true
  def handle_event("delete_day_config", %{"id" => id}, socket) do
    config_id = socket.assigns.editing_config_id
    dc = Mehungry.Repo.get!(Mehungry.AI.Bot.DayConfig, String.to_integer(id))

    case Bot.delete_day_config(dc) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:day_configs, Bot.list_day_configs(config_id))
         |> put_flash(:info, "Day focus removed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove day focus.")}
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
        <.link
          navigate={~p"/professional/ai-bot/review"}
          class="flex items-center gap-1.5 px-3 py-2 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 border border-slate-700/60 text-sm transition-colors"
        >
          <.icon name="hero-queue-list" class="h-4 w-4" /> Review Queue
        </.link>
        <.link
          navigate={~p"/professional/ai-bot/social"}
          class="flex items-center gap-1.5 px-3 py-2 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 border border-slate-700/60 text-sm transition-colors"
        >
          <.icon name="hero-share" class="h-4 w-4" /> Social Accounts
        </.link>
      </div>
    </div>

    <div class="flex gap-6">
      <!-- Configs list -->
      <div class="w-80 flex-shrink-0">
        <div class="flex items-center justify-between mb-3">
          <span class="text-xs font-semibold text-slate-500 uppercase tracking-wider">Monthly Themes</span>
          <.link
            patch={~p"/professional/ai-bot/new"}
            class="flex items-center gap-1 px-2.5 py-1.5 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-xs font-medium transition-colors"
          >
            <.icon name="hero-plus" class="h-3.5 w-3.5" /> New
          </.link>
        </div>
        <div id="configs" phx-update="stream" class="space-y-2">
          <div
            :for={{id, config} <- @streams.configs}
            id={id}
            class="bg-slate-800 border border-slate-700/60 rounded-xl p-4 hover:border-slate-600 transition-colors group"
          >
            <div class="flex items-start justify-between gap-2">
              <div class="min-w-0 flex-1">
                <div class="font-semibold text-white truncate text-sm">{config.theme}</div>
                <div class="text-xs text-slate-400 mt-0.5">
                  {month_name(config.month)} {config.year}
                </div>
              </div>
              <div class="flex items-center gap-1 flex-shrink-0 mt-0.5">
                <span class={[
                  "inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-semibold border",
                  if(config.active,
                    do: "bg-emerald-500/20 text-emerald-400 border-emerald-500/30",
                    else: "bg-slate-700/50 text-slate-500 border-slate-600/40"
                  )
                ]}>
                  {if config.active, do: "Active", else: "Off"}
                </span>
              </div>
            </div>
            <div class="flex gap-1 mt-3 opacity-0 group-hover:opacity-100 transition-opacity">
              <.link
                patch={~p"/professional/ai-bot/#{config.id}/edit"}
                class="flex items-center gap-1 px-2 py-1 rounded-md text-slate-400 hover:text-white hover:bg-slate-700 text-xs transition-colors"
              >
                <.icon name="hero-pencil-square" class="h-3.5 w-3.5" /> Edit
              </.link>
              <button
                phx-click="delete"
                phx-value-id={config.id}
                data-confirm="Delete this configuration?"
                class="flex items-center gap-1 px-2 py-1 rounded-md text-slate-400 hover:text-red-400 hover:bg-red-500/10 text-xs transition-colors"
              >
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
              {if @live_action == :new, do: "New Configuration", else: "Edit Configuration"}
            </h2>
            <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-5">
              <!-- Basic info -->
              <div>
                <p class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3">
                  Basic Info
                </p>
                <div class="space-y-3">
                  <div>
                    <label class="block text-xs text-slate-400 mb-1">Theme</label>
                    <.input
                      field={@form[:theme]}
                      type="text"
                      placeholder="e.g. Mediterranean Summer"
                      class="w-full bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-2 focus:border-primary-500 focus:outline-none"
                    />
                  </div>
                  <div class="grid grid-cols-2 gap-3">
                    <div>
                      <label class="block text-xs text-slate-400 mb-1">Month</label>
                      <.input
                        field={@form[:month]}
                        type="number"
                        min="1"
                        max="12"
                        class="w-full bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-2 focus:border-primary-500 focus:outline-none"
                      />
                    </div>
                    <div>
                      <label class="block text-xs text-slate-400 mb-1">Year</label>
                      <.input
                        field={@form[:year]}
                        type="number"
                        min="2024"
                        class="w-full bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-2 focus:border-primary-500 focus:outline-none"
                      />
                    </div>
                  </div>
                </div>
              </div>

              <div class="border-t border-slate-700/60 pt-5">
                <p class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3">
                  Bot Identity
                </p>
                <div class="space-y-3">
                  <div>
                    <label class="block text-xs text-slate-400 mb-1">Bot User</label>
                    <div class="flex gap-2">
                      <.input
                        field={@form[:bot_user_id]}
                        type="select"
                        options={Enum.map(@users, &{"#{&1.name || &1.email}", &1.id})}
                        class="flex-1 bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-2 focus:border-primary-500 focus:outline-none"
                      />
                      <button
                        type="button"
                        phx-click="show_create_user_modal"
                        class="flex items-center gap-1.5 px-3 py-2 rounded-lg border border-slate-600 text-slate-300 hover:text-white hover:border-slate-500 text-xs whitespace-nowrap transition-colors"
                      >
                        <.icon name="hero-plus" class="h-3.5 w-3.5" /> New User
                      </button>
                    </div>
                  </div>
                  <div class="flex items-center gap-3">
                    <.input
                      field={@form[:active]}
                      type="checkbox"
                      class="w-4 h-4 rounded border-slate-600 bg-slate-700 text-primary-500 focus:ring-primary-500"
                    />
                    <label class="text-sm text-slate-300">Active configuration</label>
                  </div>
                </div>
              </div>

              <!-- Social accounts status (edit mode only) -->
              <%= if @bot_user_social do %>
                <div class="border-t border-slate-700/60 pt-5">
                  <div class="flex items-center justify-between mb-3">
                    <p class="text-xs font-semibold text-slate-500 uppercase tracking-wider">
                      Social Accounts
                    </p>
                    <.link
                      navigate={~p"/professional/ai-bot/social"}
                      class="flex items-center gap-1 text-xs text-primary-400 hover:text-primary-300 transition-colors"
                    >
                      <.icon name="hero-arrow-top-right-on-square" class="h-3 w-3" /> Configure
                    </.link>
                  </div>
                  <div class="grid grid-cols-3 gap-2">
                    <.social_status_pill
                      label="Instagram"
                      connected={map_non_empty?(@bot_user_social.instagram_token)}
                    />
                    <.social_status_pill
                      label="Facebook"
                      connected={map_non_empty?(@bot_user_social.facebook_token)}
                      detail={facebook_pages_summary(@bot_user_social)}
                    />
                    <.social_status_pill
                      label="Pinterest"
                      connected={map_non_empty?(@bot_user_social.pinterest_token)}
                      detail={pinterest_boards_summary(@form.source.data)}
                    />
                  </div>
                </div>
              <% end %>

              <!-- Publish times grid -->
              <div class="border-t border-slate-700/60 pt-5">
                <p class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3">
                  Publish Times (UTC)
                </p>
                <div class="overflow-x-auto">
                  <div class="min-w-max">
                    <!-- Header row -->
                    <div
                      class="grid gap-2 mb-2"
                      style={"grid-template-columns: 140px repeat(#{length(@languages)}, minmax(120px, 1fr))"}
                    >
                      <div class="text-xs text-slate-500 font-medium px-1">Meal</div>
                      <%= for lang <- @languages do %>
                        <div class="text-center">
                          <span class="inline-block px-2 py-0.5 rounded-md bg-slate-700 text-slate-300 text-xs font-semibold uppercase">
                            {lang.name}
                          </span>
                        </div>
                      <% end %>
                    </div>
                    <!-- Data rows -->
                    <%= for meal <- @meal_types do %>
                      <div
                        class="grid gap-2 mb-2 items-center"
                        style={"grid-template-columns: 140px repeat(#{length(@languages)}, minmax(120px, 1fr))"}
                      >
                        <div class="text-xs text-slate-300 font-medium px-1 capitalize">
                          {String.replace(meal, "_", " ")}
                        </div>
                        <%= for lang <- @languages do %>
                          <div>
                            <input
                              type="time"
                              name={"ai_bot_config[publish_times][#{meal}][#{lang.name}]"}
                              value={
                                get_in(@form[:publish_times].value || %{}, [meal, lang.name]) || ""
                              }
                              class="w-full bg-slate-700 border border-slate-600 rounded-lg text-white text-xs px-2 py-1.5 focus:border-primary-500 focus:outline-none"
                            />
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>

              <div class="flex gap-2 pt-1">
                <button
                  type="submit"
                  class="flex items-center gap-1.5 px-4 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium transition-colors"
                >
                  <.icon name="hero-check" class="h-4 w-4" /> Save
                </button>
                <.link
                  patch={~p"/professional/ai-bot"}
                  class="px-4 py-2 rounded-lg text-slate-400 hover:text-white hover:bg-slate-700 text-sm transition-colors"
                >
                  Cancel
                </.link>
              </div>
            </.form>

            <!-- Week Themes (edit mode only) -->
            <%= if @live_action == :edit do %>
              <div class="border-t border-slate-700/60 pt-5 mt-5">
                <p class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3">
                  Week Themes
                </p>
                <p class="text-xs text-slate-500 mb-4">
                  Sub-theme per week of the month (days 1–7 = week 1, 8–14 = week 2, etc.).
                  Leave a week blank to use only the monthly theme.
                </p>
                <form phx-submit="save_week_themes" class="space-y-2">
                  <%= for week_num <- 1..6 do %>
                    <% existing = Enum.find(@week_configs, &(&1.week_number == week_num)) %>
                    <div class="flex items-center gap-3">
                      <span class="w-16 text-xs font-semibold text-slate-400 flex-shrink-0">Week {week_num}</span>
                      <input
                        type="text"
                        name={"week_themes[#{week_num}]"}
                        value={(existing && existing.theme) || ""}
                        placeholder="e.g. Greek Diet Week"
                        class="flex-1 bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-1.5 focus:border-primary-500 focus:outline-none placeholder-slate-500"
                      />
                      <%= if existing do %>
                        <.icon
                          name="hero-check-circle"
                          class="h-4 w-4 text-emerald-400 flex-shrink-0"
                        />
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
                      <.icon name="hero-check" class="h-4 w-4" /> Save Week Themes
                    </button>
                  </div>
                </form>
              </div>

              <!-- Day Overrides (edit mode only) -->
              <div class="border-t border-slate-700/60 pt-5 mt-5">
                <p class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3">
                  Day Focus Overrides
                </p>
                <p class="text-xs text-slate-500 mb-4">
                  Set a specific generation focus for any day, e.g. "6 ingredients only", "no meat", "quick under 20 min".
                </p>

                <!-- Add new day override -->
                <form phx-submit="save_day_config" class="flex items-end gap-2 mb-4">
                  <div class="flex-shrink-0">
                    <label class="block text-xs text-slate-500 mb-1">Date</label>
                    <input
                      type="date"
                      name="day_config[date]"
                      class="bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-1.5 focus:border-primary-500 focus:outline-none"
                    />
                  </div>
                  <div class="flex-1">
                    <label class="block text-xs text-slate-500 mb-1">Focus Hint</label>
                    <input
                      type="text"
                      name="day_config[focus_hint]"
                      placeholder="e.g. 6 ingredients recipes"
                      class="w-full bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-1.5 focus:border-primary-500 focus:outline-none placeholder-slate-500"
                    />
                  </div>
                  <button
                    type="submit"
                    class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium transition-colors flex-shrink-0"
                  >
                    <.icon name="hero-plus" class="h-4 w-4" /> Add
                  </button>
                </form>

                <!-- Existing day overrides -->
                <%= if @day_configs == [] do %>
                  <p class="text-xs text-slate-600 italic">No day overrides set.</p>
                <% else %>
                  <div class="space-y-1.5">
                    <%= for dc <- @day_configs do %>
                      <div class="flex items-center gap-3 bg-slate-700/40 rounded-lg px-3 py-2">
                        <span class="text-xs font-semibold text-slate-400 w-24 flex-shrink-0">
                          {Calendar.strftime(dc.date, "%b %d, %Y")}
                        </span>
                        <span class="text-sm text-slate-200 flex-1 truncate">{dc.focus_hint}</span>
                        <button
                          phx-click="delete_day_config"
                          phx-value-id={dc.id}
                          data-confirm="Remove this day focus?"
                          class="p-1 rounded text-slate-500 hover:text-red-400 hover:bg-red-500/10 transition-colors flex-shrink-0"
                        >
                          <.icon name="hero-x-mark" class="h-3.5 w-3.5" />
                        </button>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>
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
    <.modal
      :if={@show_create_user_modal}
      id="create-bot-user-modal"
      show
      on_cancel={JS.push("hide_create_user_modal")}
    >
      <h3 class="text-base font-semibold text-white mb-5">Create Bot User</h3>
      <form phx-submit="create_bot_user" class="space-y-4">
        <div>
          <label class="block text-xs text-slate-400 mb-1">Name</label>
          <input
            type="text"
            name="user[name]"
            value="m3hungry ai"
            class="w-full bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-2 focus:border-primary-500 focus:outline-none"
            required
          />
        </div>
        <div>
          <label class="block text-xs text-slate-400 mb-1">Email</label>
          <input
            type="email"
            name="user[email]"
            placeholder="bot@m3hungry.com"
            class="w-full bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-2 focus:border-primary-500 focus:outline-none"
            required
          />
        </div>
        <div x-data="{ pic: '' }">
          <label class="block text-xs text-slate-400 mb-1">Profile Picture</label>
          <div class="flex gap-2 mb-2">
            <button
              type="button"
              @click="pic = '/images/logo2.svg'"
              class="flex items-center gap-2 px-3 py-2 rounded-lg bg-slate-700 hover:bg-slate-600 border border-slate-600 hover:border-primary-500/50 text-slate-300 hover:text-white text-xs font-medium transition-colors"
            >
              <img src="/images/logo2.svg" class="w-5 h-5 rounded" /> Use App Logo
            </button>
          </div>
          <div class="flex items-center gap-3">
            <img
              x-bind:src="pic"
              x-show="pic"
              class="w-10 h-10 rounded-full object-cover border border-slate-600 flex-shrink-0"
            />
            <div
              class="w-10 h-10 rounded-full bg-slate-700 border border-slate-600 flex items-center justify-center flex-shrink-0"
              x-show="!pic"
            >
              <.icon name="hero-user" class="h-5 w-5 text-slate-500" />
            </div>
            <input
              x-model="pic"
              type="text"
              name="user[profile_pic]"
              placeholder="https://... or use the button above"
              class="flex-1 bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-2 focus:border-primary-500 focus:outline-none"
            />
          </div>
        </div>
        <div class="flex gap-2 pt-1">
          <button
            type="submit"
            class="flex items-center gap-1.5 px-4 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium transition-colors"
          >
            <.icon name="hero-user-plus" class="h-4 w-4" /> Create User
          </button>
          <button
            type="button"
            phx-click="hide_create_user_modal"
            class="px-4 py-2 rounded-lg text-slate-400 hover:text-white hover:bg-slate-700 text-sm transition-colors"
          >
            Cancel
          </button>
        </div>
      </form>
    </.modal>
    """
  end

  attr :label, :string, required: true
  attr :connected, :boolean, required: true
  attr :detail, :string, default: nil

  defp social_status_pill(assigns) do
    ~H"""
    <div class={[
      "rounded-lg px-3 py-2 border text-xs",
      if(@connected,
        do: "bg-emerald-500/10 border-emerald-500/25",
        else: "bg-slate-700/40 border-slate-600/40"
      )
    ]}>
      <div class="flex items-center gap-1.5 mb-0.5">
        <div class={[
          "w-1.5 h-1.5 rounded-full flex-shrink-0",
          if(@connected, do: "bg-emerald-400", else: "bg-slate-600")
        ]}>
        </div>
        <span class={if(@connected, do: "text-emerald-300 font-medium", else: "text-slate-500")}>{@label}</span>
      </div>
      <%= if @detail do %>
        <p class="text-slate-500 truncate pl-3">{@detail}</p>
      <% end %>
    </div>
    """
  end

  defp facebook_pages_summary(bot_user) do
    pages = bot_user.facebook_token || %{}
    count = map_size(pages)
    if count > 0, do: "#{count} page(s) available", else: nil
  end

  defp pinterest_boards_summary(config) do
    boards = config.pinterest_board_ids || %{}
    count = map_size(boards)
    if count > 0, do: "#{count} board(s) configured", else: nil
  end

  defp map_non_empty?(map) when is_map(map) and map_size(map) > 0, do: true
  defp map_non_empty?(_), do: false

end
