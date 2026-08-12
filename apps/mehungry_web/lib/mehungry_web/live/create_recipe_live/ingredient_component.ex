defmodule MehungryWeb.IngredientComponent do
  use MehungryWeb, :live_component

  alias Mehungry.Food.IngredientPortion

  @impl true
  def update(%{new_ingredient_id: ingredient_id} = _assigns, socket) do
    socket = assign(socket, :unit_options, unit_options(ingredient_id))

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_search_fns()

    options =
      case socket.assigns.ingredient_form[:ingredient_id].value do
        nil -> unit_options(nil)
        id -> unit_options(id)
      end

    socket = assign(socket, :unit_options, options)

    {:ok, socket}
  end

  # Builds the unit dropdown options for an ingredient. Every portion becomes an
  # option — including description-only ones (no measurement unit) — labelled via
  # IngredientPortion.display_name/1. Option values are the integer encoding used
  # by RecipeIngredient.unit_selection: a measurement_unit_id for unit-bearing
  # portions, or -portion_id for description-only portions. "gram" is always
  # appended.
  defp unit_options(nil) do
    Enum.map(gram_units(), fn mu -> {Integer.to_string(mu.id), mu.name} end)
  end

  defp unit_options(ingredient_id) do
    portion_options =
      ingredient_id
      |> Mehungry.Food.get_measurement_unit_portions_for_ingredient()
      |> Enum.map(fn portion ->
        value =
          if portion.measurement_unit_id, do: portion.measurement_unit_id, else: -portion.id

        {Integer.to_string(value), IngredientPortion.display_name(portion) || "portion"}
      end)

    gram_options = Enum.map(gram_units(), fn mu -> {Integer.to_string(mu.id), mu.name} end)

    portion_options ++ gram_options
  end

  defp gram_units, do: Mehungry.Food.get_measurement_unit_by_name("gram")

  def get_measurement_units() do
  end

  defp assign_search_fns(socket) do
    language = Map.get(socket.assigns, :search_language, "en")
    owner_id = Map.get(socket.assigns, :current_user_id)

    {item_fn, label_fn, get_by_id_fn} =
      if language == "el" do
        item_fn = fn term ->
          Mehungry.Food.IngredientSearch.search_in_language(term, "el", owner_id)
        end

        get_by_id_fn = fn id ->
          ingredient = Mehungry.Food.get_ingredient!(id)

          case Mehungry.Food.find_ingredient_translation("el", id) do
            [greek_name | _] -> %{ingredient | name: greek_name}
            [] -> ingredient
          end
        end

        {item_fn, fn item -> item.name end, get_by_id_fn}
      else
        {
          fn term -> Mehungry.Food.IngredientSearch.search(term, [], owner_id) end,
          fn item -> Mehungry.Utils.remove_parenthesis(item.name) end,
          &Mehungry.Food.get_ingredient!/1
        }
      end

    condition_ids = ingredient_condition_ids(owner_id)
    flags_fn = fn ids -> MehungryWeb.RecipeFlags.flags_for_ingredient_ids(ids, condition_ids) end

    socket
    |> assign(:ingredient_item_fn, item_fn)
    |> assign(:ingredient_label_fn, label_fn)
    |> assign(:ingredient_get_by_id_fn, get_by_id_fn)
    |> assign(:ingredient_flags_fn, flags_fn)
  end

  # The viewer's opted-in health-condition ids, for ingredient badges. `[]` when
  # logged-out or not opted-in, so the picker renders no badges.
  defp ingredient_condition_ids(nil), do: []

  defp ingredient_condition_ids(user_id) do
    user_id
    |> Mehungry.Accounts.get_user_profile_by_user_id()
    |> MehungryWeb.RecipeFlags.opted_in_condition_ids()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="group rounded-xl border border-ink-panel2 bg-black/20 p-3 transition-colors hover:border-paprika/30">
      <%!--
        Mobile: ingredient on its own row, then quantity + unit + delete.
        Desktop (md+): a single 12-column row, all controls the same height and
        vertically centred. Every field carries a small parchment-dim label so
        the two select widgets and the quantity input read as one set.
      --%>
      <div class="flex flex-col gap-3 md:grid md:grid-cols-12 md:gap-3 md:items-end">
        <%!-- Ingredient --%>
        <div class="min-w-0 md:col-span-6">
          <.field_label>Ingredient</.field_label>
          <.live_component
            module={MehungryWeb.SelectComponentDeep}
            form={@ingredient_form}
            item_function={@ingredient_item_fn}
            flags_function={@ingredient_flags_fn}
            get_by_id_func={@ingredient_get_by_id_fn}
            input_variable="ingredient_id"
            label_function={@ingredient_label_fn}
            placeholder="Select an ingredient…"
            modal_title="Search Ingredients"
            parent_id={@id}
            select_function={fn x -> send(self(), {:select_id, x, @id}) end}
            id={"ingredient_search_component" <> Integer.to_string(@ingredient_form.index)}
          />
        </div>

        <%!-- Quantity + Unit + delete: inline on mobile, columns on desktop --%>
        <div class="flex items-end gap-3 md:contents">
          <div class="w-24 shrink-0 md:col-span-2">
            <.field_label>Qty</.field_label>
            <.input field={@ingredient_form[:quantity]} type="number_subscript" placeholder="0" />
          </div>
          <div class="min-w-0 flex-1 md:col-span-3">
            <.field_label>Unit</.field_label>
            <.live_component
              module={MehungryWeb.SelectComponent}
              items={@unit_options}
              form={@ingredient_form}
              id={"measurement_unit_search_componentasdf" <> Integer.to_string(@ingredient_form.index)}
              input_variable={:unit_selection}
            />
          </div>
          <div class="md:col-span-1 md:flex md:justify-end">
            <button
              name="recipe[_action]"
              value={"remove_ingredient:#{@ingredient_form.index}"}
              aria-label="Remove ingredient"
              class="shrink-0 h-10 w-10 grid place-items-center rounded-lg text-parchment-dim hover:text-red-400 hover:bg-ink-panel2 transition-colors"
            >
              <.icon name="hero-trash" class="h-5 w-5" />
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Small, consistent field label shared by all three controls in a row.
  defp field_label(assigns) do
    ~H"""
    <span class="mb-1 block text-[11px] font-medium uppercase tracking-wide text-parchment-dim">
      {render_slot(@inner_block)}
    </span>
    """
  end

end
