defmodule MehungryWeb.ConditionDetailLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.Accounts.UserContent
  alias Mehungry.Food
  alias Mehungry.Food.SpeciesCompounds
  alias Mehungry.Health

  # Display order + copy for the recommendation groups.
  @recommendation_order ["avoid", "limit", "caution", "monitor", "encourage"]

  @recommendation_labels %{
    "avoid" => "Avoid",
    "limit" => "Limit",
    "caution" => "Approach with caution",
    "monitor" => "Monitor",
    "encourage" => "Encourage"
  }

  # ── Nutrition snapshot (mirrors SpeciesDetailLive.Index) ─────────────────────
  @top_nutrient_names [
    "Energy",
    "Protein",
    "Total lipid (fat)",
    "Carbohydrate, by difference",
    "Fiber, total dietary"
  ]

  @display_labels %{
    "Energy" => "Calories",
    "Protein" => "Protein",
    "Total lipid (fat)" => "Fat",
    "Carbohydrate, by difference" => "Carbs",
    "Fiber, total dietary" => "Fiber"
  }

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Health.get_condition(id) do
      nil ->
        {:ok, push_navigate(socket, to: "/conditions")}

      condition ->
        {:ok,
         socket
         |> assign(:condition, condition)
         |> assign_new(:current_user, fn -> nil end)
         |> assign(:current_user_recipes, saved_recipe_ids(socket))
         |> assign_async([:recommendations, :species], fn ->
           {:ok,
            %{
              recommendations: Health.recommendations_for_condition(condition.id),
              species: Health.species_for_condition(condition.id)
            }}
         end)
         |> assign(:page_title, "#{condition.name} — Dietary Guidance")
         |> assign(
           :page_description,
           "Dietary guidance for #{condition.name}: bioactive compounds to be mindful of and the food species that contain them."
         )}
    end
  end

  # `:show_food` opens the encouraged-food preview modal; loads a condensed slice
  # of the species page (identity is available immediately, the rest streams in).
  @impl true
  def handle_params(%{"species_id" => species_id}, _uri, %{assigns: %{live_action: :show_food}} = socket) do
    species = Food.get_species_with_ingredients!(species_id)

    {:noreply,
     socket
     |> assign(:modal_species, species)
     |> assign_async([:modal_nutrients, :modal_compounds, :modal_recipes], fn ->
       ingredients =
         species.foundemental_foods
         |> Enum.map(& &1.ingredient)
         |> Enum.reject(&is_nil/1)

       {:ok,
        %{
          modal_nutrients: top_nutrients_for(ingredients),
          modal_compounds: SpeciesCompounds.list_species_relationships(species.id),
          modal_recipes: sample_recipes_for(ingredients)
        }}
     end)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :modal_species, nil)}
  end

  # Save/unsave a sample recipe for later (guests are sent to log in first).
  @impl true
  def handle_event("save_user_recipe", %{"recipe_id" => recipe_id}, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:noreply, redirect(socket, to: ~p"/users/log_in")}

      user ->
        recipe_id = String.to_integer(recipe_id)

        if recipe_id in socket.assigns.current_user_recipes do
          UserContent.remove_user_saved_recipe(user.id, recipe_id)
        else
          UserContent.save_user_recipe(user.id, recipe_id)
        end

        {:noreply,
         assign(socket, :current_user_recipes, UserContent.list_user_saved_recipe_ids(user))}
    end
  end

  # Saved-recipe ids for the current user (empty for guests).
  defp saved_recipe_ids(socket) do
    case socket.assigns[:current_user] do
      nil -> []
      user -> UserContent.list_user_saved_recipe_ids(user)
    end
  end

  # Prefer a Foundation-class ingredient (most complete nutrient data), else the
  # first; build its top-macro cards. Empty when the species has no ingredients.
  defp top_nutrients_for([]), do: []

  defp top_nutrients_for(ingredients) do
    selected =
      Enum.find(ingredients, &(&1.food_class == "Foundation")) || List.first(ingredients)

    build_top_nutrients(Food.get_ingredient_details!(selected.id).ingredient_nutrients)
  end

  # Up to 4 distinct recipes drawn from across the species' ingredients.
  defp sample_recipes_for(ingredients) do
    ingredients
    |> Enum.flat_map(&Food.list_sample_recipes_for_ingredient(&1.id, 4))
    |> Enum.uniq_by(& &1.id)
    |> Enum.take(4)
  end

  # ── Partition helpers ────────────────────────────────────────────────────────

  @doc "Flagged species minus the encouraged ones (avoid/limit/caution/monitor)."
  def mindful_species(rows), do: Enum.reject(rows, &(&1.recommendation == "encourage"))

  @doc "Encouraged species, deduped (a species may be encouraged via >1 compound)."
  def encouraged_species(rows) do
    rows
    |> Enum.filter(&(&1.recommendation == "encourage"))
    |> Enum.uniq_by(& &1.species.id)
  end

  # ── View helpers (mirror SpeciesDetailLive.Index) ────────────────────────────

  @doc "The URL slug for a species — its English name with spaces hyphenated."
  def species_slug(%{name: name}), do: String.replace(name, " ", "-")

  @doc "Human label for a species↔compound relationship type."
  def relationship_label("contains"), do: "Contains"
  def relationship_label("high_in"), do: "High in"
  def relationship_label("low_in"), do: "Low in"
  def relationship_label("trace"), do: "Trace"
  def relationship_label("absent"), do: "Absent"
  def relationship_label(other), do: Phoenix.Naming.humanize(other || "")

  def format_amount(nil), do: "—"

  def format_amount(amount) when is_float(amount) do
    if amount >= 1 do
      amount |> Float.round(1) |> :erlang.float_to_binary(decimals: 1)
    else
      amount |> Float.round(3) |> :erlang.float_to_binary(decimals: 3)
    end
  end

  def format_amount(amount), do: to_string(amount)

  defp build_top_nutrients(ingredient_nutrients) do
    by_name = Map.new(ingredient_nutrients, &{&1.nutrient.name, &1})

    @top_nutrient_names
    |> Enum.flat_map(fn name ->
      case Map.get(by_name, name) do
        nil ->
          []

        in_ ->
          unit =
            if in_.nutrient.measurement_unit, do: in_.nutrient.measurement_unit.name, else: ""

          [%{label: Map.get(@display_labels, name, name), amount: in_.amount, unit: unit}]
      end
    end)
  end

  # Groups recommendation rows by their `recommendation` value, ordered for display.
  def grouped_recommendations(recommendations) do
    recommendations
    |> Enum.group_by(& &1.recommendation)
    |> Enum.sort_by(fn {rec, _} -> group_order(rec) end)
  end

  defp group_order(rec) do
    case Enum.find_index(@recommendation_order, &(&1 == rec)) do
      nil -> length(@recommendation_order)
      idx -> idx
    end
  end

  def recommendation_label(rec), do: Map.get(@recommendation_labels, rec, String.capitalize(rec))
end
