defmodule MehungryWeb.MyIngredientLive.Form do
  @moduledoc """
  User-facing create/edit form for a person's own private ingredients.

  Reuses the dynamic nutrient/portion/translation sub-components from the
  professional ingredient form, but scopes every write to `@current_user` via
  `Food.create_user_ingredient/2` and `Food.get_user_ingredient!/2`.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.{Ingredient, IngredientPortion, IngredientNutrient}
  alias Mehungry.Languages

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:categories, Food.list_categories())
     |> assign(:measurement_units, Food.list_measurement_units())
     |> assign(:nutrients, Food.list_nutrients())
     |> assign(:languages, Languages.list_languages())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    ingredient = %Ingredient{
      food_class: "User created",
      ingredient_portions: [%IngredientPortion{}],
      ingredient_nutrients: [%IngredientNutrient{}],
      ingredient_translation: []
    }

    socket
    |> assign(:page_title, "New ingredient")
    |> assign(:ingredient, ingredient)
    |> assign(:form, to_form(Food.change_ingredient(ingredient)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    ingredient = Food.get_user_ingredient!(socket.assigns.current_user, id)

    socket
    |> assign(:page_title, "Edit ingredient")
    |> assign(:ingredient, ingredient)
    |> assign(:form, to_form(Food.change_ingredient(ingredient)))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-ink text-parchment px-4 py-6 sm:px-6 lg:px-8">
      <form
        id="my-ingredient-form"
        phx-change="validate"
        phx-submit="save"
        class="ingredient-form max-w-4xl mx-auto space-y-6"
      >
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-6">
          <div class="flex items-center justify-between mb-6">
            <.link
              navigate={~p"/profile?#{[tab: "my_ingredients"]}"}
              class="text-parchment-dim hover:text-parchment text-sm"
            >
              ← Back
            </.link>
            <h2 class="text-lg font-display font-medium text-parchment">{@page_title}</h2>
          </div>

          <input type="hidden" name="ingredient[_action]" value="" />
          <input type="hidden" name="ingredient[food_class]" value={@form[:food_class].value} />

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <label class="block text-xs font-semibold uppercase tracking-wider text-parchment-dim mb-1">
                Name
              </label>
              <.input type="text" name="ingredient[name]" value={@form[:name].value} />
            </div>
            <div>
              <label class="block text-xs font-semibold uppercase tracking-wider text-parchment-dim mb-1">
                Category
              </label>
              <.live_component
                module={MehungryWeb.SelectComponent}
                items={Enum.map(@categories, fn x -> {Integer.to_string(x.id), x.name} end)}
                form={@form}
                id="category_select_component"
                input_variable={:category_id}
              />
            </div>
          </div>
        </div>

        <.live_component
          module={MehungryWeb.Professional.NutrientComponent}
          id="nutrients"
          form={@form}
          nutrients={@nutrients}
        />

        <.live_component
          module={MehungryWeb.Professional.PortionsComponent}
          id="portions"
          form={@form}
          measurement_units={@measurement_units}
        />

        <.live_component
          module={MehungryWeb.Professional.TranslationsComponent}
          id="translations"
          form={@form}
          languages={@languages}
        />

        <div class="flex justify-end pb-8">
          <button
            type="submit"
            class="px-6 py-3 rounded-full bg-paprika hover:bg-paprika-soft text-ink font-bold text-sm transition-colors"
          >
            Save Ingredient
          </button>
        </div>
      </form>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"ingredient" => params}, socket) do
    handle_action(socket, params)
  end

  def handle_event("save", %{"ingredient" => params}, socket) do
    handle_action(socket, params)
  end

  # The dynamic add/remove-row buttons submit the form with an `_action`; only a
  # plain submit (no `_action`) actually persists the ingredient.
  defp handle_action(socket, params) do
    case params["_action"] do
      "add_portion" -> rebuild(socket, add_row(params, "ingredient_portions"))
      "add_nutrient" -> rebuild(socket, add_row(params, "ingredient_nutrients"))
      "add_ingredient_translation" -> rebuild(socket, add_row(params, "ingredient_translation"))
      "remove_portion:" <> i -> rebuild(socket, remove_row(params, "ingredient_portions", i))
      "remove_nutrient:" <> i -> rebuild(socket, remove_row(params, "ingredient_nutrients", i))
      _ -> save_ingredient(socket, params)
    end
  end

  defp save_ingredient(socket, params) do
    result =
      case socket.assigns.live_action do
        :new -> Food.create_user_ingredient(socket.assigns.current_user, params)
        :edit -> Food.update_ingredient(socket.assigns.ingredient, params)
      end

    case result do
      {:ok, _ingredient} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ingredient saved")
         |> push_navigate(to: ~p"/profile?#{[tab: "my_ingredients"]}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp add_row(params, key) do
    rows = Map.get(params, key, %{})
    Map.put(params, key, Map.put(rows, "#{map_size(rows)}", %{}))
  end

  defp remove_row(params, key, index) do
    rows = params |> Map.get(key, %{}) |> Map.delete(index)
    Map.put(params, key, rows)
  end

  defp rebuild(socket, params) do
    changeset =
      socket.assigns.ingredient
      |> Food.change_ingredient(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end
end
