defmodule MehungryWeb.MealBlueprintLive.PlanMealFormComponent do
  @moduledoc """
  Editor for a single `BlueprintPlanMeal`. A meal can hold a recipe **and/or**
  any number of whole-food ingredients (mirrors the calendar's `History.UserMeal`).

  * **Recipe** — an optional recipe picker (`SelectComponent`) + cooking portions.
  * **Ingredients** — a repeatable list of ingredient rows (each with a quantity
    and a unit `<select>`), plus one "Add ingredient" search picker
    (`SelectComponentDeep`) that appends a new row. Rows live in socket state
    (`@ingredient_rows`) — the source of truth on submit — since per-row live
    pickers would collide on a shared form field.

  On save it calls `MealBlueprints.update_plan_meal/2` (which replaces the meal's
  ingredient children and recomputes compatibility) and notifies the parent
  LiveView with `{:plan_meal_saved, ...}` so it can reload the plan and close.
  """
  use MehungryWeb, :live_component

  alias Mehungry.Food
  alias Mehungry.Food.IngredientPortion
  alias Mehungry.History.MealType
  alias Mehungry.MealBlueprints
  alias Mehungry.MealBlueprints.BlueprintPlanMealIngredient

  # ── render ──────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col">
      <h2 class="text-lg font-display font-medium text-parchment mb-1">Edit meal</h2>
      <p class="text-parchment-dim text-sm mb-4">
        Day {@plan_meal.day_index} · {MealType.label(@plan_meal.meal_type)}
      </p>

      <.form
        for={@form}
        id={"plan-meal-form-#{@plan_meal.id}"}
        phx-change="validate"
        phx-submit="submit"
        phx-target={@myself}
      >
        <div class="space-y-3">
          <div class="rounded-xl border border-ink-panel2 p-3 space-y-3">
            <h3 class="text-sm font-semibold text-parchment">Recipe <span class="text-parchment-dim font-normal">(optional)</span></h3>
            <div>
              <div style={sc_theme()}>
                <.live_component
                  module={MehungryWeb.SelectComponent}
                  form={@form}
                  items={Enum.map(@recipes, fn r -> {Integer.to_string(r.id), r.title} end)}
                  input_variable={:recipe_id}
                  id="plan-meal-recipe-select"
                />
              </div>
            </div>
            <div>
              <label class="block text-sm text-parchment-dim mb-1">Cooking portions</label>
              <input
                type="number"
                min="1"
                name={@form[:cooking_portions].name}
                value={@form[:cooking_portions].value}
                class="w-full rounded-lg bg-ink border border-ink-panel2 text-parchment text-sm px-3 py-2"
              />
            </div>
          </div>

          <div class="rounded-xl border border-ink-panel2 p-3 space-y-3">
            <h3 class="text-sm font-semibold text-parchment">Ingredients</h3>

            <p :if={@ingredient_rows == []} class="text-parchment-dim text-xs">
              No ingredients yet — search below to add one.
            </p>

            <div :for={row <- @ingredient_rows} class="flex items-end gap-2">
              <div class="flex-1 min-w-0">
                <span class="text-sm text-parchment truncate block">{row.ingredient_name}</span>
              </div>
              <div class="w-20">
                <label class="block text-[11px] text-parchment-dim mb-0.5">Qty</label>
                <input
                  type="number"
                  step="any"
                  min="0"
                  name={"ing[#{row.key}][quantity]"}
                  value={row.quantity}
                  class="w-full rounded-lg bg-ink border border-ink-panel2 text-parchment text-sm px-2 py-1.5"
                />
              </div>
              <div class="w-32">
                <label class="block text-[11px] text-parchment-dim mb-0.5">Unit</label>
                <select
                  name={"ing[#{row.key}][unit_selection]"}
                  class="w-full rounded-lg bg-ink border border-ink-panel2 text-parchment text-sm px-2 py-1.5"
                >
                  <option
                    :for={{value, label} <- row.unit_options}
                    value={value}
                    selected={to_string(row.unit_selection) == value}
                  >
                    {label}
                  </option>
                </select>
              </div>
              <button
                type="button"
                phx-click="remove_ingredient"
                phx-value-key={row.key}
                phx-target={@myself}
                class="mb-1.5 px-2 py-1 rounded text-parchment-dim hover:text-paprika transition"
                title="Remove ingredient"
              >
                ✕
              </button>
            </div>

            <div>
              <label class="block text-sm text-parchment-dim mb-1">Add ingredient</label>
              <.live_component
                module={MehungryWeb.SelectComponentDeep}
                form={@add_form}
                item_function={fn term -> Food.IngredientSearch.search(term, [], @current_user.id) end}
                get_by_id_func={&Food.get_ingredient!/1}
                input_variable="ingredient_id"
                label_function={fn item -> Mehungry.Utils.remove_parenthesis(item.name) end}
                placeholder="Search an ingredient to add..."
                modal_title="Search Ingredients"
                select_function={
                  fn ingredient_id -> send_update(@myself, add_ingredient: ingredient_id) end
                }
                parent_id="plan_meal_add_ingredient"
                id={"plan-meal-add-ingredient-#{@picker_nonce}"}
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

  # Sent from the "Add ingredient" picker: append a fresh row (seeded with the
  # ingredient's unit options + a gram default) and remount the picker clean.
  @impl true
  def update(%{add_ingredient: ingredient_id}, socket) do
    ingredient = Food.get_ingredient!(ingredient_id)
    options = unit_options(ingredient_id)

    row = %{
      key: Integer.to_string(System.unique_integer([:positive])),
      ingredient_id: ingredient_id,
      ingredient_name: ingredient.name,
      quantity: 1.0,
      unit_selection: default_unit_selection(options),
      unit_options: options
    }

    {:ok,
     socket
     |> update(:ingredient_rows, &(&1 ++ [row]))
     |> update(:picker_nonce, &(&1 + 1))}
  end

  @impl true
  def update(%{plan_meal: plan_meal} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:recipes, Food.list_user_recipes_for_selection(assigns.current_user))
     |> assign(:ingredient_rows, seed_rows(plan_meal))
     |> assign(:picker_nonce, 0)
     |> assign(:add_form, new_add_form())
     |> assign(:form, to_form(MealBlueprints.change_plan_meal(plan_meal), as: :plan_meal))}
  end

  # ── events ──────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("cancel", _params, socket) do
    send(self(), {:plan_meal_edit_cancelled})
    {:noreply, socket}
  end

  @impl true
  def handle_event("remove_ingredient", %{"key" => key}, socket) do
    {:noreply, update(socket, :ingredient_rows, &Enum.reject(&1, fn r -> r.key == key end))}
  end

  @impl true
  def handle_event("validate", params, socket) do
    rows = merge_row_params(socket.assigns.ingredient_rows, Map.get(params, "ing", %{}))

    changeset =
      MealBlueprints.change_plan_meal(
        socket.assigns.plan_meal,
        recipe_params(Map.get(params, "plan_meal", %{}))
      )

    {:noreply,
     socket
     |> assign(:ingredient_rows, rows)
     |> assign(:form, to_form(changeset, as: :plan_meal))}
  end

  @impl true
  def handle_event("submit", params, socket) do
    rows = merge_row_params(socket.assigns.ingredient_rows, Map.get(params, "ing", %{}))
    plan_params = Map.get(params, "plan_meal", %{})

    attrs =
      recipe_params(plan_params)
      |> Map.put("ingredients", Enum.map(rows, &row_to_attrs/1))

    case MealBlueprints.update_plan_meal(socket.assigns.plan_meal, attrs) do
      {:ok, _} ->
        send(self(), {:plan_meal_saved, %{flash: "Meal updated."}})
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:ingredient_rows, rows)
         |> assign(:form, to_form(changeset, as: :plan_meal))}
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────────

  # Seeds the editable ingredient rows from a persisted meal's children.
  defp seed_rows(%{ingredients: ingredients}) when is_list(ingredients) do
    Enum.map(ingredients, fn ing ->
      %{
        key: Integer.to_string(ing.id),
        ingredient_id: ing.ingredient_id,
        ingredient_name: ing.ingredient && ing.ingredient.name,
        quantity: ing.quantity,
        unit_selection: BlueprintPlanMealIngredient.unit_selection_value(ing),
        unit_options: unit_options(ing.ingredient_id)
      }
    end)
  end

  defp seed_rows(_), do: []

  defp new_add_form do
    to_form(BlueprintPlanMealIngredient.changeset(%BlueprintPlanMealIngredient{}, %{}),
      as: :add_ingredient
    )
  end

  defp recipe_params(plan_params) do
    %{
      "recipe_id" => blank_to_nil(Map.get(plan_params, "recipe_id")),
      "cooking_portions" => Map.get(plan_params, "cooking_portions")
    }
  end

  defp blank_to_nil(v) when v in ["", nil], do: nil
  defp blank_to_nil(v), do: v

  # Fold the submitted per-row quantity/unit params back into the socket rows so
  # edits survive add/remove re-renders (rows are the source of truth).
  defp merge_row_params(rows, ing_params) do
    Enum.map(rows, fn row ->
      case Map.get(ing_params, row.key) do
        %{} = p ->
          %{
            row
            | quantity: Map.get(p, "quantity", row.quantity),
              unit_selection: Map.get(p, "unit_selection", row.unit_selection)
          }

        _ ->
          row
      end
    end)
  end

  defp row_to_attrs(row) do
    %{
      "ingredient_id" => row.ingredient_id,
      "quantity" => row.quantity,
      "unit_selection" => row.unit_selection
    }
  end

  # Retheme the shared `SelectComponent` off its slate defaults onto the app's
  # ink/parchment palette via its documented `--sc-*` CSS variables, scoped to
  # this call site so other usages are untouched. Values mirror the `ink` tokens
  # in tailwind.config.js (ink #17140F, panel #211D16, panel2 #2B2619).
  defp sc_theme do
    "--sc-bg:#17140F;--sc-border:#2B2619;--sc-dropdown-bg:#211D16;" <>
      "--sc-option-bg:#211D16;--sc-option-selected:#2B2619;--sc-option-hover:#2B2619;"
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

  # Default a new row to grams (the last option) when available.
  defp default_unit_selection(options) do
    case List.last(options) do
      {value, _label} -> String.to_integer(value)
      _ -> nil
    end
  end
end
