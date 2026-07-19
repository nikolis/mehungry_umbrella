defmodule MehungryWeb.AiBotLive.RecipeTranslate do
  use MehungryWeb, :live_view

  alias Mehungry.AI.Bot
  alias Mehungry.AI.Bot.RecipeTranslation
  alias Mehungry.AI.RecipeTranslator
  alias Mehungry.Food

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :translating, false)}
  end

  @impl true
  def handle_params(%{"id" => bot_recipe_id, "lang" => lang}, _url, socket) do
    bot_recipe = Bot.get_bot_recipe!(String.to_integer(bot_recipe_id))
    recipe = bot_recipe.recipe

    existing = Bot.get_recipe_translation(recipe.id, lang)
    form = build_form(existing, recipe, lang)

    ingredient_ids = Enum.map(recipe.recipe_ingredients, & &1.ingredient_id)
    unit_ids = recipe.recipe_ingredients |> Enum.map(& &1.measurement_unit_id) |> Enum.uniq()

    ing_translations = Food.ingredient_display_names(ingredient_ids, lang)
    unit_translations = Food.get_unit_translations_map(unit_ids, lang)

    unique_units =
      recipe.recipe_ingredients
      |> Enum.uniq_by(& &1.measurement_unit_id)
      |> Enum.map(& &1.measurement_unit)

    {:noreply,
     socket
     |> assign(:bot_recipe, bot_recipe)
     |> assign(:recipe, recipe)
     |> assign(:lang, lang)
     |> assign(:translation, existing)
     |> assign(:form, form)
     |> assign(:ing_translations, ing_translations)
     |> assign(:unit_translations, unit_translations)
     |> assign(:unique_units, unique_units)
     |> assign(:page_title, "Translate: #{recipe.title} → #{lang}")}
  end

  @impl true
  def handle_event("retranslate", _, socket) do
    send(self(), :do_translate)
    {:noreply, assign(socket, :translating, true)}
  end

  @impl true
  def handle_event("validate", %{"recipe_translation" => params}, socket) do
    translation = socket.assigns.translation || %RecipeTranslation{}

    form =
      Bot.change_recipe_translation(translation, params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("save_translation", %{"recipe_translation" => params}, socket) do
    recipe = socket.assigns.recipe
    lang = socket.assigns.lang

    steps = parse_steps_from_params(params, recipe.steps)

    attrs = %{
      recipe_id: recipe.id,
      language_name: lang,
      title: params["title"],
      description: params["description"],
      steps: steps
    }

    case Bot.upsert_recipe_translation(attrs) do
      {:ok, translation} ->
        {:noreply,
         socket
         |> assign(:translation, translation)
         |> assign(:form, build_form(translation, recipe, lang))
         |> put_flash(:info, "Translation saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event(
        "save_ingredient_translations",
        %{"ingredient_translations" => ing_params, "unit_translations" => unit_params},
        socket
      ) do
    lang = socket.assigns.lang

    ing_errors =
      ing_params
      |> Enum.reject(fn {_, v} -> v == "" end)
      |> Enum.flat_map(fn {id_str, name} ->
        id = String.to_integer(id_str)

        case Food.upsert_ingredient_translation(id, lang, name) do
          {:ok, _} -> []
          {:error, _} -> [id]
        end
      end)

    unit_errors =
      unit_params
      |> Enum.reject(fn {_, v} -> v == "" end)
      |> Enum.flat_map(fn {id_str, name} ->
        id = String.to_integer(id_str)

        case Food.upsert_measurement_unit_translation(id, lang, name) do
          {:ok, _} -> []
          {:error, _} -> [id]
        end
      end)

    ingredient_ids = Enum.map(socket.assigns.recipe.recipe_ingredients, & &1.ingredient_id)
    unit_ids = socket.assigns.unique_units |> Enum.map(& &1.id)

    ing_translations = Food.ingredient_display_names(ingredient_ids, lang)
    unit_translations = Food.get_unit_translations_map(unit_ids, lang)

    socket =
      socket
      |> assign(:ing_translations, ing_translations)
      |> assign(:unit_translations, unit_translations)

    if ing_errors == [] and unit_errors == [] do
      {:noreply, put_flash(socket, :info, "Ingredient & unit translations saved.")}
    else
      {:noreply, put_flash(socket, :error, "Some translations could not be saved.")}
    end
  end

  def handle_event("save_ingredient_translations", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(:do_translate, socket) do
    recipe = socket.assigns.recipe
    lang = socket.assigns.lang

    result = RecipeTranslator.translate_recipe(recipe, lang)

    case result do
      {:ok, %{title: title, description: description, steps: steps}} ->
        existing = socket.assigns.translation

        prefilled =
          (existing || %RecipeTranslation{recipe_id: recipe.id, language_name: lang})
          |> Map.put(:title, title)
          |> Map.put(:description, description)
          |> Map.put(:steps, steps)

        form =
          Bot.change_recipe_translation(prefilled, %{
            recipe_id: recipe.id,
            language_name: lang,
            title: title,
            description: description,
            steps: steps
          })
          |> to_form()

        {:noreply,
         socket
         |> assign(:form, form)
         |> assign(:translating, false)
         |> put_flash(:info, "AI translation loaded — review and save.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:translating, false)
         |> put_flash(:error, "Translation failed: #{inspect(reason)}")}
    end
  end

  defp parse_steps_from_params(%{"steps" => steps_params}, original_steps)
       when is_map(steps_params) do
    original_steps
    |> Enum.with_index()
    |> Enum.map(fn {_step, idx} ->
      desc = get_in(steps_params, [to_string(idx)]) || ""
      %{"index" => idx, "description" => desc}
    end)
  end

  defp parse_steps_from_params(_params, _steps), do: []

  defp build_form(nil, recipe, lang) do
    %RecipeTranslation{recipe_id: recipe.id, language_name: lang}
    |> Bot.change_recipe_translation()
    |> to_form()
  end

  defp build_form(translation, _recipe, _lang) do
    Bot.change_recipe_translation(translation)
    |> to_form()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <!-- Header -->
      <div class="flex items-center gap-3 mb-5">
        <.link
          navigate={~p"/professional/ai-bot/review/#{@bot_recipe.id}"}
          class="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition-colors"
        >
          <.icon name="hero-arrow-left" class="h-5 w-5" />
        </.link>
        <div class="flex-1 flex items-center gap-2">
          <span class="inline-flex items-center px-2 py-0.5 rounded-md bg-slate-700 text-slate-300 text-xs font-semibold uppercase">EN</span>
          <.icon name="hero-arrow-right" class="h-3.5 w-3.5 text-slate-500" />
          <span class="inline-flex items-center px-2 py-0.5 rounded-md bg-primary-600/30 text-primary-300 text-xs font-semibold uppercase border border-primary-500/30">{@lang}</span>
          <h1 class="text-base font-semibold text-white ml-1 truncate">{@recipe.title}</h1>
        </div>
        <button
          phx-click="retranslate"
          disabled={@translating}
          class="flex items-center gap-1.5 px-3 py-2 rounded-lg bg-slate-800 hover:bg-slate-700 border border-slate-700/60 text-slate-300 hover:text-white text-sm transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <%= if @translating do %>
            <svg class="animate-spin h-4 w-4" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4">
              </circle>
              <path
                class="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
              >
              </path>
            </svg>
            Translating…
          <% else %>
            <.icon name="hero-cpu-chip" class="h-4 w-4" /> AI Translate
          <% end %>
        </button>
      </div>

      <div class="grid grid-cols-2 gap-5">
        <!-- Original (read-only) -->
        <div class="space-y-3">
          <div class="flex items-center gap-2">
            <span class="text-xs font-semibold text-slate-500 uppercase tracking-wider">Original</span>
            <span class="inline-flex items-center px-1.5 py-0.5 rounded bg-slate-700 text-slate-400 text-[10px] font-bold">EN</span>
          </div>
          <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4">
            <div class="font-semibold text-white text-sm mb-2">{@recipe.title}</div>
            <p class="text-slate-300 text-sm leading-relaxed">{@recipe.description}</p>
          </div>
          <%= if @recipe.steps && @recipe.steps != [] do %>
            <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4">
              <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3">
                Steps
              </h3>
              <ol class="space-y-3">
                <%= for {step, i} <- Enum.with_index(@recipe.steps) do %>
                  <li class="flex gap-3">
                    <span class="flex-shrink-0 w-5 h-5 rounded-full bg-slate-700 text-slate-400 text-[10px] font-bold flex items-center justify-center mt-0.5">
                      {i + 1}
                    </span>
                    <p class="text-sm text-slate-300 leading-relaxed">{step.description}</p>
                  </li>
                <% end %>
              </ol>
            </div>
          <% end %>
        </div>

        <!-- Translation form -->
        <div class="space-y-3">
          <div class="flex items-center gap-2">
            <span class="text-xs font-semibold text-slate-500 uppercase tracking-wider">Translation</span>
            <span class="inline-flex items-center px-1.5 py-0.5 rounded bg-primary-600/30 text-primary-300 border border-primary-500/30 text-[10px] font-bold uppercase">{@lang}</span>
          </div>
          <.form for={@form} phx-change="validate" phx-submit="save_translation" class="space-y-3">
            <input type="hidden" name="recipe_translation[recipe_id]" value={@recipe.id} />
            <input type="hidden" name="recipe_translation[language_name]" value={@lang} />

            <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4 space-y-3">
              <div>
                <label class="block text-xs text-slate-500 mb-1">Title</label>
                <.input
                  field={@form[:title]}
                  type="text"
                  class="w-full bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-2 focus:border-primary-500 focus:outline-none"
                />
              </div>
              <div>
                <label class="block text-xs text-slate-500 mb-1">Description</label>
                <textarea
                  name="recipe_translation[description]"
                  class="w-full bg-slate-700 border border-slate-600 rounded-lg text-slate-200 text-sm px-3 py-2 focus:border-primary-500 focus:outline-none resize-none"
                  rows="5"
                ><%= Phoenix.HTML.Form.input_value(@form, :description) %></textarea>
              </div>
            </div>

            <%= if @recipe.steps && @recipe.steps != [] do %>
              <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4">
                <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3">
                  Steps
                </h3>
                <div class="space-y-3">
                  <%= for {step, i} <- Enum.with_index(@recipe.steps) do %>
                    <div>
                      <label class="flex items-center gap-1.5 text-xs text-slate-500 mb-1">
                        <span class="w-4 h-4 rounded-full bg-slate-700 text-slate-400 text-[10px] font-bold flex items-center justify-center flex-shrink-0">{i +
                          1}</span>
                        Step {i + 1}
                      </label>
                      <textarea
                        name={"recipe_translation[steps][#{i}]"}
                        rows="3"
                        class="w-full bg-slate-700 border border-slate-600 rounded-lg text-slate-200 text-sm px-3 py-2 focus:border-primary-500 focus:outline-none resize-none"
                        placeholder={step.description}
                      ><%= get_step_translation(@form, i) %></textarea>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <div class="sticky bottom-0 bg-slate-900 pt-2 pb-1">
              <button
                type="submit"
                class="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium transition-colors"
              >
                <.icon name="hero-check" class="h-4 w-4" /> Save Translation
              </button>
            </div>
          </.form>
        </div>
      </div>

      <!-- Ingredients & Units translation -->
      <.form for={%{}} phx-submit="save_ingredient_translations" class="mt-6 space-y-4">
        <div class="flex items-center gap-2 mb-1">
          <.icon name="hero-beaker" class="h-4 w-4 text-slate-500" />
          <span class="text-xs font-semibold text-slate-400 uppercase tracking-wider">Ingredients & Units</span>
        </div>

        <!-- Ingredients -->
        <div class="grid grid-cols-2 gap-5">
          <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4">
            <div class="flex items-center gap-2 mb-3">
              <span class="text-xs font-semibold text-slate-500 uppercase tracking-wider">Ingredient</span>
              <span class="inline-flex items-center px-1.5 py-0.5 rounded bg-slate-700 text-slate-400 text-[10px] font-bold">EN</span>
            </div>
            <ul class="space-y-2">
              <%= for ri <- @recipe.recipe_ingredients do %>
                <li class="flex items-center gap-2 text-sm py-1 border-b border-slate-700/40 last:border-0">
                  <span class="text-slate-200 flex-1">{ri.ingredient.name}</span>
                </li>
              <% end %>
            </ul>
          </div>

          <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4">
            <div class="flex items-center gap-2 mb-3">
              <span class="text-xs font-semibold text-slate-500 uppercase tracking-wider">Ingredient</span>
              <span class="inline-flex items-center px-1.5 py-0.5 rounded bg-primary-600/30 text-primary-300 border border-primary-500/30 text-[10px] font-bold uppercase">{@lang}</span>
            </div>
            <ul class="space-y-2">
              <%= for ri <- @recipe.recipe_ingredients do %>
                <li class="py-1 border-b border-slate-700/40 last:border-0">
                  <input
                    type="text"
                    name={"ingredient_translations[#{ri.ingredient_id}]"}
                    value={Map.get(@ing_translations, ri.ingredient_id, "")}
                    placeholder={ri.ingredient.name}
                    class="w-full bg-slate-700 border border-slate-600 rounded-lg text-slate-200 text-sm px-3 py-1.5 focus:border-primary-500 focus:outline-none"
                  />
                </li>
              <% end %>
            </ul>
          </div>
        </div>

        <!-- Units -->
        <div class="grid grid-cols-2 gap-5">
          <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4">
            <div class="flex items-center gap-2 mb-3">
              <span class="text-xs font-semibold text-slate-500 uppercase tracking-wider">Measurement Unit</span>
              <span class="inline-flex items-center px-1.5 py-0.5 rounded bg-slate-700 text-slate-400 text-[10px] font-bold">EN</span>
            </div>
            <ul class="space-y-2">
              <%= for unit <- @unique_units do %>
                <li class="flex items-center gap-2 text-sm py-1 border-b border-slate-700/40 last:border-0">
                  <span class="text-slate-200 flex-1">{unit.name}</span>
                </li>
              <% end %>
            </ul>
          </div>

          <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4">
            <div class="flex items-center gap-2 mb-3">
              <span class="text-xs font-semibold text-slate-500 uppercase tracking-wider">Measurement Unit</span>
              <span class="inline-flex items-center px-1.5 py-0.5 rounded bg-primary-600/30 text-primary-300 border border-primary-500/30 text-[10px] font-bold uppercase">{@lang}</span>
            </div>
            <ul class="space-y-2">
              <%= for unit <- @unique_units do %>
                <li class="py-1 border-b border-slate-700/40 last:border-0">
                  <input
                    type="text"
                    name={"unit_translations[#{unit.id}]"}
                    value={Map.get(@unit_translations, unit.id, "")}
                    placeholder={unit.name}
                    class="w-full bg-slate-700 border border-slate-600 rounded-lg text-slate-200 text-sm px-3 py-1.5 focus:border-primary-500 focus:outline-none"
                  />
                </li>
              <% end %>
            </ul>
          </div>
        </div>

        <button
          type="submit"
          class="flex items-center gap-2 px-4 py-2.5 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium transition-colors"
        >
          <.icon name="hero-check" class="h-4 w-4" /> Save Ingredient & Unit Translations
        </button>
      </.form>
    </div>
    """
  end

  defp get_step_translation(form, index) do
    steps = Phoenix.HTML.Form.input_value(form, :steps) || []

    case Enum.find(steps, fn s ->
           (Map.get(s, "index") || Map.get(s, :index)) == index
         end) do
      nil -> ""
      step -> Map.get(step, "description") || Map.get(step, :description) || ""
    end
  end
end
