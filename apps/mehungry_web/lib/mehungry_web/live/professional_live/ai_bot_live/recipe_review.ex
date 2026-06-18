defmodule MehungryWeb.AiBotLive.RecipeReview do
  use MehungryWeb, :live_view

  alias Mehungry.{AiBot, Languages, Food, Accounts}
  alias Mehungry.Food.Recipe
  alias Mehungry.Api.Pinterest
  alias Mehungry.ObanWorkers.{RecipeTranslationWorker, RecipePublishWorker}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:bot_recipe, nil)
     |> assign(:editing, false)
     |> assign(:f, nil)
     |> assign(:changeset, nil)
     |> assign(:measurement_units, nil)
     |> assign(:show_publish_modal, false)
     |> assign(:publish_modal_data, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    bot_recipe = AiBot.get_bot_recipe!(String.to_integer(id))
    translations = AiBot.list_translations_for_recipe(bot_recipe.recipe.id)
    languages = Languages.list_languages()
    translated_langs = Enum.map(translations, & &1.language_name)

    changeset = Food.change_recipe(bot_recipe.recipe) |> struct!(action: :validate)

    {:noreply,
     socket
     |> assign(:bot_recipe, bot_recipe)
     |> assign(:recipe, bot_recipe.recipe)
     |> assign(:f, to_form(changeset))
     |> assign(:changeset, changeset)
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
      bot_user = Accounts.get_user!(config.bot_user_id)
      boards = Pinterest.get_boards(bot_user)

      lang_times = get_in(config.publish_times, [bot_recipe.meal_type]) || %{}
      languages = if map_size(lang_times) > 0, do: Map.keys(lang_times), else: ["en"]

      facebook_pages =
        (bot_user.facebook_token || %{})
        |> Enum.map(fn {name, page} -> %{name: name, id: page["id"]} end)

      instagram_connected = map_non_empty?(bot_user.instagram_token)
      facebook_connected = map_non_empty?(bot_user.facebook_token)
      pinterest_connected = map_non_empty?(bot_user.pinterest_token) and boards != []

      defaults =
        Map.new(languages, fn lang ->
          fb_page_id =
            get_in(config.facebook_page_ids || %{}, [lang]) ||
              (List.first(facebook_pages) && List.first(facebook_pages).id)

          pt_board_id =
            get_in(config.pinterest_board_ids || %{}, [lang]) ||
              (List.first(boards) && List.first(boards)["id"])

          {lang,
           %{
             instagram: instagram_connected,
             facebook: facebook_connected and not is_nil(get_in(config.facebook_page_ids || %{}, [lang])),
             facebook_page_id: fb_page_id,
             pinterest: pinterest_connected and not is_nil(get_in(config.pinterest_board_ids || %{}, [lang])),
             pinterest_board_id: pt_board_id
           }}
        end)

      {:noreply,
       socket
       |> assign(:show_publish_modal, true)
       |> assign(:publish_modal_data, %{
         languages: languages,
         instagram_connected: instagram_connected,
         facebook_connected: facebook_connected,
         pinterest_connected: pinterest_connected,
         facebook_pages: facebook_pages,
         pinterest_boards: boards,
         defaults: defaults
       })}
    end
  end

  @impl true
  def handle_event("close_publish_modal", _, socket) do
    {:noreply, assign(socket, :show_publish_modal, false)}
  end

  @impl true
  def handle_event("confirm_publish", %{"publish" => publish_params}, socket) do
    bot_recipe = socket.assigns.bot_recipe

    jobs_inserted =
      Enum.reduce(publish_params, 0, fn {lang, platform_params}, count ->
        platforms =
          ["instagram", "facebook", "pinterest"]
          |> Enum.filter(&(Map.get(platform_params, &1) == "true"))

        if platforms == [] do
          count
        else
          args = %{
            ai_bot_recipe_id: bot_recipe.id,
            language_name: lang,
            platforms: platforms,
            facebook_page_id: Map.get(platform_params, "facebook_page_id"),
            pinterest_board_id: Map.get(platform_params, "pinterest_board_id")
          }

          case RecipePublishWorker.new(args) |> Oban.insert() do
            {:ok, _} -> count + 1
            _ -> count
          end
        end
      end)

    {:noreply,
     socket
     |> assign(:show_publish_modal, false)
     |> put_flash(:info, "Publish jobs queued for #{jobs_inserted} language(s) — check social media shortly.")}
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
  def handle_event("toggle_edit", _, socket) do
    {:noreply, assign(socket, :editing, !socket.assigns.editing)}
  end

  @impl true
  def handle_event("validate", %{"recipe" => recipe_params}, socket) do
    changeset =
      socket.assigns.recipe
      |> Food.change_recipe(recipe_params)
      |> struct!(action: :validate)

    {:noreply, socket |> assign(:f, to_form(changeset)) |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("add_ingredient", _params, socket) do
    add_ingredient(socket, socket.assigns.f.params || %{})
  end

  @impl true
  def handle_event("add-step", _, socket) do
    existing = Ecto.Changeset.get_embed(socket.assigns.changeset, :steps)

    changeset =
      socket.assigns.changeset
      |> Ecto.Changeset.put_embed(:steps, existing ++ [%{temp_id: get_temp_id()}])

    {:noreply, socket |> assign(:changeset, changeset) |> assign(:f, to_form(changeset))}
  end

  @impl true
  def handle_event("remove-ingredient", %{"temp_id" => remove_id}, socket) do
    {_progress, recipe_ingredients} = remove_from_change(socket, remove_id)

    changeset =
      socket.assigns.changeset
      |> Ecto.Changeset.put_assoc(:recipe_ingredients, recipe_ingredients)

    {:noreply, socket |> assign(:changeset, changeset) |> assign(:f, to_form(changeset))}
  end

  @impl true
  def handle_event("remove-step", %{"temp_id" => remove_id}, socket) do
    {_progress, steps} = remove_from_change_step(socket, remove_id)

    changeset =
      socket.assigns.changeset
      |> Ecto.Changeset.put_embed(:steps, steps)

    {:noreply, socket |> assign(:changeset, changeset) |> assign(:f, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"recipe" => recipe_params}, socket) do
    case recipe_params["_action"] do
      "add_ingredient" -> add_ingredient(socket, recipe_params)
      "add_step" -> add_step(socket, recipe_params)
      "remove_ingredient:" <> index -> remove_ingredient(socket, recipe_params, index)
      "remove_step:" <> index -> remove_step(socket, recipe_params, index)
      _ -> save_recipe(socket, recipe_params)
    end
  end

  @impl true
  def handle_info({:select_id, id, component_id}, socket) do
    send_update(MehungryWeb.IngredientComponent, id: component_id, new_ingredient_id: id)
    {:noreply, socket}
  end

  # ── form helpers ──────────────────────────────────────────────────────────────

  defp add_ingredient(socket, params) do
    ingredients = Map.get(params, "recipe_ingredients", %{})
    updated = Map.put(ingredients, "#{map_size(ingredients)}", %{})
    rebuild_form(socket, Map.put(params, "recipe_ingredients", updated))
  end

  defp remove_ingredient(socket, params, index) do
    portions = Map.get(params, "recipe_ingredients", %{}) |> Map.delete(index)
    rebuild_form(socket, Map.put(params, "recipe_ingredients", portions))
  end

  defp add_step(socket, params) do
    steps = Map.get(params, "steps", %{})
    updated = Map.put(steps, "#{map_size(steps)}", %{})
    rebuild_form(socket, Map.put(params, "steps", updated))
  end

  defp remove_step(socket, params, index) do
    steps = Map.get(params, "steps", %{}) |> Map.delete(index)
    rebuild_form(socket, Map.put(params, "steps", steps))
  end

  defp rebuild_form(socket, params) do
    changeset =
      socket.assigns.recipe
      |> Food.change_recipe(params)
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:f, to_form(changeset)) |> assign(:changeset, changeset)}
  end

  defp save_recipe(socket, recipe_params) do
    recipe_params = filter_empty_steps(recipe_params)

    case Food.update_recipe(socket.assigns.recipe, recipe_params) do
      {:ok, %Recipe{}} ->
        bot_recipe = AiBot.get_bot_recipe!(socket.assigns.bot_recipe.id)
        changeset = Food.change_recipe(bot_recipe.recipe) |> struct!(action: :validate)

        {:noreply,
         socket
         |> assign(:bot_recipe, bot_recipe)
         |> assign(:recipe, bot_recipe.recipe)
         |> assign(:f, to_form(changeset))
         |> assign(:changeset, changeset)
         |> assign(:editing, false)
         |> put_flash(:info, "Recipe saved.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(:f, to_form(changeset)) |> assign(:changeset, changeset)}
    end
  end

  defp remove_from_change(socket, remove_id) do
    case Map.get(socket.assigns.changeset.changes, :recipe_ingredients, nil) do
      nil ->
        {:repeat, []}

      changes ->
        original = length(changes)
        filtered = Enum.reject(changes, fn %{changes: ri} -> Map.get(ri, :temp_id) == remove_id end)
        if length(filtered) == original, do: {:repeat, filtered}, else: {:ok, filtered}
    end
  end

  defp remove_from_change_step(socket, remove_id) do
    case Map.get(socket.assigns.changeset.changes, :steps, nil) do
      nil ->
        {:repeat, []}

      changes ->
        original = length(changes)
        filtered = Enum.reject(changes, fn %{changes: s} -> Map.get(s, :temp_id) == remove_id end)
        if length(filtered) == original, do: {:repeat, filtered}, else: {:ok, filtered}
    end
  end

  defp filter_empty_steps(recipe_params) do
    steps = Map.get(recipe_params, "steps", %{})
    filtered = Enum.reject(steps, fn {_, v} -> is_nil(v["description"]) or v["description"] == "" end) |> Map.new()
    Map.put(recipe_params, "steps", filtered)
  end

  defp get_temp_id, do: :crypto.strong_rand_bytes(5) |> Base.url_encode64() |> binary_part(0, 5)

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
          <!-- Recipe preview / edit -->
          <div class="col-span-2 space-y-4">
            <!-- Edit toggle header -->
            <div class="flex items-center justify-end">
              <button phx-click="toggle_edit"
                      class={[
                        "flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-colors",
                        if(@editing,
                          do: "bg-slate-700 text-white",
                          else: "text-slate-400 hover:text-white hover:bg-slate-700")
                      ]}>
                <.icon name={if @editing, do: "hero-eye", else: "hero-pencil-square"} class="h-3.5 w-3.5" />
                <%= if @editing, do: "View", else: "Edit" %>
              </button>
            </div>

            <%= if @editing do %>
              <!-- Edit form -->
              <form phx-change="validate" phx-submit="save" class="space-y-4">
                <input type="hidden" name="recipe[_action]" value="" />

                <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4 space-y-3">
                  <.input field={@f[:title]} type="text" label="Title" />
                  <.input field={@f[:description]} type="text" label="Description" />
                  <div class="grid grid-cols-2 gap-3">
                    <.input field={@f[:cooking_time_lower_limit]} type="number_subscript" subscript="mins" label="Cooking time" />
                    <.input field={@f[:preperation_time_lower_limit]} type="number_subscript" subscript="mins" label="Prep time" />
                  </div>
                  <div class="grid grid-cols-2 gap-3">
                    <.input field={@f[:servings]} type="text" label="Servings" />
                    <.input field={@f[:difficulty]} type="select" options={[Easy: "1", Medium: "2", Difficult: "3"]} />
                  </div>
                </div>

                <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4">
                  <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3">Ingredients</h3>
                  <div class="space-y-1">
                    <.inputs_for :let={ingredient_form} field={@f[:recipe_ingredients]}>
                      <.live_component
                        module={MehungryWeb.IngredientComponent}
                        id={"review_ingredient_" <> Integer.to_string(ingredient_form.index)}
                        f={@f}
                        ingredient_form={ingredient_form}
                        ingredients={[]}
                        measurement_units={@measurement_units}
                        search_language="en"
                      />
                    </.inputs_for>
                  </div>
                  <button type="button" phx-click="add_ingredient"
                          class="mt-3 px-3 py-1.5 bg-primary-500 hover:bg-primary-600 rounded-lg text-white text-xs font-semibold transition-colors">
                    + Add Ingredient
                  </button>
                </div>

                <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4">
                  <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3">Steps</h3>
                  <.live_component module={MehungryWeb.StepComponent} id="review_recipe_steps" f={@f} />
                </div>

                <div class="flex items-center gap-3">
                  <button type="submit"
                          class="px-5 py-2 bg-primary-500 hover:bg-primary-600 text-white rounded-lg text-sm font-semibold transition-colors">
                    Save Changes
                  </button>
                  <button type="button" phx-click="toggle_edit"
                          class="px-5 py-2 border border-slate-600 text-slate-300 rounded-lg text-sm font-medium hover:border-slate-400 hover:text-white transition-colors">
                    Cancel
                  </button>
                </div>
              </form>
            <% else %>
              <!-- Read-only view -->
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

              <%= if @recipe.nutrients && map_size(@recipe.nutrients) > 0 do %>
                <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4">
                  <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3">Nutrition Facts</h3>
                  <MehungryWeb.NutritionAccordion.nutrition_accordion
                    nutrients={@recipe.nutrients}
                    title="Nutrition Facts"
                    max_height="600px"
                    show_title={false}
                  />
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
                  <button phx-click="publish_now"
                          class="w-full flex items-center justify-center gap-2 px-3 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium transition-colors">
                    <.icon name="hero-paper-airplane" class="h-4 w-4" /> Publish Now…
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

      <!-- Publish modal -->
      <.modal :if={@show_publish_modal} id="publish-modal" show
              on_cancel={JS.push("close_publish_modal")}>
        <h3 class="text-base font-semibold text-white mb-1">Publish Recipe</h3>
        <p class="text-sm text-slate-400 mb-5">Choose which platforms and pages to publish to for each language.</p>

        <%= if @publish_modal_data do %>
          <form phx-submit="confirm_publish" class="space-y-5">
            <%= for {lang, idx} <- Enum.with_index(@publish_modal_data.languages) do %>
              <% defaults = Map.get(@publish_modal_data.defaults, lang, %{}) %>
              <div class={["space-y-2", if(idx > 0, do: "pt-5 border-t border-slate-700/40")]}
                   x-data={publish_xdata(defaults)}>
                <span class="inline-flex items-center px-2 py-0.5 rounded-md bg-slate-700 text-slate-300 text-xs font-bold uppercase mb-1">
                  <%= lang %>
                </span>

                <%= if @publish_modal_data.instagram_connected do %>
                  <div class="flex items-center gap-3 py-1.5">
                    <input type="hidden" name={"publish[#{lang}][instagram]"} x-bind:value="instagram ? 'true' : 'false'" />
                    <input type="checkbox" id={"ig_#{lang}"} x-model="instagram"
                           class="w-4 h-4 rounded border-slate-600 bg-slate-700 text-primary-500 focus:ring-primary-500" />
                    <label for={"ig_#{lang}"} class="flex items-center gap-2 text-sm text-slate-200 cursor-pointer select-none">
                      <span>📸</span> Instagram
                    </label>
                  </div>
                <% end %>

                <%= if @publish_modal_data.facebook_connected do %>
                  <div class="py-1.5">
                    <div class="flex items-center gap-3 mb-2">
                      <input type="hidden" name={"publish[#{lang}][facebook]"} x-bind:value="facebook ? 'true' : 'false'" />
                      <input type="checkbox" id={"fb_#{lang}"} x-model="facebook"
                             class="w-4 h-4 rounded border-slate-600 bg-slate-700 text-primary-500 focus:ring-primary-500" />
                      <label for={"fb_#{lang}"} class="flex items-center gap-2 text-sm text-slate-200 cursor-pointer select-none">
                        <span>📘</span> Facebook
                      </label>
                    </div>
                    <div x-show="facebook" class="ml-7">
                      <select name={"publish[#{lang}][facebook_page_id]"}
                              class="w-full bg-slate-700 border border-slate-600 rounded-lg text-slate-200 text-sm px-3 py-1.5 focus:border-primary-500 focus:outline-none">
                        <%= for page <- @publish_modal_data.facebook_pages do %>
                          <option value={page.id} selected={defaults[:facebook_page_id] == page.id}>
                            <%= page.name %>
                          </option>
                        <% end %>
                      </select>
                    </div>
                  </div>
                <% end %>

                <%= if @publish_modal_data.pinterest_connected do %>
                  <div class="py-1.5">
                    <div class="flex items-center gap-3 mb-2">
                      <input type="hidden" name={"publish[#{lang}][pinterest]"} x-bind:value="pinterest ? 'true' : 'false'" />
                      <input type="checkbox" id={"pt_#{lang}"} x-model="pinterest"
                             class="w-4 h-4 rounded border-slate-600 bg-slate-700 text-primary-500 focus:ring-primary-500" />
                      <label for={"pt_#{lang}"} class="flex items-center gap-2 text-sm text-slate-200 cursor-pointer select-none">
                        <span>📌</span> Pinterest
                      </label>
                    </div>
                    <div x-show="pinterest" class="ml-7">
                      <select name={"publish[#{lang}][pinterest_board_id]"}
                              class="w-full bg-slate-700 border border-slate-600 rounded-lg text-slate-200 text-sm px-3 py-1.5 focus:border-primary-500 focus:outline-none">
                        <%= for board <- @publish_modal_data.pinterest_boards do %>
                          <option value={board["id"]} selected={defaults[:pinterest_board_id] == board["id"]}>
                            <%= board["name"] %>
                          </option>
                        <% end %>
                      </select>
                    </div>
                  </div>
                <% end %>

                <%= if not @publish_modal_data.instagram_connected and not @publish_modal_data.facebook_connected and not @publish_modal_data.pinterest_connected do %>
                  <p class="text-xs text-slate-500 py-2">No social accounts connected — configure them in Bot Social Accounts.</p>
                <% end %>
              </div>
            <% end %>

            <div class="flex gap-2 pt-3 border-t border-slate-700/40">
              <button type="submit"
                      class="flex items-center gap-2 px-4 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium transition-colors">
                <.icon name="hero-paper-airplane" class="h-4 w-4" /> Publish
              </button>
              <button type="button" phx-click="close_publish_modal"
                      class="px-4 py-2 rounded-lg text-slate-400 hover:text-white hover:bg-slate-700 text-sm transition-colors">
                Cancel
              </button>
            </div>
          </form>
        <% end %>
      </.modal>
    </div>
    """
  end

  defp publish_xdata(defaults) do
    instagram = if defaults[:instagram], do: "true", else: "false"
    facebook = if defaults[:facebook], do: "true", else: "false"
    pinterest = if defaults[:pinterest], do: "true", else: "false"
    "{instagram: #{instagram}, facebook: #{facebook}, pinterest: #{pinterest}}"
  end

  defp map_non_empty?(map) when is_map(map) and map_size(map) > 0, do: true
  defp map_non_empty?(_), do: false

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
