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
    fns = MehungryWeb.IngredientSearchFns.search_fns(language, owner_id)

    socket
    |> assign(:ingredient_item_fn, fns.item_fn)
    |> assign(:ingredient_label_fn, fns.label_fn)
    |> assign(:ingredient_get_by_id_fn, fns.get_by_id_fn)
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
          <.field_label>{gettext("Ingredient")}</.field_label>
          <.live_component
            module={MehungryWeb.SelectComponentDeep}
            form={@ingredient_form}
            item_function={@ingredient_item_fn}
            get_by_id_func={@ingredient_get_by_id_fn}
            input_variable="ingredient_id"
            label_function={@ingredient_label_fn}
            placeholder={gettext("Select an ingredient…")}
            modal_title={gettext("Search Ingredients")}
            parent_id={@id}
            select_function={fn x -> send(self(), {:select_id, x, @id}) end}
            id={"ingredient_search_component" <> Integer.to_string(@ingredient_form.index)}
          />
          <.row_errors field={@ingredient_form[:ingredient_id]} />
        </div>

        <%!-- Quantity + Unit + delete: inline on mobile, columns on desktop --%>
        <div class="flex items-end gap-3 md:contents">
          <div class="w-24 shrink-0 md:col-span-2">
            <.field_label>{gettext("Qty")}</.field_label>
            <.input field={@ingredient_form[:quantity]} type="number_subscript" placeholder="0" />
            <.row_errors field={@ingredient_form[:quantity]} />
          </div>
          <div class="min-w-0 flex-1 md:col-span-3">
            <.field_label>{gettext("Unit")}</.field_label>
            <.live_component
              module={MehungryWeb.SelectComponent}
              items={@unit_options}
              form={@ingredient_form}
              id={"measurement_unit_search_componentasdf" <> Integer.to_string(@ingredient_form.index)}
              input_variable={:unit_selection}
            />
            <.row_errors field={@ingredient_form[:measurement_unit_id]} />
          </div>
          <div class="md:col-span-1 md:flex md:justify-end">
            <button
              name="recipe[_action]"
              value={"remove_ingredient:#{@ingredient_form.index}"}
              aria-label={gettext("Remove ingredient")}
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

  # Inline validation errors for one control in an ingredient row. The row's
  # ingredient/quantity/unit live in custom select + number widgets that render
  # no errors of their own, so a required or unit/portion problem was previously
  # invisible here — this surfaces it right under the offending field.
  attr :field, Phoenix.HTML.FormField, required: true

  defp row_errors(assigns) do
    ~H"""
    <div phx-feedback-for={@field.name}>
      <p
        :for={msg <- Enum.map(@field.errors, &MehungryWeb.CoreComponents.translate_error/1)}
        class="mt-1 text-xs text-rose-400 phx-no-feedback:hidden"
      >
        {msg}
      </p>
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
