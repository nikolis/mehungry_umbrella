defmodule MehungryWeb.AiBotLive.ReviewQueue do
  use MehungryWeb, :live_view

  alias Mehungry.AI.Bot
  alias Mehungry.ObanWorkers.DailyRecipeGenerationWorker

  @status_filters [
    {"Pending", "pending_review"},
    {"Approved", "approved"},
    {"Rejected", "rejected"},
    {"Published", "published"},
    {"All", "all"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mehungry.PubSub, "admin:bot_recipes")
    end

    configs = Bot.list_bot_configs()
    today = Date.utc_today()

    default_config =
      Bot.get_active_config_for_month(today.month, today.year) || List.first(configs)

    {:ok,
     socket
     |> assign(:page_title, "AI Bot Review Queue")
     |> assign(:generating, false)
     |> assign(:status_filter, "pending_review")
     |> assign(:selected_date, Date.to_iso8601(Date.add(Date.utc_today(), 1)))
     |> assign(:configs, configs)
     |> assign(:selected_config_id, default_config && to_string(default_config.id))
     |> load_recipes()
     |> load_untracked()}
  end

  @impl true
  def handle_event("set_filter", %{"status" => status}, socket) do
    valid = Enum.map(@status_filters, &elem(&1, 1))

    if status in valid do
      {:noreply,
       socket
       |> assign(:status_filter, status)
       |> load_recipes()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("generate_now", params, socket) do
    target_date =
      case Map.get(params, "target_date") do
        date_str when is_binary(date_str) and date_str != "" -> date_str
        _ -> socket.assigns.selected_date
      end

    config_id =
      case Map.get(params, "bot_config_id") do
        id when is_binary(id) and id != "" -> id
        _ -> socket.assigns.selected_config_id
      end

    if is_nil(config_id) do
      {:noreply,
       put_flash(
         socket,
         :error,
         "Select a bot config to generate for — create one first if none exist."
       )}
    else
      job_args = %{target_date: target_date, bot_config_id: config_id}

      case DailyRecipeGenerationWorker.new(job_args) |> Oban.insert() do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:generating, true)
           |> put_flash(
             :info,
             "Generation job queued for #{config_label(config_id, socket.assigns.configs)} on #{target_date} — recipes will appear here shortly."
           )}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to queue generation: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_event("select_config", %{"bot_config_id" => id}, socket) do
    {:noreply, assign(socket, :selected_config_id, id)}
  end

  @impl true
  def handle_event("update_date", %{"target_date" => date}, socket) do
    {:noreply, assign(socket, :selected_date, date)}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    bot_recipe = Bot.get_bot_recipe!(String.to_integer(id))

    case Bot.approve_recipe(bot_recipe) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Recipe approved.")
         |> load_recipes()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to approve recipe.")}
    end
  end

  @impl true
  def handle_event("reject", %{"id" => id}, socket) do
    bot_recipe = Bot.get_bot_recipe!(String.to_integer(id))

    case Bot.reject_recipe(bot_recipe) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Recipe rejected.")
         |> load_recipes()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to reject recipe.")}
    end
  end

  @impl true
  def handle_event("import_one", %{"id" => recipe_id}, socket) do
    today = Date.utc_today()
    config = Bot.get_active_config_for_month(today.month, today.year)

    if is_nil(config) do
      {:noreply,
       put_flash(socket, :error, "No active bot config for this month — create one first.")}
    else
      recipe = Enum.find(socket.assigns.untracked, &(to_string(&1.id) == recipe_id))
      scheduled_date = (recipe && NaiveDateTime.to_date(recipe.inserted_at)) || today

      case Bot.import_single_recipe(String.to_integer(recipe_id), config, scheduled_date) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Recipe added to the review queue.")
           |> load_recipes()
           |> load_untracked()}

        {:error, _} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Could not import — there may already be a recipe for that meal/date slot."
           )}
      end
    end
  end

  @impl true
  def handle_event("dismiss_one", %{"id" => recipe_id}, socket) do
    today = Date.utc_today()
    config = Bot.get_active_config_for_month(today.month, today.year)

    if is_nil(config) do
      {:noreply,
       put_flash(socket, :error, "No active bot config for this month — create one first.")}
    else
      case Bot.dismiss_untracked_recipe(String.to_integer(recipe_id), config) do
        {:ok, _} ->
          {:noreply, socket |> load_untracked()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not dismiss recipe.")}
      end
    end
  end

  @impl true
  def handle_info({:pending_count_updated, _count}, socket) do
    {:noreply, socket |> assign(:generating, false) |> load_recipes()}
  end

  defp load_recipes(socket) do
    grouped =
      Bot.list_bot_recipes(socket.assigns.status_filter)
      |> Enum.group_by(& &1.scheduled_date)
      |> Enum.sort_by(fn {date, _} -> date end)

    assign(socket, :grouped, grouped)
  end

  defp load_untracked(socket) do
    today = Date.utc_today()
    config = Bot.get_active_config_for_month(today.month, today.year)

    untracked =
      if config, do: Bot.list_untracked_bot_recipes(config.bot_user_id), else: []

    assign(socket, :untracked, untracked)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :status_filters, @status_filters)
    total = Enum.reduce(assigns.grouped, 0, fn {_, recipes}, acc -> acc + length(recipes) end)
    assigns = assign(assigns, :total, total)

    ~H"""
    <div>
      <!-- Header -->
      <div class="flex items-center justify-between mb-4">
        <div>
          <h1 class="text-xl font-bold text-white">Review Queue</h1>
          <p class="text-sm text-slate-400 mt-0.5">
            AI-generated recipes — review, approve, or reconsider
          </p>
        </div>
        <div class="flex items-center gap-2">
          <form phx-submit="generate_now" class="flex items-center gap-2">
            <select
              name="bot_config_id"
              phx-change="select_config"
              disabled={@generating or @configs == []}
              title="Which bot config to generate for"
              class="bg-slate-800 border border-slate-700/60 rounded-lg text-slate-200 text-sm px-2 py-1.5 focus:border-amber-500/50 focus:outline-none disabled:opacity-50 max-w-[16rem]"
            >
              <%= if @configs == [] do %>
                <option value="">No configs — create one</option>
              <% else %>
                <%= for config <- @configs do %>
                  <option value={config.id} selected={to_string(config.id) == @selected_config_id}>
                    {config_option_label(config)}
                  </option>
                <% end %>
              <% end %>
            </select>
            <input
              type="date"
              name="target_date"
              value={@selected_date}
              phx-change="update_date"
              min={Date.to_iso8601(Date.utc_today())}
              disabled={@generating}
              class="bg-slate-800 border border-slate-700/60 rounded-lg text-slate-200 text-sm px-2 py-1.5 focus:border-amber-500/50 focus:outline-none disabled:opacity-50"
            />
            <button
              type="submit"
              disabled={@generating or @configs == []}
              class="flex items-center gap-1.5 px-3 py-2 rounded-lg bg-amber-500/20 hover:bg-amber-500/30 text-amber-400 border border-amber-500/30 text-sm font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <%= if @generating do %>
                <svg class="animate-spin h-4 w-4" fill="none" viewBox="0 0 24 24">
                  <circle
                    class="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    stroke-width="4"
                  >
                  </circle>
                  <path
                    class="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                  >
                  </path>
                </svg>
                Generating…
              <% else %>
                <.icon name="hero-bolt" class="h-4 w-4" /> Generate
              <% end %>
            </button>
          </form>
          <.link
            navigate={~p"/professional/ai-bot"}
            class="flex items-center gap-1.5 px-3 py-2 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 border border-slate-700/60 text-sm transition-colors"
          >
            <.icon name="hero-cog-6-tooth" class="h-4 w-4" /> Bot Config
          </.link>
        </div>
      </div>

      <!-- Status filter tabs -->
      <div class="flex items-center gap-1 mb-5 bg-slate-800/60 rounded-xl p-1 w-fit">
        <%= for {label, status} <- @status_filters do %>
          <button
            phx-click="set_filter"
            phx-value-status={status}
            class={[
              "px-3 py-1.5 rounded-lg text-xs font-medium transition-colors",
              if(@status_filter == status,
                do: filter_active_class(status),
                else: "text-slate-400 hover:text-white hover:bg-slate-700"
              )
            ]}
          >
            {label}
          </button>
        <% end %>
      </div>

      <!-- Untracked recipes section (only shown on pending filter) -->
      <%= if @status_filter == "pending_review" and length(@untracked) > 0 do %>
        <div class="mb-6 bg-amber-500/5 border border-amber-500/25 rounded-xl overflow-hidden">
          <div class="flex items-center gap-2 px-4 py-3 border-b border-amber-500/20">
            <.icon name="hero-exclamation-triangle" class="h-4 w-4 text-amber-400 flex-shrink-0" />
            <p class="text-sm text-amber-300 font-medium flex-1">
              {length(@untracked)} untracked recipe(s) found — review each one before adding to queue
            </p>
          </div>
          <div class="divide-y divide-amber-500/10">
            <%= for recipe <- @untracked do %>
              <div class="flex items-center gap-3 px-4 py-3">
                <%= if recipe.image_url do %>
                  <img src={recipe.image_url} class="w-10 h-10 rounded-lg object-cover flex-shrink-0" />
                <% else %>
                  <div class="w-10 h-10 rounded-lg bg-slate-700/60 flex-shrink-0 flex items-center justify-center">
                    <.icon name="hero-photo" class="h-4 w-4 text-slate-500" />
                  </div>
                <% end %>
                <div class="flex-1 min-w-0">
                  <div class="text-sm text-white font-medium truncate">{recipe.title}</div>
                  <div class="text-xs text-slate-500 mt-0.5">
                    Created {Calendar.strftime(NaiveDateTime.to_date(recipe.inserted_at), "%b %d, %Y")}
                  </div>
                </div>
                <div class="flex items-center gap-1.5 flex-shrink-0">
                  <button
                    phx-click="import_one"
                    phx-value-id={recipe.id}
                    class="flex items-center gap-1 px-2.5 py-1 rounded-lg bg-emerald-600/20 hover:bg-emerald-600/30 text-emerald-400 border border-emerald-500/30 text-xs font-medium transition-colors"
                  >
                    <.icon name="hero-plus" class="h-3 w-3" /> Add to Queue
                  </button>
                  <button
                    phx-click="dismiss_one"
                    phx-value-id={recipe.id}
                    title="Dismiss — won't appear here again"
                    class="flex items-center gap-1 px-2.5 py-1 rounded-lg text-slate-500 hover:text-slate-300 hover:bg-slate-700 text-xs transition-colors"
                  >
                    <.icon name="hero-x-mark" class="h-3 w-3" /> Dismiss
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @total > 0 do %>
        <div class="flex items-center gap-3 mb-6">
          <div class="flex items-center gap-2 px-3 py-1.5 bg-slate-800 border border-slate-700/60 rounded-lg text-sm">
            <span class="text-white font-semibold">{@total}</span>
            <span class="text-slate-400">recipes</span>
          </div>
          <div class="flex items-center gap-2 px-3 py-1.5 bg-slate-800 border border-slate-700/60 rounded-lg text-sm">
            <.icon name="hero-calendar-days" class="h-4 w-4 text-slate-400" />
            <span class="text-white font-semibold">{length(@grouped)}</span>
            <span class="text-slate-400">dates</span>
          </div>
        </div>
      <% end %>

      <%= if @grouped == [] do %>
        <div class="flex flex-col items-center justify-center py-24 text-center">
          <div class="w-16 h-16 rounded-full bg-slate-800 border border-slate-700/60 flex items-center justify-center mb-4">
            <.icon name="hero-inbox" class="h-8 w-8 text-slate-500" />
          </div>
          <p class="text-slate-300 font-medium">No recipes in this category</p>
          <%= if @status_filter == "pending_review" do %>
            <p class="text-slate-500 text-sm mt-1 mb-6">
              Generate new recipes to start filling the queue
            </p>
            <button
              phx-click="generate_now"
              phx-value-bot_config_id={@selected_config_id}
              phx-value-target_date={@selected_date}
              disabled={@generating or is_nil(@selected_config_id)}
              class="flex items-center gap-2 px-4 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium transition-colors disabled:opacity-50"
            >
              <.icon name="hero-bolt" class="h-4 w-4" /> Generate Now
            </button>
            <%= if @selected_config_id do %>
              <p class="text-slate-600 text-xs mt-2">
                Generating for
                <span class="text-slate-400">{config_label(@selected_config_id, @configs)}</span>
              </p>
            <% end %>
          <% else %>
            <p class="text-slate-500 text-sm mt-1">Switch to a different filter to see recipes</p>
          <% end %>
        </div>
      <% else %>
        <div class="space-y-8">
          <%= for {date, recipes} <- @grouped do %>
            <div>
              <div class="flex items-center gap-3 mb-3">
                <span class="text-xs font-semibold text-slate-500 uppercase tracking-widest">
                  {Calendar.strftime(date, "%A, %B %d %Y")}
                </span>
                <div class="flex-1 border-t border-slate-700/40"></div>
                <span class="text-xs text-slate-600">{length(recipes)} recipe{if length(recipes) != 1,
                  do: "s"}</span>
              </div>
              <div class="space-y-2">
                <%= for recipe <- recipes do %>
                  <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4 flex items-center gap-4 hover:border-slate-600 transition-colors">
                    <%= if recipe.recipe.image_url do %>
                      <img
                        src={recipe.recipe.image_url}
                        class="w-14 h-14 rounded-lg object-cover flex-shrink-0"
                      />
                    <% else %>
                      <div class="w-14 h-14 rounded-lg bg-slate-700/60 flex-shrink-0 flex items-center justify-center">
                        <.icon name="hero-photo" class="h-6 w-6 text-slate-500" />
                      </div>
                    <% end %>
                    <div class="flex-1 min-w-0">
                      <div class="font-medium text-white truncate text-sm">{recipe.recipe.title}</div>
                      <div class="flex items-center gap-2 mt-1">
                        <span class={[
                          "inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-semibold border",
                          meal_badge_class(recipe.meal_type)
                        ]}>
                          {String.replace(recipe.meal_type, "_", " ") |> String.capitalize()}
                        </span>
                        <%= if @status_filter == "all" do %>
                          <span class={[
                            "inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-semibold border",
                            status_badge_class(recipe.status)
                          ]}>
                            {status_label(recipe.status)}
                          </span>
                        <% end %>
                      </div>
                    </div>
                    <div class="flex items-center gap-2 flex-shrink-0">
                      <.link
                        navigate={~p"/professional/ai-bot/review/#{recipe.id}"}
                        class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-xs font-medium transition-colors"
                      >
                        <.icon name="hero-eye" class="h-3.5 w-3.5" /> Review
                      </.link>
                      <%= if recipe.status in ["approved", "rejected", "published"] do %>
                        <%= if recipe.status != "approved" and recipe.status != "published" do %>
                          <button
                            phx-click="approve"
                            phx-value-id={recipe.id}
                            title="Re-approve"
                            class="p-1.5 rounded-lg text-slate-500 hover:text-emerald-400 hover:bg-emerald-500/10 transition-colors"
                          >
                            <.icon name="hero-check-circle" class="h-4 w-4" />
                          </button>
                        <% end %>
                        <%= if recipe.status != "rejected" do %>
                          <button
                            phx-click="reject"
                            phx-value-id={recipe.id}
                            data-confirm="Reject this recipe?"
                            title="Reject"
                            class="p-1.5 rounded-lg text-slate-500 hover:text-red-400 hover:bg-red-500/10 transition-colors"
                          >
                            <.icon name="hero-x-mark" class="h-4 w-4" />
                          </button>
                        <% end %>
                      <% else %>
                        <button
                          phx-click="reject"
                          phx-value-id={recipe.id}
                          data-confirm="Reject this recipe?"
                          class="p-1.5 rounded-lg text-slate-500 hover:text-red-400 hover:bg-red-500/10 transition-colors"
                          title="Reject"
                        >
                          <.icon name="hero-x-mark" class="h-4 w-4" />
                        </button>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp meal_badge_class("breakfast"), do: "bg-amber-500/20 text-amber-400 border-amber-500/30"

  defp meal_badge_class("morning_snack"),
    do: "bg-orange-500/20 text-orange-400 border-orange-500/30"

  defp meal_badge_class("lunch"), do: "bg-emerald-500/20 text-emerald-400 border-emerald-500/30"
  defp meal_badge_class("afternoon_snack"), do: "bg-rose-500/20 text-rose-400 border-rose-500/30"
  defp meal_badge_class("dinner"), do: "bg-indigo-500/20 text-indigo-400 border-indigo-500/30"
  defp meal_badge_class(_), do: "bg-slate-700/50 text-slate-400 border-slate-600/40"

  defp status_badge_class("pending_review"),
    do: "bg-amber-500/20 text-amber-400 border-amber-500/30"

  defp status_badge_class("approved"),
    do: "bg-emerald-500/20 text-emerald-400 border-emerald-500/30"

  defp status_badge_class("rejected"), do: "bg-red-500/20 text-red-400 border-red-500/30"
  defp status_badge_class("published"), do: "bg-blue-500/20 text-blue-400 border-blue-500/30"
  defp status_badge_class(_), do: "bg-slate-700/50 text-slate-400 border-slate-600/40"

  defp status_label("pending_review"), do: "Pending"
  defp status_label("approved"), do: "Approved"
  defp status_label("rejected"), do: "Rejected"
  defp status_label("published"), do: "Published"
  defp status_label(s), do: s

  defp filter_active_class("pending_review"), do: "bg-amber-500/20 text-amber-300"
  defp filter_active_class("approved"), do: "bg-emerald-500/20 text-emerald-300"
  defp filter_active_class("rejected"), do: "bg-red-500/20 text-red-300"
  defp filter_active_class("published"), do: "bg-blue-500/20 text-blue-300"
  defp filter_active_class(_), do: "bg-slate-700 text-white"

  # Dropdown label: a readable name for the config plus its month/year, e.g.
  # "Kidney Stones (condition) · 8/2026" or "Mediterranean Summer · 8/2026".
  defp config_option_label(config) do
    name =
      case config.setup_type do
        "condition" ->
          direction =
            if config.diet_direction not in [nil, ""],
              do: config.diet_direction,
              else: "Condition setup"

          "#{direction} (condition)"

        _ ->
          config.theme || "Untitled"
      end

    "#{name} · #{config.month}/#{config.year}"
  end

  defp config_label(config_id, configs) do
    case Enum.find(configs, &(to_string(&1.id) == to_string(config_id))) do
      nil -> "config ##{config_id}"
      config -> config_option_label(config)
    end
  end
end
