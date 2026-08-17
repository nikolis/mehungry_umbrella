defmodule MehungryWeb.ConditionDetailLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.Accounts.UserContent
  alias Mehungry.Food
  alias Mehungry.Food.SpeciesCompounds
  alias Mehungry.Health
  alias Phoenix.LiveView.AsyncResult

  # Absolute origin for JSON-LD URLs (mirrors the canonical base in head.html.heex).
  @base_url "https://www.m3hungry.com"

  # Display order for the recommendation groups (labels are gettext'd at render).
  @recommendation_order ["avoid", "limit", "caution", "monitor", "encourage"]

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
    language = socket.assigns[:current_language] || "en"

    case Health.get_condition(id, language) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/#{language}/conditions")}

      condition ->
        # Resolved synchronously (not via assign_async) so the disconnected HTTP
        # render — the only HTML a crawler ever sees — contains the real content
        # (compounds, foods, recipes) rather than loading skeletons.
        species = Health.species_for_condition(condition.id, nil, language)

        page_title = gettext("%{name} — Dietary Guidance", name: condition.name)

        page_description =
          gettext(
            "Dietary guidance for %{name}: bioactive compounds to be mindful of and the food species that contain them.",
            name: condition.name
          )

        {:ok,
         socket
         |> assign(:condition, condition)
         |> assign(:language, language)
         |> assign_new(:current_user, fn -> nil end)
         |> assign(:current_user_recipes, saved_recipe_ids(socket))
         |> assign(
           :recommendations,
           AsyncResult.ok(Health.recommendations_for_condition(condition.id, language))
         )
         |> assign(:species, AsyncResult.ok(species))
         |> assign(:recommended_recipes, AsyncResult.ok(recommended_recipes(species)))
         |> assign(:page_title, page_title)
         |> assign(:page_description, page_description)
         |> assign(
           :structured_data,
           build_structured_data(condition, language, page_title, page_description)
         )}
    end
  end

  # `:show_food` opens the encouraged-food preview modal; loads a condensed slice
  # of the species page (identity is available immediately, the rest streams in).
  @impl true
  def handle_params(%{"species_id" => species_id}, _uri, %{assigns: %{live_action: :show_food}} = socket) do
    species =
      species_id
      |> Food.get_species_with_ingredients!()
      |> localize_species_name(socket.assigns[:language])

    {:noreply,
     socket
     |> assign(:modal_species, species)
     # The food-modal URL is a slice of the condition page; canonicalize to the
     # base page so crawlers don't treat it as duplicate content.
     |> assign(:canonical_path, ~p"/#{socket.assigns.language}/conditions/#{socket.assigns.condition.id}")
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

  @doc """
  Encouraged species, deduped (a species may be encouraged via >1 compound).

  A species that is also flagged as mindful (avoid/limit/caution/monitor via some
  other compound) is excluded — the mindful guidance takes precedence.
  """
  def encouraged_species(rows) do
    mindful_ids =
      rows
      |> mindful_species()
      |> MapSet.new(& &1.species.id)

    rows
    |> Enum.filter(&(&1.recommendation == "encourage"))
    |> Enum.reject(&MapSet.member?(mindful_ids, &1.species.id))
    |> Enum.uniq_by(& &1.species.id)
  end

  # schema.org nodes for this page, emitted as a single @graph in the head:
  #   • BreadcrumbList — mirrors the visible "Conditions › {name}" trail (breadcrumb
  #     rich result).
  #   • MedicalWebPage/MedicalCondition — semantic clarity that the page is dietary
  #     guidance about a condition (no visible card; YMYL, so kept purely descriptive).
  defp build_structured_data(condition, language, page_title, page_description) do
    conditions_url = "#{@base_url}/#{language}/conditions"
    condition_url = "#{conditions_url}/#{condition.id}"

    [
      %{
        "@type" => "BreadcrumbList",
        "itemListElement" => [
          %{
            "@type" => "ListItem",
            "position" => 1,
            "name" => gettext("Conditions"),
            "item" => conditions_url
          },
          %{
            "@type" => "ListItem",
            "position" => 2,
            "name" => condition.name,
            "item" => condition_url
          }
        ]
      },
      %{
        "@type" => "MedicalWebPage",
        "name" => page_title,
        "url" => condition_url,
        "description" => page_description,
        "about" => %{"@type" => "MedicalCondition", "name" => condition.name},
        "audience" => %{"@type" => "MedicalAudience", "audienceType" => "Patient"}
      }
    ]
  end

  # Up to 10 random recipes that use at least one encouraged food and none of the
  # mindful ones. Encouraged/mindful species are disjoint (see `encouraged_species/1`),
  # so their ingredient sets don't overlap.
  defp recommended_recipes(species_rows) do
    encouraged_ids = encouraged_species(species_rows) |> Enum.map(& &1.species.id)
    mindful_ids = mindful_species(species_rows) |> Enum.map(& &1.species.id)

    case encouraged_ids do
      [] ->
        []

      _ ->
        include = Food.list_ingredient_ids_for_species(encouraged_ids)
        exclude = Food.list_ingredient_ids_for_species(mindful_ids)
        Food.list_random_recipes_including_excluding(include, exclude, 10)
    end
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

  def recommendation_label("avoid"), do: gettext("Avoid")
  def recommendation_label("limit"), do: gettext("Limit")
  def recommendation_label("caution"), do: gettext("Approach with caution")
  def recommendation_label("monitor"), do: gettext("Monitor")
  def recommendation_label("encourage"), do: gettext("Encourage")
  def recommendation_label(rec), do: String.capitalize(rec)

  # Gettext-translated label for a top-macro nutrient card (canonical English key
  # from `@display_labels`); explicit clauses so `mix gettext.extract` sees them.
  def nutrient_label("Calories"), do: gettext("Calories")
  def nutrient_label("Protein"), do: gettext("Protein")
  def nutrient_label("Fat"), do: gettext("Fat")
  def nutrient_label("Carbs"), do: gettext("Carbs")
  def nutrient_label("Fiber"), do: gettext("Fiber")
  def nutrient_label(other), do: other

  # Overlays the species' translated name for the modal title. A locale maps to
  # several `language_name` codes (ISO + legacy, e.g. "el"/"Gr"); species rows
  # often predate the ISO migration and live under "Gr", so we try every code for
  # the locale (canonical ISO first). `nil`/`"en"` leaves the base English name.
  defp localize_species_name(species, language) when language in [nil, "", "en"], do: species

  defp localize_species_name(species, language) do
    Mehungry.Languages.Locale.data_codes(language)
    |> Enum.find_value(fn code ->
      case Food.find_species_translation(code, species.id) do
        [name | _] -> name
        [] -> nil
      end
    end)
    |> case do
      nil -> species
      name -> %{species | name: name}
    end
  end
end
