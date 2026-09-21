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
                    <.day_header
                      day_index={day_index}
                      report={day_report(@compat, plan.id, day_index)}
                    />
                    <div class="space-y-1.5">
                      <div :for={m <- meals} class="flex items-center gap-2 group">
                        <span class="text-parchment-dim text-[11px] w-24 shrink-0">
                          {MealType.label(m.meal_type)}
                        </span>
                        <div class="min-w-0 flex-1">
                          <.recipe_line m={m} />
                          <.ingredient_line m={m} />
                          <.meal_badges report={meal_report(@compat, plan.id, m.id)} />
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
        <.live_component
          module={MehungryWeb.MealBlueprintLive.PlanMealFormComponent}
          id={"plan-meal-form-#{@editing_plan_meal.id}"}
          plan_meal={@editing_plan_meal}
          current_user={@user}
        />
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

  # ── compatibility indicators ────────────────────────────────────────────────

  # Day heading + whole-day blueprint indicators: calorie over/under target,
  # a violation count, and any required compound/nutrient no meal covers today.
  attr(:day_index, :any, required: true)
  attr(:report, :any, default: nil)

  defp day_header(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-1.5 mb-1.5">
      <span class="text-parchment-dim text-xs font-semibold uppercase tracking-wide">
        Day {@day_index}
      </span>
      <.calorie_badge :if={@report} report={@report} />
      <span
        :if={@report && @report["violation_count"] > 0}
        class="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full bg-paprika/20 text-paprika"
        title={"#{@report.violation_count} blueprint violation(s) among today's meals"}
      >
        ⚠ {@report.violation_count}
      </span>
      <span
        :for={miss <- missing_required(@report)}
        class="text-[10px] px-1.5 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim normal-case"
        title={"Blueprint requires #{miss}, but no meal today includes it"}
      >
        missing: {miss}
      </span>
    </div>
    """
  end

  defp missing_required(%{"missing_required" => list}) when is_list(list), do: list
  defp missing_required(_), do: []

  # Day energy vs the blueprint's calorie aim, hidden when the day has no target.
  attr(:report, :map, required: true)

  defp calorie_badge(%{report: %{"calorie_status" => "no_target"}} = assigns), do: ~H""

  defp calorie_badge(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full [font-variant-numeric:tabular-nums]",
        calorie_badge_class(@report["calorie_status"])
      ]}
      title={calorie_tooltip(@report)}
    >
      {@report["calorie_total"]} / {@report["calorie_target"]} kcal
      <span :if={@report["calorie_status"] != "ok"}>{calorie_delta_label(@report["calorie_delta"])}</span>
    </span>
    """
  end

  defp calorie_badge_class("over"), do: "bg-paprika/20 text-paprika"
  defp calorie_badge_class("under"), do: "bg-amber-500/20 text-amber-400"
  defp calorie_badge_class("ok"), do: "bg-basil/20 text-basil"
  defp calorie_badge_class(_), do: "bg-ink-panel2 text-parchment-dim"

  defp calorie_delta_label(delta) when is_integer(delta) and delta > 0, do: "· +#{delta}"
  defp calorie_delta_label(delta) when is_integer(delta), do: "· #{delta}"
  defp calorie_delta_label(_), do: ""

  defp calorie_tooltip(%{"calorie_status" => :over, "calorie_delta" => d}),
    do: "#{d} kcal over the day's calorie target"

  defp calorie_tooltip(%{calorie_status: :under, calorie_delta: d}),
    do: "#{abs(d)} kcal under the day's calorie target"

  defp calorie_tooltip(_), do: "On the day's calorie target"

  # Per-meal badges: red for an avoided compound/nutrient present, green for a
  # required one. Hover (native title) explains each.
  attr(:report, :any, default: nil)

  defp meal_badges(%{report: nil} = assigns), do: ~H""
  defp meal_badges(%{report: %{"violations" => [], "matches" => []}} = assigns), do: ~H""

  defp meal_badges(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-1 mt-1">
      <.compat_badge :for={e <- @report.violations} entry={e} />
      <.compat_badge :for={e <- @report.matches} entry={e} />
    </div>
    """
  end

  attr(:entry, :map, required: true)

  defp compat_badge(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full cursor-help normal-case",
        badge_class(@entry.direction)
      ]}
      title={badge_tooltip(@entry)}
    >
      {badge_icon(@entry.direction)} {@entry.name}
    </span>
    """
  end

  defp badge_class(:avoid), do: "bg-paprika/20 text-paprika border border-paprika/40"
  defp badge_class(:required), do: "bg-basil/20 text-basil border border-basil/40"

  defp badge_icon(:avoid), do: "⚠"
  defp badge_icon(:required), do: "✓"

  defp badge_tooltip(%{direction: :avoid, via: :family, name: name}),
    do: "Contains #{name} — a compound family this blueprint says to avoid"

  defp badge_tooltip(%{direction: :required, via: :family, name: name}),
    do: "Includes #{name} — a compound family this blueprint requires"

  defp badge_tooltip(%{direction: :avoid, kind: :compound, name: name}),
    do: "Contains #{name}, which this blueprint says to avoid"

  defp badge_tooltip(%{direction: :avoid, kind: :nutrient, name: name}),
    do: "High in #{name}, which this blueprint says to avoid"

  defp badge_tooltip(%{direction: :required, kind: :compound, name: name}),
    do: "Includes #{name}, which this blueprint requires"

  defp badge_tooltip(%{direction: :required, kind: :nutrient, name: name}),
    do: "Provides #{name}, which this blueprint requires"

  # Compatibility lookups into the @compat map (keyed by plan id).
  defp day_report(compat, plan_id, day_index) do
    compat
    |> Map.get(plan_id, %{})
    |> Map.get("days", %{})
    |> Map.get(Integer.to_string(day_index))
  end

  defp meal_report(compat, plan_id, meal_id) do
    compat
    |> Map.get(plan_id, %{})
    |> Map.get("meals", %{})
    |> Map.get(Integer.to_string(meal_id))
  end

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
     |> assign(:compat, %{})
     |> assign(:generating_ids, MapSet.new())
     |> assign(:gen_tasks, %{})
     |> assign(:import_plan_id, nil)
     |> assign(:import_form, nil)
     |> assign(:editing_plan_meal, nil)}
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
      case MealBlueprints.create_blueprint(MealBlueprints.default_blueprint_attrs(user.id, name)) do
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

    {:noreply, socket |> assign(:expanded_plans, expanded) |> refresh_compat()}
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
         put_flash(
           socket,
           :error,
           "You've reached your meal-plan generation limit for this month."
         )}

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
    {:noreply, assign(socket, :editing_plan_meal, meal)}
  end

  @impl true
  def handle_event("close_meal_edit", _params, socket) do
    {:noreply, assign(socket, :editing_plan_meal, nil)}
  end

  @impl true
  def handle_event("delete_plan_meal", %{"id" => id}, socket) do
    meal = MealBlueprints.get_plan_meal!(socket.assigns.user.id, String.to_integer(id))
    {:ok, _} = MealBlueprints.delete_plan_meal(meal)

    {:noreply, socket |> put_flash(:info, "Meal removed.") |> reload_blueprints()}
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

  # ── plan-meal edit form (PlanMealFormComponent) ─────────────────────────────────

  @impl true
  def handle_info({:plan_meal_saved, %{flash: flash}}, socket) do
    # Reload closes the modal and re-runs refresh_compat, so the day badges update.
    {:noreply,
     socket
     |> assign(:editing_plan_meal, nil)
     |> put_flash(:info, flash)
     |> reload_blueprints()}
  end

  @impl true
  def handle_info({:plan_meal_edit_cancelled}, socket) do
    {:noreply, assign(socket, :editing_plan_meal, nil)}
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
    |> refresh_compat()
  end

  # Recomputes the blueprint-compatibility report for every currently-expanded,
  # completed plan (cheap: usually one open at a time). Keyed by plan id so the
  # render can look up each day/meal's badges. Runs after any edit that changes a
  # plan's meals, so indicators stay live.
  defp refresh_compat(socket) do
    user = socket.assigns.user
    plans_by_bp = socket.assigns.plans_by_blueprint

    expanded = socket.assigns.expanded_plans

    compat =
      for {bp_id, plans} <- plans_by_bp,
          plan <- plans,
          MapSet.member?(expanded, plan.id),
          plan.status == "completed",
          report = safe_compat(user.id, bp_id, plan.id),
          not is_nil(report),
          into: %{} do
        {plan.id, report}
      end

    assign(socket, :compat, compat)
  end

  defp safe_compat(user_id, blueprint_id, plan_id) do
    plan = MealBlueprints.get_plan!(user_id, plan_id)
    plan.compatibility
  rescue
    _ -> nil
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
    whose =
      if target.id == user.id, do: "your calendar", else: "#{client_label(target)}'s calendar"

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
