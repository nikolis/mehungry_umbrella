defmodule MehungryWeb.MealBlueprintLive.PlanMealFormComponent do
  @moduledoc """
  Calendar-style editor for a single `BlueprintPlanMeal`. Mirrors the calendar's
  `MehungryWeb.CalendarLive.MealFormComponent` UX — a Recipe/Ingredient toggle, a
  recipe picker (+ cooking portions), or an ingredient picker (+ quantity + unit
  dropdown) — but for the flat single-item plan-meal model, and **without** the
  meal-type (slot) picker since a plan meal's slot is fixed.

  Reuses the shared `SelectComponent` (recipe + unit) and `SelectComponentDeep`
  (ingredient search) widgets and the `unit_selection` decode on `BlueprintPlanMeal`.
  On save it calls `MealBlueprints.update_plan_meal/2` and notifies the parent
  LiveView with `{:plan_meal_saved, ...}` so it can reload the plan (which recomputes
  the day compatibility badges) and close the modal.
  """
  use MehungryWeb, :live_component

  alias Mehungry.Food
  alias Mehungry.Food.IngredientPortion
  alias Mehungry.History.MealType
  alias Mehungry.MealBlueprints
  alias Mehungry.MealBlueprints.BlueprintPlanMeal

  # ── render ──────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col">
      <h2 class="text-lg font-display font-medium text-parchment mb-1">Edit meal</h2>
      <p class="text-parchment-dim text-sm mb-4">
        Day {@plan_meal.day_index} · {MealType.label(@plan_meal.meal_type)}
      </p>

      <div class="flex bg-ink-panel2 rounded-xl p-1 mb-4">
        <button
          type="button"
          phx-click="set_mode"
          phx-value-mode="recipe"
          phx-target={@myself}
          class={[
            "flex-1 py-2 text-sm font-medium rounded-lg transition-all",
            if(@mode == "recipe",
              do: "bg-paprika text-ink shadow",
              else: "text-parchment-dim hover:text-parchment"
            )
          ]}
        >
          Recipe
        </button>
        <button
          type="button"
          phx-click="set_mode"
          phx-value-mode="ingredient"
          phx-target={@myself}
          class={[
            "flex-1 py-2 text-sm font-medium rounded-lg transition-all",
            if(@mode == "ingredient",
              do: "bg-paprika text-ink shadow",
              else: "text-parchment-dim hover:text-parchment"
            )
          ]}
        >
          Ingredient
        </button>
      </div>

      <.form
        for={@form}
        id={"plan-meal-form-#{@plan_meal.id}"}
        phx-change="validate"
        phx-submit="submit"
        phx-target={@myself}
      >
        <div :if={@mode == "recipe"} class="space-y-3">
          <div>
            <label class="block text-sm text-parchment-dim mb-1">Recipe</label>
            <.live_component
              module={MehungryWeb.SelectComponent}
              form={@form}
              items={Enum.map(@recipes, fn r -> {Integer.to_string(r.id), r.title} end)}
              input_variable={:recipe_id}
              id="plan-meal-recipe-select"
            />
          </div>
          <.input field={@form[:cooking_portions]} type="number" min="1" label="Cooking portions" />
        </div>

        <div :if={@mode == "ingredient"} class="space-y-3">
          <div>
            <label class="block text-sm text-parchment-dim mb-1">Ingredient</label>
            <.live_component
              module={MehungryWeb.SelectComponentDeep}
              form={@form}
              item_function={fn term -> Food.IngredientSearch.search(term, [], @current_user.id) end}
              get_by_id_func={&Food.get_ingredient!/1}
              input_variable="ingredient_id"
              label_function={fn item -> Mehungry.Utils.remove_parenthesis(item.name) end}
              placeholder="Select an ingredient..."
              modal_title="Search Ingredients"
              select_function={
                fn ingredient_id -> send_update(@myself, ingredient_selected: ingredient_id) end
              }
              parent_id="plan_meal_ingredient_form"
              id="plan-meal-ingredient-select"
            />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <.input field={@form[:quantity]} type="number" step="any" min="0" label="Quantity" />
            <div>
              <label class="block text-sm text-parchment-dim mb-1">Unit</label>
              <.live_component
                module={MehungryWeb.SelectComponent}
                items={@unit_options}
                form={@form}
                input_variable={:unit_selection}
                id="plan-meal-unit-select"
              />
            </div>
          </div>
        </div>

        <div class="flex justify-end gap-2 mt-5">
          <button
            type="button"
            phx-click="cancel"
            phx-target={@myself}
            class="px-4 py-2 rounded-lg text-parchment-dim hover:text-parchment"
          >
            Cancel
          </button>
          <.button type="primary">Save</.button>
        </div>
      </.form>
    </div>
    """
  end

  # ── update ──────────────────────────────────────────────────────────────────

  # Sent from the ingredient picker when its ingredient changes: refresh the unit
  # dropdown to the new ingredient's portions and stamp the id into the changeset
  # (before the picker re-renders and recomputes its selection).
  @impl true
  def update(%{ingredient_selected: ingredient_id}, socket) do
    socket =
      socket
      |> assign(:unit_options, unit_options(ingredient_id))
      |> update(:form, fn %{source: changeset} ->
        changeset
        |> Ecto.Changeset.put_change(:ingredient_id, ingredient_id)
        |> to_form(as: :plan_meal)
      end)

    {:ok, socket}
  end

  @impl true
  def update(%{plan_meal: plan_meal} = assigns, socket) do
    seeded = %{plan_meal | unit_selection: BlueprintPlanMeal.unit_selection_value(plan_meal)}

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:plan_meal, seeded)
     |> assign(:mode, if(plan_meal.recipe_id, do: "recipe", else: "ingredient"))
     |> assign(:recipes, Food.list_user_recipes_for_selection(assigns.current_user))
     |> assign(:unit_options, unit_options(plan_meal.ingredient_id))
     |> assign(:form, to_form(MealBlueprints.change_plan_meal(seeded), as: :plan_meal))}
  end

  # ── events ──────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :mode, mode)}
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    send(self(), {:plan_meal_edit_cancelled})
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"plan_meal" => params}, socket) do
    changeset =
      socket.assigns.plan_meal
      |> BlueprintPlanMeal.changeset(mode_attrs(socket.assigns.mode, params))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :plan_meal))}
  end

  @impl true
  def handle_event("submit", %{"plan_meal" => params}, socket) do
    case MealBlueprints.update_plan_meal(
           socket.assigns.plan_meal,
           mode_attrs(socket.assigns.mode, params)
         ) do
      {:ok, _} ->
        send(self(), {:plan_meal_saved, %{flash: "Meal updated."}})
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :plan_meal))}
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────────

  # Keeps exactly one side of the recipe/ingredient XOR, nulling the other so a
  # type switch clears stale data (and passes the schema's XOR validation).
  defp mode_attrs("recipe", params) do
    %{
      "recipe_id" => params["recipe_id"],
      "cooking_portions" => params["cooking_portions"],
      "ingredient_id" => nil,
      "quantity" => nil,
      "unit_selection" => nil,
      "measurement_unit_id" => nil,
      "ingredient_portion_id" => nil
    }
  end

  defp mode_attrs("ingredient", params) do
    %{
      "ingredient_id" => params["ingredient_id"],
      "quantity" => params["quantity"],
      "unit_selection" => params["unit_selection"],
      "recipe_id" => nil,
      "cooking_portions" => nil
    }
  end

  # Unit dropdown options for an ingredient: each portion (encoded as
  # `measurement_unit_id`, or `-portion_id` for description-only portions) plus a
  # gram fallback. Mirrors `MealFormComponent.unit_options/1`.
  defp unit_options(nil), do: gram_options()

  defp unit_options(ingredient_id) do
    portion_options =
      ingredient_id
      |> Food.get_measurement_unit_portions_for_ingredient()
      |> Enum.map(fn portion ->
        value = if portion.measurement_unit_id, do: portion.measurement_unit_id, else: -portion.id
        {Integer.to_string(value), IngredientPortion.display_name(portion) || "portion"}
      end)

    portion_options ++ gram_options()
  end

  defp gram_options do
    Enum.map(Food.get_measurement_unit_by_name("gram"), fn mu ->
      {Integer.to_string(mu.id), mu.name}
    end)
  end
end
