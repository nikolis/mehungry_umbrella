defmodule MehungryWeb.Professional.TranslationsComponent do
  use MehungryWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-display font-medium text-parchment">Translations</h3>
        <button
          type="submit"
          name="ingredient[_action]"
          value="add_ingredient_translation"
          class="flex items-center gap-1 px-3 py-1.5 rounded-full border border-ink-panel2 text-parchment-dim hover:bg-ink-panel2 hover:text-parchment text-xs font-semibold transition-colors"
        >
          + Add Translation
        </button>
      </div>
      <div class="space-y-3">
        <.inputs_for :let={tr_form} field={@form[:ingredient_translation]}>
          <div class="bg-black/20 border border-ink-panel2 rounded-xl p-3 flex flex-col sm:flex-row sm:items-end gap-3">
            <input
              type="hidden"
              name="ingredient[ingredient_translation_sort][]"
              value={tr_form.index}
            />
            <div class="flex-1">
              <.input
                type="text"
                label="Translated name"
                name={tr_form[:name].name}
                value={tr_form[:name].value}
              />
            </div>
            <div class="flex-1">
              <.live_component
                module={MehungryWeb.SelectComponent}
                items={Enum.map(@languages, fn x -> {x.name, x.name} end)}
                form={tr_form}
                id={"translation_select_id_" <> Integer.to_string(tr_form.index)}
                input_variable={:language_name}
              />
            </div>
          </div>
        </.inputs_for>
      </div>
    </div>
    """
  end

  def handle_event("add_translation", _, socket) do
    send(self(), :add_translation)
    {:noreply, socket}
  end

  def handle_event("remove_translation", %{"index" => i}, socket) do
    send(self(), {:remove_translation, String.to_integer(i)})
    {:noreply, socket}
  end
end
