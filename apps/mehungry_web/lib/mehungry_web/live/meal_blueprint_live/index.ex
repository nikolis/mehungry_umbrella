defmodule MehungryWeb.MealBlueprintLive.Index do
  @moduledoc """
  Library of the user's meal-plan blueprints: list, create (name-only modal that
  seeds the 7×5 skeleton and jumps to the editor), duplicate, delete, and
  generate plans from a blueprint.

  Generated plans are **independent of the calendar** — each is listed under its
  blueprint in an expandable accordion, and a plan lands on the calendar only
  when the user imports it (choosing a start date). Multiple plans per blueprint
  can coexist so the user picks whichever they like.

  Since this is the nutritionist-facing library, the import modal also lets them
  pick **who** the plan is imported for: themselves or any of their assigned
  clients (the plan is written to that client's calendar).
  """
  use MehungryWeb, :live_view

  alias Mehungry.Accounts
  alias Mehungry.Food
  alias Mehungry.History.MealType
  alias Mehungry.MealBlueprints
  alias Mehungry.Professionals
  alias Mehungry.Subscriptions

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-ink text-parchment pb-16">
      <div class="container max-w-3xl mx-auto px-4 py-8">
        <div class="flex items-center justify-between mb-6">
          <div>
            <h1 class="text-2xl font-display font-medium text-parchment">Meal Blueprints</h1>
            <p class="text-parchment-dim text-sm mt-1">
              Reusable 7-day nutritional targets you can plan against.
            </p>
          </div>
          <.link
            patch={~p"/nutritionist/blueprints/new"}
            class="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-bold transition"
          >
            + New blueprint
          </.link>
        </div>

        <div :if={@blueprints == []} class="text-center text-parchment-dim py-20">
          You don't have any blueprints yet. Create your first one.
        </div>

        <div class="space-y-3">
          <div
            :for={bp <- @blueprints}
            id={"blueprint-#{bp.id}"}
            class="bg-ink-panel rounded-xl border border-ink-panel2 overflow-hidden"
          >
            <div class="p-4 flex items-center justify-between">
              <.link patch={~p"/nutritionist/blueprints/#{bp.id}/edit"} class="min-w-0 flex-1">
                <div class="font-semibold text-parchment truncate flex items-center gap-2">
                  {bp.name}
                  <span class={[
                    "text-[10px] font-semibold px-1.5 py-0.5 rounded-full uppercase tracking-wide",
                    if(bp.visibility == "public",
                      do: "bg-basil/20 text-basil",
                      else: "bg-ink-panel2 text-parchment-dim"
                    )
                  ]}>
                    {bp.visibility}
                  </span>
                </div>
                <div :if={bp.description} class="text-parchment-dim text-sm truncate">
                  {bp.description}
                </div>
                <div class="text-parchment-dim text-xs mt-1">7 days · 5 meals/day</div>
              </.link>
              <div class="flex items-center gap-2 ml-4 shrink-0">
                <.link
                  :if={bp.visibility == "public" && bp.slug}
                  navigate={~p"/blueprints/#{bp.slug}"}
                  class="px-3 py-1.5 rounded-lg text-sm text-basil hover:bg-basil/10 transition"
                  target="_blank"
                >
                  View public
                </.link>
                <button
                  phx-click="generate"
                  phx-value-id={bp.id}
                  disabled={MapSet.member?(@generating_ids, bp.id)}
                  class="px-3 py-1.5 rounded-lg text-sm font-semibold bg-basil/20 text-basil hover:bg-basil/30 transition disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {if MapSet.member?(@generating_ids, bp.id), do: "Generating…", else: "Generate"}
                </button>
                <.link
                  patch={~p"/nutritionist/blueprints/#{bp.id}/edit"}
                  class="px-3 py-1.5 rounded-lg text-sm text-parchment-dim hover:text-parchment hover:bg-ink-panel2 transition"
                >
                  Edit
                </.link>
                <button
                  phx-click="duplicate"
                  phx-value-id={bp.id}
                  class="px-3 py-1.5 rounded-lg text-sm text-parchment-dim hover:text-parchment hover:bg-ink-panel2 transition"
                >
                  Duplicate
                </button>
                <button
                  phx-click="delete"
                  phx-value-id={bp.id}
                  data-confirm="Delete this blueprint?"
                  class="px-3 py-1.5 rounded-lg text-sm text-parchment-dim hover:text-paprika transition"
                >
                  Delete
                </button>
              </div>
            </div>

            <%!-- Generated plans accordion (independent of the calendar) --%>
            <div
              :for={plan <- Map.get(@plans_by_blueprint, bp.id, [])}
              class="border-t border-ink-panel2"
            >
              <div class="w-full flex items-center justify-between px-4 py-2.5">
                <button
                  type="button"
                  phx-click="toggle_plan"
                  phx-value-id={plan.id}
                  class="min-w-0 flex items-center gap-2 text-left flex-1 hover:opacity-80 transition"
                >
                  <span class={[
                    "transition-transform text-parchment-dim text-xs",
                    MapSet.member?(@expanded_plans, plan.id) && "rotate-90"
                  ]}>
                    ▶
                  </span>
                  <span class="text-sm text-parchment truncate">{plan.name}</span>
                  <.plan_status_badge status={plan.status} />
                  <span
                    :if={plan.imported_at}
                    class="text-[10px] px-1.5 py-0.5 rounded bg-basil/20 text-basil"
                  >
                    imported
                  </span>
                </button>
                <div class="flex items-center gap-3 shrink-0 ml-2">
                  <span class="text-parchment-dim text-xs">{plan.meals_count} meals</span>
                  <button
                    :if={plan.status == "completed"}
                    phx-click="open_import"
                    phx-value-id={plan.id}
                    data-confirm={
                      plan.imported_at &&
                        "This plan is already on your calendar. Import it again onto another week?"
                    }
                    class="px-2.5 py-1 rounded-lg text-xs font-semibold bg-paprika/90 hover:bg-paprika text-ink transition"
                  >
                    Import
                  </button>
                  <button
                    type="button"
                    phx-click="delete_plan"
                    phx-value-id={plan.id}
                    data-confirm={
                      "Delete this plan? " <>
                        if(plan.imported_at,
                          do: "Meals already on your calendar will stay.",
                          else: "This can't be undone."
                        )
                    }
                    aria-label="Delete plan"
                    class="px-2 py-1 rounded-lg text-xs font-semibold text-parchment-dim hover:text-paprika transition"
                  >
                    Delete
                  </button>
                </div>
              </div>

              <div
                :if={MapSet.member?(@expanded_plans, plan.id)}
                class="px-4 pb-3 pt-1 bg-ink/40"
              >
                <div :if={plan.status == "failed"} class="text-paprika text-xs mb-2">
                  {plan.error || "Generation failed."}
                </div>
                <div :if={plan.meals == []} class="text-parchment-dim text-xs py-2">
                  No meals in this plan.
                </div>
                <div class="space-y-3">
                  <div :for={{day_index, meals} <- group_by_day_index(plan.meals)}>
                    <div class="text-parchment-dim text-xs font-semibold uppercase tracking-wide mb-1.5">
                      Day {day_index}
                    </div>
                    <div class="space-y-1.5">
                      <div :for={m <- meals} class="flex items-center gap-2 group">
                        <span class="text-parchment-dim text-[11px] w-24 shrink-0">
                          {MealType.label(m.meal_type)}
                        </span>
                        <div class="min-w-0 flex-1">
                          <.recipe_line m={m} />
                          <.ingredient_line m={m} />
                        </div>
                        <div class="flex items-center gap-1 shrink-0 opacity-0 group-hover:opacity-100 transition">
                          <button
                            type="button"
                            phx-click="edit_plan_meal"
                            phx-value-id={m.id}
                            class="px-2 py-1 rounded text-[11px] text-parchment-dim hover:text-parchment hover:bg-ink-panel2 transition"
                          >
                            Edit
                          </button>
                          <button
                            type="button"
                            phx-click="delete_plan_meal"
                            phx-value-id={m.id}
                            data-confirm="Remove this meal from the plan?"
                            class="px-2 py-1 rounded text-[11px] text-parchment-dim hover:text-paprika transition"
                          >
                            ✕
                          </button>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
                <.link
                  :if={plan.imported_at}
                  navigate={~p"/calendar"}
                  class="inline-block mt-2 text-xs text-basil hover:underline"
                >
                  View on calendar →
                </.link>
              </div>
            </div>
          </div>
        </div>
      </div>

      <.modal
        :if={@live_action == :new}
        id="new-blueprint-modal"
        show
        on_cancel={JS.patch(~p"/nutritionist/blueprints")}
      >
        <h2 class="text-lg font-display font-medium text-parchment mb-4">New blueprint</h2>
        <.simple_form for={@new_form} phx-submit="create">
          <.input field={@new_form[:name]} type="text" label="Name" placeholder="e.g. Cutting week" />
          <:actions>
            <.button type="primary">Create &amp; edit</.button>
          </:actions>
        </.simple_form>
      </.modal>

      <.modal
        :if={@import_form}
        id="import-plan-modal"
        show
        on_cancel={JS.push("close_import")}
      >
        <h2 class="text-lg font-display font-medium text-parchment mb-2">Import to calendar</h2>
        <p class="text-parchment-dim text-sm mb-4">
          Choose the start date — the plan's 7 days will be laid out from there.
          Any meals already on the selected calendar that week will be replaced.
        </p>
        <.simple_form for={@import_form} phx-submit="import_plan">
          <.input
            :if={@clients != []}
            field={@import_form[:target_user_id]}
            type="select"
            label="Import for"
            options={client_options(@clients, @user)}
          />
          <.input field={@import_form[:start_date]} type="date" label="Start date" />
          <:actions>
            <.button type="primary">Add to calendar</.button>
          </:actions>
        </.simple_form>
      </.modal>

      <.modal
        :if={@editing_plan_meal}
        id="edit-meal-modal"
        show
        on_cancel={JS.push("close_meal_edit")}
      >
        <h2 class="text-lg font-display font-medium text-parchment mb-1">Edit meal</h2>
        <p class="text-parchment-dim text-sm mb-4">
          Day {@editing_plan_meal.day_index} · {MealType.label(@editing_plan_meal.meal_type)}
        </p>

        <%!-- Adjust the current item's portions/quantity --%>
        <form phx-submit="save_meal_fields" class="mb-5">
          <div :if={@editing_plan_meal.recipe_id} class="flex items-end gap-2">
            <div class="flex-1">
              <label class="block text-sm text-parchment-dim mb-1">Cooking portions</label>
              <input
                type="number"
                name="meal[cooking_portions]"
                value={@editing_plan_meal.cooking_portions || 2}
                min="1"
                class="w-full rounded-lg bg-ink border border-ink-panel2 text-parchment text-sm px-3 py-2"
              />
            </div>
            <.button type="primary">Save</.button>
          </div>
          <div :if={!@editing_plan_meal.recipe_id} class="flex items-end gap-2">
            <div class="flex-1">
              <label class="block text-sm text-parchment-dim mb-1">Quantity</label>
              <input
                type="number"
                step="any"
                name="meal[quantity]"
                value={@editing_plan_meal.quantity || 1.0}
                min="0"
                class="w-full rounded-lg bg-ink border border-ink-panel2 text-parchment text-sm px-3 py-2"
              />
            </div>
            <.button type="primary">Save</.button>
          </div>
        </form>

        <%!-- Swap the slot to a different recipe --%>
        <div class="border-t border-ink-panel2 pt-4">
          <label class="block text-sm text-parchment-dim mb-1">Swap for a recipe</label>
          <form id="meal-search-form" phx-change="meal_search" phx-submit="meal_search">
            <input
              type="text"
              name="query"
              placeholder="Search recipes…"
              phx-debounce="300"
              class="w-full rounded-lg bg-ink border border-ink-panel2 text-parchment text-sm px-3 py-2"
            />
          </form>
          <div :if={@meal_search_results != []} class="mt-2 space-y-1 max-h-56 overflow-y-auto">
            <button
              :for={r <- @meal_search_results}
              type="button"
              phx-click="swap_meal_recipe"
              phx-value-recipe_id={r.id}
              class="w-full text-left px-3 py-2 rounded-lg text-sm text-parchment hover:bg-ink-panel2 transition"
            >
              {r.title}
            </button>
          </div>
        </div>
      </.modal>
    </div>
    """
  end

  # ── view helpers ──────────────────────────────────────────────────────────────

  defp plan_status_badge(%{status: "generating"} = assigns) do
    ~H"""
    <span class="text-[10px] px-1.5 py-0.5 rounded bg-amber-500/20 text-amber-400">generating…</span>
    """
  end

  defp plan_status_badge(%{status: "failed"} = assigns) do
    ~H"""
    <span class="text-[10px] px-1.5 py-0.5 rounded bg-paprika/20 text-paprika">failed</span>
    """
  end

  defp plan_status_badge(assigns), do: ~H""

  # Groups a plan's meals by their relative day (1..7) for accordion display.
  defp group_by_day_index(meals) do
    meals
    |> Enum.group_by(& &1.day_index)
    |> Enum.sort_by(fn {day_index, _} -> day_index end)
  end

  # A compact recipe row: small thumbnail, title, and a muted basic-info line.
  defp recipe_line(%{m: %{recipe: recipe}} = assigns) when not is_nil(recipe) do
    ~H"""
    <div class="flex items-center gap-2 py-0.5">
      <div class="w-9 h-9 rounded-md overflow-hidden bg-ink-panel2 shrink-0">
        <img
          :if={@m.recipe.image_url}
          src={@m.recipe.image_url}
          alt={@m.recipe.title}
          class="w-full h-full object-cover"
        />
        <div
          :if={!@m.recipe.image_url}
          class="w-full h-full flex items-center justify-center text-parchment-dim text-xs"
        >
          🍽
        </div>
      </div>
      <div class="min-w-0">
        <div class="text-sm text-parchment truncate">{@m.recipe.title}</div>
        <div class="text-parchment-dim text-[11px] truncate">{recipe_info(@m.recipe)}</div>
      </div>
    </div>
    """
  end

  defp recipe_line(assigns), do: ~H""

  # A compact ingredient row: name on the left, quantity + unit on the right.
  defp ingredient_line(%{m: %{ingredient: ingredient}} = assigns) when not is_nil(ingredient) do
    ~H"""
    <div class="flex items-center justify-between gap-2 py-0.5 pl-1">
      <div class="flex items-center gap-2 min-w-0">
        <span class="w-9 h-9 rounded-md bg-basil/15 text-basil flex items-center justify-center text-xs shrink-0">
          🥗
        </span>
        <span class="text-sm text-parchment truncate">{@m.ingredient.name}</span>
      </div>
      <span class="text-parchment-dim text-xs shrink-0 [font-variant-numeric:tabular-nums]">
        {format_quantity(@m.quantity)} {Mehungry.Food.RecipeIngredient.unit_label(@m)}
      </span>
    </div>
    """
  end

  defp ingredient_line(assigns), do: ~H""

  # Muted "2 servings · Easy · 25 min" line, dropping any parts that are missing.
  defp recipe_info(recipe) do
    [
      recipe.servings && "#{recipe.servings} servings",
      difficulty_label(recipe.difficulty),
      cooking_time(recipe)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp difficulty_label(1), do: "Easy"
  defp difficulty_label(2), do: "Medium"
  defp difficulty_label(3), do: "Difficult"
  defp difficulty_label(_), do: nil

  defp cooking_time(%{cooking_time_lower_limit: t}) when is_integer(t) and t > 0, do: "#{t} min"
  defp cooking_time(_), do: nil

  defp format_quantity(q) when is_float(q) do
    if q == Float.round(q), do: q |> trunc() |> Integer.to_string(), else: Float.to_string(q)
  end

  defp format_quantity(nil), do: ""
  defp format_quantity(q), do: to_string(q)

  # ── lifecycle ─────────────────────────────────────────────────────────────────

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])
    blueprints = MealBlueprints.list_blueprints_for_user(user.id)

    {:ok,
     socket
     |> assign(:user, user)
     |> assign(:page_title, "Meal Blueprints")
     |> assign(:new_form, to_form(%{"name" => ""}, as: :blueprint))
     |> assign(:blueprints, blueprints)
     |> assign(:plans_by_blueprint, load_plans(user.id, blueprints))
     |> assign(:clients, load_client_targets(user.id))
     |> assign(:expanded_plans, MapSet.new())
     |> assign(:generating_ids, MapSet.new())
     |> assign(:gen_tasks, %{})
     |> assign(:import_plan_id, nil)
     |> assign(:import_form, nil)
     |> assign(:editing_plan_meal, nil)
     |> assign(:meal_search_results, [])}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # ── events ────────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("create", %{"blueprint" => %{"name" => name}}, socket) do
    user = socket.assigns.user
    name = String.trim(name)

    if name == "" do
      {:noreply, put_flash(socket, :error, "Please enter a name.")}
    else
      case MealBlueprints.create_blueprint(
             MealBlueprints.default_blueprint_attrs(user.id, name)
           ) do
        {:ok, blueprint} ->
          {:noreply, push_navigate(socket, to: ~p"/nutritionist/blueprints/#{blueprint.id}/edit")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not create blueprint.")}
      end
    end
  end

  @impl true
  def handle_event("duplicate", %{"id" => id}, socket) do
    user = socket.assigns.user
    blueprint = MealBlueprints.get_blueprint!(user.id, id)
    {:ok, _copy} = MealBlueprints.duplicate_blueprint(blueprint)

    {:noreply, reload_blueprints(socket)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.user
    blueprint = MealBlueprints.get_blueprint!(user.id, id)
    {:ok, _} = MealBlueprints.delete_blueprint(blueprint)

    {:noreply, reload_blueprints(socket)}
  end

  @impl true
  def handle_event("toggle_plan", %{"id" => id}, socket) do
    id = String.to_integer(id)

    expanded =
      if MapSet.member?(socket.assigns.expanded_plans, id) do
        MapSet.delete(socket.assigns.expanded_plans, id)
      else
        MapSet.put(socket.assigns.expanded_plans, id)
      end

    {:noreply, assign(socket, :expanded_plans, expanded)}
  end

  @impl true
  def handle_event("generate", %{"id" => id}, socket) do
    user = socket.assigns.user
    blueprint_id = String.to_integer(id)

    cond do
      MapSet.member?(socket.assigns.generating_ids, blueprint_id) ->
        {:noreply, socket}

      Subscriptions.check_quota(user.id, "meal_plan") == {:error, :quota_exceeded} ->
        {:noreply,
         put_flash(socket, :error, "You've reached your meal-plan generation limit for this month.")}

      true ->
        start_generation(socket, blueprint_id)
    end
  end

  @impl true
  def handle_event("open_import", %{"id" => id}, socket) do
    plan_id = String.to_integer(id)
    today = Date.utc_today()

    {:noreply,
     socket
     |> assign(:import_plan_id, plan_id)
     |> assign(
       :import_form,
       to_form(
         %{
           "start_date" => Date.to_iso8601(today),
           "target_user_id" => Integer.to_string(socket.assigns.user.id)
         },
         as: :import
       )
     )}
  end

  @impl true
  def handle_event("close_import", _params, socket) do
    {:noreply, socket |> assign(:import_plan_id, nil) |> assign(:import_form, nil)}
  end

  @impl true
  def handle_event("import_plan", %{"import" => params}, socket) do
    user = socket.assigns.user
    start_date = params["start_date"]

    with plan_id when not is_nil(plan_id) <- socket.assigns.import_plan_id,
         {:ok, date} <- Date.from_iso8601(start_date),
         {:ok, target} <- resolve_import_target(socket, params["target_user_id"]),
         plan <- MealBlueprints.get_plan!(user.id, plan_id) do
      {:ok, created, skipped, deleted} =
        MealBlueprints.import_plan_to_calendar(target.id, plan, date)

      {:noreply,
       socket
       |> assign(:import_plan_id, nil)
       |> assign(:import_form, nil)
       |> put_flash(:info, import_message(created, skipped, deleted, target, user))
       |> reload_blueprints()}
    else
      _ ->
        {:noreply,
         socket
         |> assign(:import_plan_id, nil)
         |> assign(:import_form, nil)
         |> put_flash(:error, "Could not import this plan.")}
    end
  end

  @impl true
  def handle_event("delete_plan", %{"id" => id}, socket) do
    user = socket.assigns.user
    plan_id = String.to_integer(id)

    case safe_get_plan(user.id, plan_id) do
      %_{} = plan ->
        {:ok, _} = MealBlueprints.delete_plan(plan)

        {:noreply,
         socket
         |> assign(:expanded_plans, MapSet.delete(socket.assigns.expanded_plans, plan_id))
         |> put_flash(:info, "Plan deleted.")
         |> reload_blueprints()}

      nil ->
        {:noreply, put_flash(socket, :error, "Plan not found.")}
    end
  end

  @impl true
  def handle_event("edit_plan_meal", %{"id" => id}, socket) do
    meal = MealBlueprints.get_plan_meal!(socket.assigns.user.id, String.to_integer(id))

    {:noreply,
     socket
     |> assign(:editing_plan_meal, meal)
     |> assign(:meal_search_results, [])}
  end

  @impl true
  def handle_event("close_meal_edit", _params, socket) do
    {:noreply, socket |> assign(:editing_plan_meal, nil) |> assign(:meal_search_results, [])}
  end

  @impl true
  def handle_event("meal_search", %{"query" => query}, socket) do
    results =
      case String.trim(query) do
        "" -> []
        q -> Mehungry.Search.RecipeVectorSearch.search(q, limit: 10)
      end

    {:noreply, assign(socket, :meal_search_results, results)}
  end

  @impl true
  def handle_event("swap_meal_recipe", %{"recipe_id" => recipe_id}, socket) do
    meal = socket.assigns.editing_plan_meal

    {:ok, _} =
      MealBlueprints.update_plan_meal(meal, %{
        recipe_id: String.to_integer(recipe_id),
        cooking_portions: meal.cooking_portions || 2,
        ingredient_id: nil,
        quantity: nil,
        measurement_unit_id: nil,
        ingredient_portion_id: nil
      })

    {:noreply,
     socket
     |> assign(:editing_plan_meal, nil)
     |> assign(:meal_search_results, [])
     |> put_flash(:info, "Meal updated.")
     |> reload_blueprints()}
  end

  @impl true
  def handle_event("save_meal_fields", %{"meal" => params}, socket) do
    meal = socket.assigns.editing_plan_meal
    attrs = meal_field_attrs(meal, params)

    case MealBlueprints.update_plan_meal(meal, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:editing_plan_meal, nil)
         |> put_flash(:info, "Meal updated.")
         |> reload_blueprints()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update the meal.")}
    end
  end

  @impl true
  def handle_event("delete_plan_meal", %{"id" => id}, socket) do
    meal = MealBlueprints.get_plan_meal!(socket.assigns.user.id, String.to_integer(id))
    {:ok, _} = MealBlueprints.delete_plan_meal(meal)

    {:noreply, socket |> put_flash(:info, "Meal removed.") |> reload_blueprints()}
  end

  # A recipe meal edits its cooking portions; an ingredient meal edits quantity.
  defp meal_field_attrs(%{recipe_id: rid}, params) when not is_nil(rid) do
    %{cooking_portions: parse_int(params["cooking_portions"]) || 2}
  end

  defp meal_field_attrs(_meal, params) do
    %{quantity: parse_float(params["quantity"]) || 1.0}
  end

  defp parse_int(nil), do: nil

  defp parse_int(v) do
    case Integer.parse(to_string(v)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_float(nil), do: nil

  defp parse_float(v) do
    case Float.parse(to_string(v)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp start_generation(socket, blueprint_id) do
    user = socket.assigns.user
    blueprint = MealBlueprints.get_blueprint!(user.id, blueprint_id)
    start_date = Date.utc_today()

    {:ok, plan} =
      MealBlueprints.create_plan(%{
        name: "Plan · #{Calendar.strftime(start_date, "%b %-d, %Y")}",
        start_date: start_date,
        status: "generating",
        blueprint_id: blueprint.id,
        user_id: user.id
      })

    preferences = MealBlueprints.blueprint_preferences(blueprint)
    recipes = Food.list_user_recipes_for_selection(user)

    task =
      Task.async(fn ->
        Mehungry.AI.MealPlanGenerator.generate_entries(
          preferences,
          recipes,
          start_date,
          user.id,
          blueprint
        )
      end)

    {:noreply,
     socket
     |> assign(:generating_ids, MapSet.put(socket.assigns.generating_ids, blueprint_id))
     |> assign(:gen_tasks, Map.put(socket.assigns.gen_tasks, task.ref, {blueprint_id, plan.id}))
     |> assign(:expanded_plans, MapSet.put(socket.assigns.expanded_plans, plan.id))
     |> reload_blueprints()}
  end

  # ── async generation result ────────────────────────────────────────────────────

  @impl true
  def handle_info({ref, result}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    case Map.pop(socket.assigns.gen_tasks, ref) do
      {nil, _} ->
        {:noreply, socket}

      {{blueprint_id, plan_id}, gen_tasks} ->
        user = socket.assigns.user
        plan = MealBlueprints.get_plan!(user.id, plan_id)

        socket =
          case result do
            {:ok, entries} ->
              MealBlueprints.store_plan_meals(plan, entries)
              Subscriptions.record_usage(user.id, "meal_plan")

              put_flash(
                socket,
                :info,
                "Generated a #{length(entries)}-meal plan. Review it, then import to your calendar."
              )

            {:error, reason} ->
              MealBlueprints.update_plan(plan, %{status: "failed", error: to_string(reason)})
              put_flash(socket, :error, "Could not generate plan: #{reason}")
          end

        {:noreply,
         socket
         |> assign(:gen_tasks, gen_tasks)
         |> assign(:generating_ids, MapSet.delete(socket.assigns.generating_ids, blueprint_id))
         |> reload_blueprints()}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _, _reason}, socket) when is_reference(ref) do
    case Map.pop(socket.assigns.gen_tasks, ref) do
      {nil, _} ->
        {:noreply, socket}

      {{blueprint_id, plan_id}, gen_tasks} ->
        user = socket.assigns.user

        with %_{} = plan <- safe_get_plan(user.id, plan_id) do
          MealBlueprints.update_plan(plan, %{status: "failed", error: "generation crashed"})
        end

        {:noreply,
         socket
         |> assign(:gen_tasks, gen_tasks)
         |> assign(:generating_ids, MapSet.delete(socket.assigns.generating_ids, blueprint_id))
         |> put_flash(:error, "Plan generation failed unexpectedly.")
         |> reload_blueprints()}
    end
  end

  # ── helpers ────────────────────────────────────────────────────────────────────

  defp reload_blueprints(socket) do
    user = socket.assigns.user
    blueprints = MealBlueprints.list_blueprints_for_user(user.id)

    socket
    |> assign(:blueprints, blueprints)
    |> assign(:plans_by_blueprint, load_plans(user.id, blueprints))
  end

  defp load_plans(user_id, blueprints) do
    Map.new(blueprints, fn bp ->
      {bp.id, MealBlueprints.list_plans_for_blueprint(user_id, bp.id)}
    end)
  end

  defp safe_get_plan(user_id, plan_id) do
    MealBlueprints.get_plan!(user_id, plan_id)
  rescue
    Ecto.NoResultsError -> nil
  end

  # The nutritionist's assigned clients (platform users with a real calendar),
  # the pool the plan can be imported for alongside the nutritionist themselves.
  defp load_client_targets(professional_id) do
    professional_id
    |> Professionals.list_clients()
    |> Enum.map(& &1.client)
    |> Enum.reject(&is_nil/1)
  end

  # Select options for the import target: the nutritionist first, then each client.
  defp client_options(clients, user) do
    [{"Myself", Integer.to_string(user.id)}] ++
      Enum.map(clients, fn client ->
        {client_label(client), Integer.to_string(client.id)}
      end)
  end

  defp client_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp client_label(%{email: email}) when is_binary(email), do: email
  defp client_label(_), do: "Client"

  # Resolves (and authorizes) the chosen import target to a %User{}: only the
  # nutritionist themselves or one of their assigned clients is allowed.
  defp resolve_import_target(socket, target_user_id) do
    user = socket.assigns.user

    case target_user_id do
      nil ->
        {:ok, user}

      "" ->
        {:ok, user}

      id_str ->
        with {id, ""} <- Integer.parse(id_str),
             target when not is_nil(target) <- find_import_target(socket, id) do
          {:ok, target}
        else
          _ -> :error
        end
    end
  end

  defp find_import_target(socket, id) do
    user = socket.assigns.user

    if id == user.id do
      user
    else
      Enum.find(socket.assigns.clients, &(&1.id == id))
    end
  end

  defp import_message(created, skipped, deleted, target, user) do
    whose = if target.id == user.id, do: "your calendar", else: "#{client_label(target)}'s calendar"

    [
      "Added #{created} meals to #{whose}",
      deleted > 0 && ", replacing #{deleted} existing meal#{plural(deleted)} that week",
      skipped > 0 && " (#{skipped} skipped)",
      "."
    ]
    |> Enum.reject(&(&1 == false))
    |> Enum.join()
  end

  defp plural(1), do: ""
  defp plural(_), do: "s"
end
