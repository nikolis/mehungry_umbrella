defmodule MehungryWeb.AiBotLive.Setups do
  @moduledoc """
  Admin CRUD for recipe setups — a named bundle of persona + origin + story +
  optional condition + seed ingredients (with roles). Consumed by monthly
  configs and by ad-hoc recipe orders.
  """
  use MehungryWeb, :live_view

  alias Mehungry.{Food, Health}
  alias Mehungry.AI.Bot
  alias Mehungry.AI.Bot.RecipeSetup
  alias Mehungry.AI.Bot.RecipeSetupIngredient

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:setups, Bot.list_recipe_setups())
     |> assign(:personas, Bot.list_active_personas())
     |> assign(:conditions, Health.list_conditions_for_presentation())
     |> assign(:roles, RecipeSetupIngredient.roles())
     |> assign(:form, nil)
     |> assign(:setup, nil)
     |> assign(:seed_ingredients, [])
     |> assign(:ingredient_form, to_form(%{"name" => "", "role" => "primary"}))
     |> assign(:page_title, "AI Bot Setups")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket |> assign(:form, nil) |> assign(:setup, nil) |> assign(:seed_ingredients, [])
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:form, to_form(Bot.change_recipe_setup(%RecipeSetup{})))
    |> assign(:setup, nil)
    |> assign(:seed_ingredients, [])
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    setup = Bot.get_recipe_setup!(id)

    socket
    |> assign(:form, to_form(Bot.change_recipe_setup(setup)))
    |> assign(:setup, setup)
    |> assign(:seed_ingredients, Bot.list_setup_ingredients(setup.id))
  end

  @impl true
  def handle_event("validate", %{"recipe_setup" => params}, socket) do
    data = (socket.assigns.setup || %RecipeSetup{})
    {:noreply, assign(socket, :form, to_form(Bot.change_recipe_setup(data, params), action: :validate))}
  end

  def handle_event("save", %{"recipe_setup" => params}, socket) do
    result =
      case socket.assigns.live_action do
        :new -> Bot.create_recipe_setup(params)
        :edit -> Bot.update_recipe_setup(socket.assigns.setup, params)
      end

    case result do
      {:ok, setup} ->
        {:noreply,
         socket
         |> assign(:setups, Bot.list_recipe_setups())
         |> put_flash(:info, "Setup saved.")
         |> push_patch(to: ~p"/professional/ai-bot/setups/#{setup.id}/edit")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    socket =
      case id |> Bot.get_recipe_setup!() |> Bot.delete_recipe_setup() do
        {:ok, _setup} ->
          socket
          |> assign(:setups, Bot.list_recipe_setups())
          |> put_flash(:info, "Setup deleted.")

        {:error, _reason} ->
          put_flash(socket, :error, "Could not delete this setup — it is still in use.")
      end

    {:noreply, socket}
  end

  def handle_event("add_ingredient", %{"name" => name, "role" => role}, socket)
      when is_binary(name) do
    setup = socket.assigns.setup

    case String.trim(name) do
      "" ->
        {:noreply, socket}

      query ->
        case Food.IngredientSearch.search(query) do
          [ingredient | _] ->
            Bot.add_setup_ingredient(%{
              recipe_setup_id: setup.id,
              ingredient_id: ingredient.id,
              role: role
            })

            {:noreply,
             socket
             |> assign(:seed_ingredients, Bot.list_setup_ingredients(setup.id))
             |> assign(:ingredient_form, to_form(%{"name" => "", "role" => role}))}

          [] ->
            {:noreply, put_flash(socket, :error, "No ingredient found for \"#{query}\".")}
        end
    end
  end

  def handle_event("remove_ingredient", %{"id" => id}, socket) do
    id |> Bot.get_setup_ingredient!() |> Bot.delete_setup_ingredient()

    {:noreply,
     assign(socket, :seed_ingredients, Bot.list_setup_ingredients(socket.assigns.setup.id))}
  end

  def handle_event("populate_from_condition", _params, socket) do
    {:ok, count} = Bot.populate_setup_ingredients_from_condition(socket.assigns.setup)

    socket = assign(socket, :seed_ingredients, Bot.list_setup_ingredients(socket.assigns.setup.id))

    socket =
      if count == 0 do
        put_flash(
          socket,
          :error,
          "No ingredients derived from this condition — it has no encouraged/discouraged " <>
            "compounds wired to curated species yet, so the condition will have no effect on " <>
            "generation. Add seed ingredients manually or wire up the condition's compounds first."
        )
      else
        put_flash(socket, :info, "Added #{count} ingredient(s) from the condition.")
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="text-xl font-bold text-white">Recipe Setups</h1>
        <p class="text-sm text-slate-400 mt-0.5">
          A persona + place + ingredients + optional condition. Attach to a monthly config
          or <.link navigate={~p"/professional/ai-bot/orders"} class="text-primary-400 hover:underline">order recipes</.link> against it.
        </p>
      </div>
      <div class="flex items-center gap-2">
        <.link
          navigate={~p"/professional/ai-bot/personas"}
          class="flex items-center gap-1.5 px-3 py-2 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 border border-slate-700/60 text-sm transition-colors"
        >
          <.icon name="hero-user-circle" class="h-4 w-4" /> Personas
        </.link>
        <.link
          patch={~p"/professional/ai-bot/setups/new"}
          class="flex items-center gap-1 px-3 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium transition-colors"
        >
          <.icon name="hero-plus" class="h-4 w-4" /> New Setup
        </.link>
      </div>
    </div>

    <div class="flex gap-6">
      <div class="w-80 flex-shrink-0 space-y-2">
        <div
          :for={setup <- @setups}
          class="bg-slate-800 border border-slate-700/60 rounded-xl p-4 group"
        >
          <div class="font-semibold text-white text-sm">{setup.name}</div>
          <div class="text-xs text-slate-400 mt-0.5">
            {(setup.persona && setup.persona.name) || "No persona"}
            <span :if={setup.origin}>· {setup.origin}</span>
          </div>
          <div class="flex gap-1 mt-3 opacity-0 group-hover:opacity-100 transition-opacity">
            <.link
              patch={~p"/professional/ai-bot/setups/#{setup.id}/edit"}
              class="flex items-center gap-1 px-2 py-1 rounded-md text-slate-400 hover:text-white hover:bg-slate-700 text-xs transition-colors"
            >
              <.icon name="hero-pencil-square" class="h-3.5 w-3.5" /> Edit
            </.link>
            <button
              phx-click="delete"
              phx-value-id={setup.id}
              data-confirm="Delete this setup?"
              class="flex items-center gap-1 px-2 py-1 rounded-md text-slate-400 hover:text-red-400 hover:bg-red-500/10 text-xs transition-colors"
            >
              <.icon name="hero-trash" class="h-3.5 w-3.5" /> Delete
            </button>
          </div>
        </div>
        <p :if={@setups == []} class="text-sm text-slate-500">No setups yet.</p>
      </div>

      <div :if={@form} class="flex-1 min-w-0 space-y-6">
        <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-6">
          <h2 class="text-base font-semibold text-white mb-5">
            {if @live_action == :new, do: "New Setup", else: "Edit Setup"}
          </h2>
          <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
            <div>
              <label class="block text-xs text-slate-400 mb-1">Name</label>
              <.input field={@form[:name]} type="text" placeholder="e.g. Grandma from Rethymno" class={input_class()} />
            </div>
            <div>
              <label class="block text-xs text-slate-400 mb-1">Persona</label>
              <.input
                field={@form[:persona_id]}
                type="select"
                prompt="No persona (generic voice)…"
                options={Enum.map(@personas, &{&1.name, &1.id})}
                class={input_class()}
              />
            </div>
            <div>
              <label class="block text-xs text-slate-400 mb-1">Cuisine</label>
              <.input field={@form[:cuisine]} type="text" placeholder="e.g. Greek, Sicilian, Oaxacan — the single most important constraint" class={input_class()} />
              <p class="text-[11px] text-slate-500 mt-1">Drives ingredient coherence and the cover-image style. Leave blank to derive it from the origin.</p>
            </div>
            <div>
              <label class="block text-xs text-slate-400 mb-1">Origin (free text)</label>
              <.input field={@form[:origin]} type="text" placeholder="e.g. Rethymno -> Crete -> Greece" class={input_class()} />
            </div>
            <div>
              <label class="block text-xs text-slate-400 mb-1">Story (optional)</label>
              <.input field={@form[:story]} type="textarea" rows="3" placeholder="A short backstory this cook brings to the table…" class={input_class()} />
            </div>
            <div>
              <label class="block text-xs text-slate-400 mb-1">Health condition (optional)</label>
              <.input
                field={@form[:condition_id]}
                type="select"
                prompt="No condition…"
                options={Enum.map(@conditions, &{&1.name, &1.id})}
                class={input_class()}
              />
              <p class="text-[11px] text-slate-500 mt-1">
                Drives a dietologist-style setup. Use "Populate from condition" below to seed
                encouraged/avoided ingredients.
              </p>
            </div>
            <div>
              <label class="block text-xs text-slate-400 mb-1">Diet direction (optional)</label>
              <.input field={@form[:diet_direction]} type="text" placeholder="e.g. Mediterranean diet" class={input_class()} />
            </div>
            <label class="flex items-center gap-2 text-sm text-slate-300">
              <.input field={@form[:active]} type="checkbox" /> Active
            </label>
            <div class="flex items-center gap-2 pt-2">
              <button type="submit" class="px-4 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium">
                Save
              </button>
              <.link patch={~p"/professional/ai-bot/setups"} class="px-4 py-2 rounded-lg text-slate-400 hover:text-white text-sm">
                Cancel
              </.link>
            </div>
          </.form>
        </div>

        <div :if={@setup} class="bg-slate-800 border border-slate-700/60 rounded-xl p-6">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-base font-semibold text-white">Seed ingredients</h3>
            <button
              :if={@setup.condition_id}
              phx-click="populate_from_condition"
              class="flex items-center gap-1 px-2.5 py-1.5 rounded-lg border border-slate-700/60 text-slate-300 hover:text-white hover:bg-slate-700 text-xs transition-colors"
            >
              <.icon name="hero-sparkles" class="h-3.5 w-3.5" /> Populate from condition
            </button>
          </div>

          <.form for={@ingredient_form} phx-submit="add_ingredient" class="flex items-end gap-2 mb-4">
            <div class="flex-1">
              <label class="block text-xs text-slate-400 mb-1">Ingredient name</label>
              <.input field={@ingredient_form[:name]} type="text" placeholder="e.g. olive oil" class={input_class()} />
            </div>
            <div class="w-36">
              <label class="block text-xs text-slate-400 mb-1">Role</label>
              <.input
                field={@ingredient_form[:role]}
                type="select"
                options={Enum.map(@roles, &{String.capitalize(&1), &1})}
                class={input_class()}
              />
            </div>
            <button type="submit" class="px-3 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium">
              Add
            </button>
          </.form>

          <div class="space-y-1.5">
            <div
              :for={si <- @seed_ingredients}
              class="flex items-center justify-between bg-slate-700/40 rounded-lg px-3 py-2"
            >
              <div class="flex items-center gap-2 text-sm text-white">
                <span class={["inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-semibold border", role_class(si.role)]}>
                  {si.role}
                </span>
                {si.ingredient && si.ingredient.name}
              </div>
              <button
                phx-click="remove_ingredient"
                phx-value-id={si.id}
                class="text-slate-400 hover:text-red-400 transition-colors"
              >
                <.icon name="hero-x-mark" class="h-4 w-4" />
              </button>
            </div>
            <p :if={@seed_ingredients == []} class="text-sm text-slate-500">
              No seed ingredients yet.
            </p>
          </div>
        </div>

        <p :if={@live_action == :new} class="text-xs text-slate-500">
          Save the setup first to add seed ingredients.
        </p>
      </div>
    </div>
    """
  end

  defp role_class("primary"), do: "bg-emerald-500/20 text-emerald-300 border-emerald-500/30"
  defp role_class("spice"), do: "bg-amber-500/20 text-amber-300 border-amber-500/30"
  defp role_class("garnish"), do: "bg-sky-500/20 text-sky-300 border-sky-500/30"
  defp role_class("avoid"), do: "bg-red-500/20 text-red-300 border-red-500/30"
  defp role_class(_), do: "bg-slate-700/50 text-slate-400 border-slate-600/40"

  defp input_class,
    do:
      "w-full bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-2 focus:border-primary-500 focus:outline-none"
end
