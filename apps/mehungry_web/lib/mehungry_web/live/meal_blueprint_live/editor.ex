defmodule MehungryWeb.MealBlueprintLive.Editor do
  @moduledoc """
  Full-page editor for one blueprint.

  Three levels of targets:

  * **Blueprint** — an optional disease/`Health.Condition` (native select). Picking
    one auto-suggests that condition's recommended bioactive compounds into every
    day's compound picker (`Health` links conditions to compounds only, so
    nutrients stay manual).
  * **Day** — the "general" targets: required nutrients and required compounds,
    each a searchable chip multi-select sourced from the DB (persisted as name
    arrays), plus free-text preferred foods and the per-day calorie aim.
  * **Meal** — a macro percentage split (protein / carbs / fats, always totalling
    100 %) + a note.

  The two chip pickers are managed as server events (`add_tag` / `remove_tag` /
  `search_tag`) on the working changeset — the same apply-changes-then-rebuild
  pattern the copy shortcuts use — and each renders hidden `name[...][]` inputs so
  the selections survive form submit.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Accounts
  alias Mehungry.Food
  alias Mehungry.Health
  alias Mehungry.MealBlueprints
  alias Mehungry.History.MealType

  # ── render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-ink text-parchment pb-20">
      <div class="container max-w-3xl mx-auto px-4 py-8">
        <div class="flex items-center justify-between mb-6">
          <div class="min-w-0">
            <.link
              navigate={~p"/nutritionist/blueprints"}
              class="text-parchment-dim text-sm hover:text-parchment"
            >
              ← Blueprints
            </.link>
            <h1 class="text-2xl font-display font-medium text-parchment truncate">
              {@blueprint.name}
            </h1>
          </div>
        </div>

        <.form for={@form} id="blueprint-form" phx-change="validate" phx-submit="save">
          <div class="bg-ink-panel rounded-xl border border-ink-panel2 p-4 mb-4 space-y-4">
            <div>
              <label class="block text-sm text-parchment-dim mb-1">Name</label>
              <input
                type="text"
                name={@form[:name].name}
                value={@form[:name].value}
                placeholder="Blueprint name"
                class="w-full rounded-lg bg-ink border border-ink-panel2 text-parchment text-sm px-3 py-2"
              />
              <p :for={msg <- name_errors(@form)} class="text-paprika text-xs mt-1">{msg}</p>
            </div>

            <div>
              <label class="block text-sm text-parchment-dim mb-1">Visibility</label>
              <select
                name="blueprint[visibility]"
                class="w-full rounded-lg bg-ink border border-ink-panel2 text-parchment text-sm px-3 py-2"
              >
                <option value="private" selected={@form[:visibility].value in [nil, "private"]}>
                  Private — only you can see it
                </option>
                <option value="public" selected={@form[:visibility].value == "public"}>
                  Public — browsable & shareable
                </option>
              </select>
              <p
                :if={@blueprint.visibility == "public" && @blueprint.slug}
                class="text-parchment-dim text-xs mt-1"
              >
                Public page:
                <.link
                  navigate={~p"/blueprints/#{@blueprint.slug}"}
                  class="text-basil hover:underline"
                >
                  /blueprints/{@blueprint.slug}
                </.link>
              </p>
            </div>

            <div>
              <label class="block text-sm text-parchment-dim mb-1">Condition (disease)</label>
              <select
                name="blueprint[condition_id]"
                class="w-full rounded-lg bg-ink border border-ink-panel2 text-parchment text-sm px-3 py-2"
              >
                <option value="">None</option>
                <option
                  :for={{id, name} <- @condition_items}
                  value={id}
                  selected={to_string(@form[:condition_id].value) == id}
                >
                  {name}
                </option>
              </select>
              <p class="text-parchment-dim text-xs mt-1">
                Everything in this panel applies across every day. Selecting a condition
                suggests its recommended compounds below.
              </p>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <.tag_multiselect
                form={@form}
                field={:required_nutrients}
                label="Required nutrients"
                placeholder="Search nutrients…"
                tone={:required}
                active_search={@active_search}
              />
              <.tag_multiselect
                form={@form}
                field={:avoid_nutrients}
                label="Avoid nutrients"
                placeholder="Search nutrients…"
                tone={:avoid}
                active_search={@active_search}
              />
              <.tag_multiselect
                form={@form}
                field={:required_compounds}
                label="Required compounds"
                placeholder="Search compounds…"
                tone={:required}
                active_search={@active_search}
              />
              <.tag_multiselect
                form={@form}
                field={:avoid_compounds}
                label="Avoid compounds"
                placeholder="Search compounds…"
                tone={:avoid}
                active_search={@active_search}
              />
            </div>

            <div>
              <label class="block text-sm text-parchment-dim mb-1">Preferred foods</label>
              <input
                type="text"
                name={@form[:preferred_foods].name}
                value={tags_value(@form[:preferred_foods].value)}
                placeholder="nuts, dairy, eggs, meat"
                phx-debounce="blur"
                class="w-full rounded-lg bg-ink border border-ink-panel2 text-parchment text-sm px-3 py-2"
              />
            </div>
          </div>

          <.inputs_for :let={df} field={@form[:days]}>
            <details
              class="bg-ink-panel rounded-xl border border-ink-panel2 mb-3"
              open={df.index == 0}
            >
              <summary class="cursor-pointer select-none px-4 py-3 flex items-center justify-between">
                <span class="font-semibold text-parchment">Day {day_index(df)}</span>
                <span class="text-parchment-dim text-xs">5 meals</span>
              </summary>

              <div class="px-4 pb-4 space-y-4">
                <input type="hidden" name={df[:day_index].name} value={df[:day_index].value} />

                <div class="flex items-end gap-3">
                  <.input
                    field={df[:total_calorie_target]}
                    type="number"
                    label="Total calorie aim (day)"
                    min="0"
                  />
                  <button
                    type="button"
                    phx-click="copy_day_to_all"
                    phx-value-day_index={day_index(df)}
                    class="mb-2 px-3 py-1.5 rounded-lg text-xs bg-ink-panel2 text-parchment-dim hover:text-parchment transition"
                  >
                    Copy this day to all days
                  </button>
                </div>

                <.inputs_for :let={mf} field={df[:meals]}>
                  <div class="rounded-lg border border-ink-panel2 p-3">
                    <input type="hidden" name={mf[:meal_type].name} value={mf[:meal_type].value} />

                    <div class="flex items-center justify-between mb-3">
                      <h3 class="font-semibold text-basil">{MealType.label(mf[:meal_type].value)}</h3>
                      <button
                        type="button"
                        phx-click="copy_meal_across_week"
                        phx-value-day_index={day_index(df)}
                        phx-value-meal_type={mf[:meal_type].value}
                        class="px-2 py-1 rounded text-xs text-parchment-dim hover:text-parchment transition"
                      >
                        Copy to every day
                      </button>
                    </div>

                    <div class="grid grid-cols-3 gap-2">
                      <.input
                        field={mf[:protein_pct]}
                        type="number"
                        step="1"
                        min="0"
                        max="100"
                        label="Protein %"
                      />
                      <.input
                        field={mf[:carbs_pct]}
                        type="number"
                        step="1"
                        min="0"
                        max="100"
                        label="Carbs %"
                      />
                      <.input
                        field={mf[:fats_pct]}
                        type="number"
                        step="1"
                        min="0"
                        max="100"
                        label="Fats %"
                      />
                    </div>

                    <p class={[
                      "text-xs mt-1",
                      if(macro_total(mf) == 100, do: "text-parchment-dim", else: "text-paprika")
                    ]}>
                      Total: {macro_total(mf)}%
                      <span :if={macro_total(mf) != 100}>(must be 100%)</span>
                    </p>

                    <div class="mt-2">
                      <label class="block text-sm text-parchment-dim mb-1">Note</label>
                      <input
                        type="text"
                        name={mf[:note].name}
                        value={mf[:note].value}
                        phx-debounce="blur"
                        class="w-full rounded-lg bg-ink border border-ink-panel2 text-parchment text-sm px-3 py-2"
                      />
                    </div>
                  </div>
                </.inputs_for>
              </div>
            </details>
          </.inputs_for>

          <div class="sticky bottom-0 bg-ink/90 backdrop-blur py-3 flex justify-end gap-2">
            <.link
              navigate={~p"/nutritionist/blueprints"}
              class="px-4 py-2 rounded-lg text-parchment-dim hover:text-parchment"
            >
              Cancel
            </.link>
            <.button type="primary">Save blueprint</.button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  # A day-level chip multi-select: current chips (with remove), a search box, and
  # a filtered dropdown. Selections live on the changeset; hidden `[]` inputs
  # (incl. an empty sentinel so a fully-cleared field still posts) carry them on
  # submit — `BlueprintDay`'s changeset trims the blank.
  #
  # `phx-click-away` lives on the dropdown `<ul>` (not the widget root): only the
  # single active widget renders a `<ul>`, so exactly one click-away handler is
  # live at a time. (One per widget would let the other pickers' handlers close
  # the dropdown the instant you interact with any one of them.)
  attr :form, :any, required: true
  attr :field, :atom, required: true
  attr :label, :string, required: true
  attr :placeholder, :string, required: true
  attr :tone, :atom, default: :required
  attr :active_search, :any, required: true

  defp tag_multiselect(assigns) do
    assigns =
      assigns
      |> assign(:selected, tag_list(assigns.form[assigns.field].value))
      |> assign(:name, assigns.form[assigns.field].name <> "[]")
      |> assign(:chip_class, chip_class(assigns.tone))

    ~H"""
    <div class="relative">
      <label class="block text-sm text-parchment-dim mb-1">{@label}</label>

      <input type="hidden" name={@name} value="" />
      <div class="flex flex-wrap gap-1.5 mb-1.5">
        <span
          :for={tag <- @selected}
          class={"inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs #{@chip_class}"}
        >
          <input type="hidden" name={@name} value={tag} />
          {tag}
          <button
            type="button"
            phx-click="remove_tag"
            phx-value-field={@field}
            phx-value-tag={tag}
            class="opacity-70 hover:opacity-100"
          >
            ×
          </button>
        </span>
      </div>

      <input
        type="text"
        autocomplete="off"
        placeholder={@placeholder}
        phx-keyup="search_tag"
        phx-value-field={@field}
        phx-focus="search_tag"
        class="w-full rounded-lg bg-ink border border-ink-panel2 text-parchment text-sm px-3 py-2"
      />

      <ul
        :if={search_open?(@active_search, @field)}
        phx-click-away="close_search"
        class="absolute z-50 left-0 right-0 mt-1 max-h-48 overflow-y-auto rounded-lg bg-ink-panel border border-ink-panel2 shadow-lg"
      >
        <li :if={@active_search.results == []} class="px-3 py-2 text-parchment-dim text-sm">
          No matches
        </li>
        <li
          :for={{value, item_label} <- @active_search.results}
          phx-click="add_tag"
          phx-value-field={@field}
          phx-value-tag={value}
          class="px-3 py-2 text-sm text-parchment hover:bg-ink-panel2 cursor-pointer"
        >
          {item_label}
        </li>
      </ul>
    </div>
    """
  end

  defp chip_class(:avoid), do: "bg-paprika/20 text-paprika border border-paprika/40"
  defp chip_class(_), do: "bg-ink-panel2 text-parchment"

  # Translated validation messages for the name field (shown after a validate).
  defp name_errors(form) do
    Enum.map(form[:name].errors, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp day_index(df), do: df[:day_index].value

  # Live sum of a meal's three macro percentages (for the "Total: X%" hint).
  defp macro_total(mf) do
    [:protein_pct, :carbs_pct, :fats_pct]
    |> Enum.map(&to_int(mf[&1].value))
    |> Enum.sum()
  end

  defp to_int(value) when is_integer(value), do: value

  defp to_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp to_int(_), do: 0

  defp search_open?(%{field: f}, field), do: to_string(f) == to_string(field)
  defp search_open?(_, _), do: false

  # Renders a comma-separated tag string (for the free-text preferred_foods box).
  defp tags_value(value) when is_list(value), do: Enum.join(value, ", ")
  defp tags_value(value) when is_binary(value), do: value
  defp tags_value(_), do: ""

  # Drop blank entries — notably the hidden "" sentinel each picker posts, which
  # Phoenix reflects back into `form[field].value` from the raw params (the
  # cleaned changeset value equals the data, so Ecto drops the change and the form
  # falls back to the submitted param). Without this it renders as an empty chip.
  defp tag_list(value) when is_list(value), do: Enum.reject(value, &blank_tag?/1)
  defp tag_list(_), do: []

  defp blank_tag?(v), do: v |> to_string() |> String.trim() == ""

  # ── lifecycle ───────────────────────────────────────────────────────────────

  @impl true
  def mount(%{"id" => id}, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])
    blueprint = MealBlueprints.get_blueprint!(user.id, id)

    {:ok,
     socket
     |> assign(:user, user)
     |> assign(:blueprint, blueprint)
     |> assign(:condition_id, blueprint.condition_id)
     |> assign(:active_search, nil)
     |> assign(:nutrient_items, nutrient_items())
     |> assign(:compound_items, compound_items())
     |> assign(:condition_items, condition_items())
     |> assign(:page_title, blueprint.name)
     |> assign(:form, to_form(MealBlueprints.change_blueprint(blueprint), as: :blueprint))}
  end

  # Preloaded, bounded option lists ({value, label}); value == persisted string.
  defp nutrient_items do
    Food.list_nutrients()
    |> Enum.map(&{&1.name, &1.name})
    |> Enum.uniq()
    |> Enum.sort_by(fn {_v, l} -> l end)
  end

  defp compound_items do
    families = Enum.map(Food.Compounds.family_labels(), fn {_type, label} -> {label, label} end)
    specific = Enum.map(Food.list_compounds(), &{&1.name, &1.name})

    (families ++ specific)
    |> Enum.uniq_by(fn {v, _l} -> v end)
  end

  defp condition_items do
    Enum.map(Health.list_conditions(), &{to_string(&1.id), &1.name})
  end

  # ── events ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("validate", %{"blueprint" => params}, socket) do
    new_condition_id = parse_condition_id(params["condition_id"])

    changeset =
      socket.assigns.blueprint
      |> MealBlueprints.change_blueprint(normalize_params(params))
      |> Map.put(:action, :validate)

    changeset = maybe_suggest_compounds(changeset, new_condition_id, socket.assigns.condition_id)

    {:noreply,
     socket
     |> assign(:condition_id, new_condition_id)
     |> assign(:form, to_form(changeset, as: :blueprint))}
  end

  @impl true
  def handle_event("save", %{"blueprint" => params}, socket) do
    case MealBlueprints.update_blueprint(socket.assigns.blueprint, normalize_params(params)) do
      {:ok, _blueprint} ->
        {:noreply,
         socket
         |> put_flash(:info, "Blueprint saved.")
         |> push_navigate(to: ~p"/nutritionist/blueprints")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Please fix the highlighted fields.")
         |> assign(:form, to_form(changeset, as: :blueprint))}
    end
  end

  @impl true
  def handle_event("search_tag", %{"field" => field} = params, socket) do
    field = String.to_existing_atom(field)
    query = Map.get(params, "value", "")

    selected = tag_list(Map.get(current_data(socket), field))
    results = filter_items(items_for(socket, field), query, selected)

    {:noreply, assign(socket, :active_search, %{field: field, results: results})}
  end

  @impl true
  def handle_event("add_tag", %{"field" => field, "tag" => value}, socket) do
    field = String.to_existing_atom(field)

    socket =
      socket
      |> update_field(field, fn cur -> Enum.uniq(tag_list(cur) ++ [value]) end)
      |> assign(:active_search, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("remove_tag", %{"field" => field, "tag" => value}, socket) do
    field = String.to_existing_atom(field)

    {:noreply,
     update_field(socket, field, fn cur -> Enum.reject(tag_list(cur), &(&1 == value)) end)}
  end

  @impl true
  def handle_event("close_search", _params, socket) do
    {:noreply, assign(socket, :active_search, nil)}
  end

  @impl true
  def handle_event("copy_day_to_all", %{"day_index" => di}, socket) do
    di = String.to_integer(di)
    data = current_data(socket)
    source = Enum.find(data.days, &(&1.day_index == di))
    days = Enum.map(data.days, &copy_day_from_source(&1, di, source))

    {:noreply, assign_data(socket, %{data | days: days})}
  end

  @impl true
  def handle_event("copy_meal_across_week", %{"day_index" => di, "meal_type" => mt}, socket) do
    di = String.to_integer(di)
    data = current_data(socket)
    source_day = Enum.find(data.days, &(&1.day_index == di))
    source_meal = Enum.find(source_day.meals, &(&1.meal_type == mt))
    days = Enum.map(data.days, &copy_slot_from_source(&1, mt, source_meal))

    {:noreply, assign_data(socket, %{data | days: days})}
  end

  # ── search helpers ────────────────────────────────────────────────────────

  defp items_for(socket, field) when field in [:required_nutrients, :avoid_nutrients],
    do: socket.assigns.nutrient_items

  defp items_for(socket, field) when field in [:required_compounds, :avoid_compounds],
    do: socket.assigns.compound_items

  # Case-insensitive substring match on the label, excluding already-picked
  # values; capped so the dropdown stays bounded.
  defp filter_items(items, query, exclude) do
    q = query |> to_string() |> String.trim() |> String.downcase()

    items
    |> Enum.reject(fn {value, _label} -> value in exclude end)
    |> Enum.filter(fn {_value, label} ->
      q == "" or String.contains?(String.downcase(label), q)
    end)
    |> Enum.take(20)
  end

  # ── condition auto-suggest ─────────────────────────────────────────────────

  defp parse_condition_id(value) do
    case value do
      nil -> nil
      "" -> nil
      v -> String.to_integer(v)
    end
  end

  # When the disease selection changes to a real condition, union its recommended
  # compounds AND nutrients into the blueprint — encouraged ones into the
  # required_* lists, discouraged ones into the avoid_* lists (editable afterwards).
  defp maybe_suggest_compounds(changeset, new_id, prev_id)
       when is_integer(new_id) and new_id != prev_id do
    compounds = MealBlueprints.recommended_compounds_for_condition(new_id)
    nutrients = MealBlueprints.recommended_nutrients_for_condition(new_id)

    case {compounds, nutrients} do
      {%{required: [], avoid: []}, %{required: [], avoid: []}} ->
        changeset

      {%{required: c_req, avoid: c_avoid}, %{required: n_req, avoid: n_avoid}} ->
        data = Ecto.Changeset.apply_changes(changeset)

        MealBlueprints.change_blueprint(%{
          data
          | required_compounds: Enum.uniq(tag_list(data.required_compounds) ++ c_req),
            avoid_compounds: Enum.uniq(tag_list(data.avoid_compounds) ++ c_avoid),
            required_nutrients: Enum.uniq(tag_list(data.required_nutrients) ++ n_req),
            avoid_nutrients: Enum.uniq(tag_list(data.avoid_nutrients) ++ n_avoid)
        })
    end
  end

  defp maybe_suggest_compounds(changeset, _new_id, _prev_id), do: changeset

  # ── changeset mutation helpers ─────────────────────────────────────────────

  # Current edited state as a %Blueprint{} struct (applies pending form changes).
  defp current_data(socket), do: Ecto.Changeset.apply_changes(socket.assigns.form.source)

  defp assign_data(socket, %_{} = data) do
    assign(socket, :form, to_form(MealBlueprints.change_blueprint(data), as: :blueprint))
  end

  defp update_field(socket, field, fun) do
    data = current_data(socket)
    assign_data(socket, Map.update!(data, field, fn cur -> fun.(cur) end))
  end

  defp copy_day_from_source(day, source_index, source) do
    if day.day_index == source_index, do: day, else: copy_day_targets(day, source)
  end

  # Overwrite the given `meal_type` slot on this day with the source meal's macros.
  defp copy_slot_from_source(day, meal_type, source_meal) do
    meals =
      Enum.map(day.meals, fn meal ->
        if meal.meal_type == meal_type, do: merge_meal_targets(meal, source_meal), else: meal
      end)

    %{day | meals: meals}
  end

  defp copy_day_targets(day, source) do
    by_type = Map.new(source.meals, &{&1.meal_type, &1})

    meals =
      Enum.map(day.meals, fn meal ->
        case Map.get(by_type, meal.meal_type) do
          nil -> meal
          src -> merge_meal_targets(meal, src)
        end
      end)

    %{day | total_calorie_target: source.total_calorie_target, meals: meals}
  end

  defp merge_meal_targets(meal, source) do
    %{
      meal
      | protein_pct: source.protein_pct,
        carbs_pct: source.carbs_pct,
        fats_pct: source.fats_pct,
        note: source.note
    }
  end

  # ── params ────────────────────────────────────────────────────────────────

  # Split the free-text (blueprint-level) preferred_foods field into an array;
  # the chip pickers already arrive as arrays via their hidden `[]` inputs.
  defp normalize_params(params) do
    case Map.get(params, "preferred_foods") do
      value when is_binary(value) ->
        tags = value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
        Map.put(params, "preferred_foods", tags)

      _ ->
        params
    end
  end
end
