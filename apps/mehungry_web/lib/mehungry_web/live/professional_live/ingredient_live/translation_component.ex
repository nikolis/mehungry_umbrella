defmodule MehungryWeb.Professional.TranslationsComponent do
  use MehungryWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="relative px-8">
      <h3 class="text-xl font-semibold mb-2">Translations</h3>
      <.inputs_for :let={tr_form} field={@form[:ingredient_translation]}>
        <div class="grid grid-cols-5 p-2">
          <input type="hidden" name="ingredient[ingredient_translation_sort][]" value={tr_form.index} />

          <.input
            type="text"
            label="translated ingredient name"
            name={tr_form[:name].name}
            value={tr_form[:name].value}
          />

          <.live_component
            module={MehungryWeb.SelectComponent}
            items={Enum.map(@languages, fn x -> {x.name, x.name} end)}
            form={tr_form}
            id={"translation_select_id_" <> Integer.to_string(tr_form.index)}
            input_variable={:language_name}
          />
        </div>
      </.inputs_for>
      <button
        type="submit"
        name="ingredient[_action]"
        value="add_ingredient_translation"
        class="px-4 font-semibold text-md absolute right-10"
      >
        + Add Translation
      </button>
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
