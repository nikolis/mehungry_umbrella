defmodule MehungryWeb.AiBotLive.RecipeReview do
  use MehungryWeb, :live_view

  alias Mehungry.{AiBot, Languages}
  alias Mehungry.ObanWorkers.{RecipeTranslationWorker, RecipePublishWorker}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :bot_recipe, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    bot_recipe = AiBot.get_bot_recipe!(String.to_integer(id))
    translations = AiBot.list_translations_for_recipe(bot_recipe.recipe.id)
    languages = Languages.list_languages()

    translated_langs = Enum.map(translations, & &1.language_name)

    {:noreply,
     socket
     |> assign(:bot_recipe, bot_recipe)
     |> assign(:recipe, bot_recipe.recipe)
     |> assign(:translations, translations)
     |> assign(:languages, languages)
     |> assign(:translated_langs, translated_langs)
     |> assign(:page_title, "Review: #{bot_recipe.recipe.title}")}
  end

  @impl true
  def handle_event("approve", _, socket) do
    case AiBot.approve_recipe(socket.assigns.bot_recipe) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:bot_recipe, %{socket.assigns.bot_recipe | status: updated.status})
         |> put_flash(:info, "Recipe approved.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to approve recipe.")}
    end
  end

  @impl true
  def handle_event("reject", _, socket) do
    case AiBot.reject_recipe(socket.assigns.bot_recipe) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:bot_recipe, %{socket.assigns.bot_recipe | status: updated.status})
         |> put_flash(:info, "Recipe rejected.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to reject recipe.")}
    end
  end

  @impl true
  def handle_event("publish_now", _, socket) do
    bot_recipe = socket.assigns.bot_recipe

    if bot_recipe.status != "approved" do
      {:noreply, put_flash(socket, :error, "Recipe must be approved before publishing.")}
    else
      config = bot_recipe.bot_config
      lang_times = get_in(config.publish_times, [bot_recipe.meal_type]) || %{}

      # Fall back to "en" if no publish times configured for this meal
      languages = if map_size(lang_times) > 0, do: Map.keys(lang_times), else: ["en"]

      jobs_inserted =
        Enum.reduce(languages, 0, fn lang, count ->
          case RecipePublishWorker.new(%{ai_bot_recipe_id: bot_recipe.id, language_name: lang}) |> Oban.insert() do
            {:ok, _} -> count + 1
            _ -> count
          end
        end)

      {:noreply, put_flash(socket, :info, "Publish jobs queued for #{jobs_inserted} language(s) — check social media shortly.")}
    end
  end

  @impl true
  def handle_event("trigger_translation", %{"lang" => lang}, socket) do
    case RecipeTranslationWorker.enqueue(socket.assigns.recipe.id, lang) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Translation to #{lang} queued.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to queue translation: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <!-- Header -->
      <div class="flex items-center gap-3 mb-5">
        <.link navigate={~p"/professional/ai-bot/review"}
               class="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition-colors">
          <.icon name="hero-arrow-left" class="h-5 w-5" />
        </.link>
        <h1 class="text-lg font-semibold text-white flex-1 truncate"><%= @recipe && @recipe.title %></h1>
      </div>

      <%= if @bot_recipe do %>
        <!-- Status banner -->
        <div class={["flex items-center gap-2 px-4 py-2.5 rounded-xl mb-5 text-sm font-medium", status_banner_class(@bot_recipe.status)]}>
          <.icon name={status_icon(@bot_recipe.status)} class="h-4 w-4" />
          <%= status_label(@bot_recipe.status) %>
        </div>

        <div class="grid grid-cols-3 gap-5">
          <!-- Recipe preview -->
          <div class="col-span-2 space-y-4">
            <%= if @recipe.image_url do %>
              <div class="relative rounded-xl overflow-hidden">
                <img src={@recipe.image_url} class="w-full aspect-video object-cover" />
                <div class="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/70 via-black/20 to-transparent p-4">
                  <h2 class="font-bold text-white text-lg leading-tight"><%= @recipe.title %></h2>
                </div>
              </div>
            <% end %>

            <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4">
              <%= if !@recipe.image_url do %>
                <h2 class="font-bold text-white text-base mb-2"><%= @recipe.title %></h2>
              <% end %>
              <p class="text-slate-300 text-sm leading-relaxed"><%= @recipe.description %></p>
            </div>

            <%= if @recipe.recipe_ingredients != [] do %>
              <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4">
                <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3">Ingredients</h3>
                <ul class="space-y-1.5">
                  <%= for ri <- @recipe.recipe_ingredients do %>
                    <li class="flex items-baseline gap-2 text-sm">
                      <span class="text-slate-400 text-xs tabular-nums w-8 text-right flex-shrink-0"><%= ri.quantity %></span>
                      <span class="text-slate-500 text-xs flex-shrink-0"><%= ri.measurement_unit.name %></span>
                      <span class="text-slate-200"><%= ri.ingredient.name %></span>
                    </li>
                  <% end %>
                </ul>
              </div>
            <% end %>

            <%= if @recipe.steps && @recipe.steps != [] do %>
              <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4">
                <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3">Steps</h3>
                <ol class="space-y-3">
                  <%= for {step, i} <- Enum.with_index(@recipe.steps) do %>
                    <li class="flex gap-3">
                      <span class="flex-shrink-0 w-6 h-6 rounded-full bg-slate-700 text-slate-400 text-xs font-bold flex items-center justify-center mt-0.5">
                        <%= i + 1 %>
                      </span>
                      <p class="text-sm text-slate-300 leading-relaxed"><%= step.description %></p>
                    </li>
                  <% end %>
                </ol>
              </div>
            <% end %>
          </div>

          <!-- Right panel -->
          <div class="space-y-4">
            <!-- Actions -->
            <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4">
              <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3">Actions</h3>
              <div class="space-y-2">
                <%= if @bot_recipe.status == "pending_review" do %>
                  <button phx-click="approve"
                          class="w-full flex items-center justify-center gap-2 px-3 py-2 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium transition-colors">
                    <.icon name="hero-check-circle" class="h-4 w-4" /> Approve
                  </button>
                  <button phx-click="reject" data-confirm="Reject this recipe?"
                          class="w-full flex items-center justify-center gap-2 px-3 py-2 rounded-lg bg-red-600/20 hover:bg-red-600/30 text-red-400 border border-red-500/30 text-sm font-medium transition-colors">
                    <.icon name="hero-x-circle" class="h-4 w-4" /> Reject
                  </button>
                <% end %>
                <%= if @bot_recipe.status == "approved" do %>
                  <button phx-click="publish_now" data-confirm="Publish to social media now?"
                          class="w-full flex items-center justify-center gap-2 px-3 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium transition-colors">
                    <.icon name="hero-paper-airplane" class="h-4 w-4" /> Publish Now
                  </button>
                  <p class="text-xs text-slate-500 text-center">Posts to all configured social accounts</p>
                  <button phx-click="reject"
                          class="w-full flex items-center justify-center gap-2 px-3 py-2 rounded-lg text-slate-400 hover:text-white hover:bg-slate-700 text-sm transition-colors">
                    <.icon name="hero-arrow-uturn-left" class="h-4 w-4" /> Undo / Reject
                  </button>
                <% end %>
                <%= if @bot_recipe.status == "rejected" do %>
                  <button phx-click="approve"
                          class="w-full flex items-center justify-center gap-2 px-3 py-2 rounded-lg text-slate-400 hover:text-white hover:bg-slate-700 text-sm transition-colors">
                    <.icon name="hero-arrow-uturn-left" class="h-4 w-4" /> Undo / Approve
                  </button>
                <% end %>
                <%= if @bot_recipe.status == "published" do %>
                  <p class="text-xs text-slate-500 text-center py-2">This recipe has been published.</p>
                <% end %>
              </div>
            </div>

            <!-- Translations -->
            <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4">
              <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3">Translations</h3>
              <div class="space-y-1.5">
                <%= for lang <- @languages do %>
                  <div class="flex items-center justify-between bg-slate-700/40 rounded-lg px-3 py-2">
                    <div class="flex items-center gap-2">
                      <%= if lang.name in @translated_langs do %>
                        <.icon name="hero-check-badge" class="h-4 w-4 text-emerald-400 flex-shrink-0" />
                      <% else %>
                        <.icon name="hero-language" class="h-4 w-4 text-slate-500 flex-shrink-0" />
                      <% end %>
                      <span class="text-sm text-slate-200 uppercase font-medium"><%= lang.name %></span>
                    </div>
                    <div class="flex items-center gap-1">
                      <%= if lang.name in @translated_langs do %>
                        <.link navigate={~p"/professional/ai-bot/review/#{@bot_recipe.id}/translate/#{lang.name}"}
                               class="flex items-center gap-1 px-2 py-0.5 rounded text-emerald-400 hover:bg-emerald-500/10 text-xs transition-colors">
                          <.icon name="hero-pencil-square" class="h-3 w-3" /> Edit
                        </.link>
                      <% else %>
                        <button phx-click="trigger_translation" phx-value-lang={lang.name}
                                class="flex items-center gap-1 px-2 py-0.5 rounded text-slate-400 hover:text-white hover:bg-slate-600 text-xs transition-colors">
                          <.icon name="hero-cpu-chip" class="h-3 w-3" /> AI
                        </button>
                        <.link navigate={~p"/professional/ai-bot/review/#{@bot_recipe.id}/translate/#{lang.name}"}
                               class="flex items-center gap-1 px-2 py-0.5 rounded text-slate-500 hover:text-white hover:bg-slate-600 text-xs transition-colors">
                          <.icon name="hero-pencil" class="h-3 w-3" /> Manual
                        </.link>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>

            <!-- Schedule info -->
            <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4">
              <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3">Schedule</h3>
              <div class="space-y-2">
                <div class="flex items-center gap-2 text-sm">
                  <.icon name="hero-calendar-days" class="h-4 w-4 text-slate-500 flex-shrink-0" />
                  <span class="text-slate-300"><%= @bot_recipe.scheduled_date %></span>
                </div>
                <div class="flex items-center gap-2 text-sm">
                  <.icon name="hero-clock" class="h-4 w-4 text-slate-500 flex-shrink-0" />
                  <span class="text-slate-300 capitalize"><%= String.replace(@bot_recipe.meal_type, "_", " ") %></span>
                </div>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp status_banner_class("pending_review"), do: "bg-amber-500/15 text-amber-300 border border-amber-500/25"
  defp status_banner_class("approved"), do: "bg-emerald-500/15 text-emerald-300 border border-emerald-500/25"
  defp status_banner_class("rejected"), do: "bg-red-500/15 text-red-300 border border-red-500/25"
  defp status_banner_class("published"), do: "bg-blue-500/15 text-blue-300 border border-blue-500/25"
  defp status_banner_class(_), do: "bg-slate-700/40 text-slate-400 border border-slate-600/40"

  defp status_icon("pending_review"), do: "hero-clock"
  defp status_icon("approved"), do: "hero-check-circle"
  defp status_icon("rejected"), do: "hero-x-circle"
  defp status_icon("published"), do: "hero-paper-airplane"
  defp status_icon(_), do: "hero-question-mark-circle"

  defp status_label("pending_review"), do: "Pending Review"
  defp status_label("approved"), do: "Approved — ready to publish"
  defp status_label("rejected"), do: "Rejected"
  defp status_label("published"), do: "Published"
  defp status_label(s), do: s
end
