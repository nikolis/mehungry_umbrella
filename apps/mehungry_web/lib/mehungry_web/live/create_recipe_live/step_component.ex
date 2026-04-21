defmodule MehungryWeb.StepComponent do
  use MehungryWeb, :live_component

  def render(assigns) do
    ~H"""
    <div>
      <.inputs_for :let={steps_form} field={@f[:steps]}>
        <div class={"grid grid-cols-7 gap-2 h-14  m-2" <> if Map.get(steps_form.source.changes, :delete)  do " hidden"  else ""  end}>
          <div class="m-auto">
            <span class="text-3xl">{steps_form.index + 1}</span>
          </div>
          {hidden_input(steps_form, :delete)}
          <.input required field={steps_form[:index]} type="hidden" value={steps_form.index} />

          <div class="col-span-5">
            <.input required field={steps_form[:description]} type="textarea" class="w-full max-h-14" />
          </div>
          <.input required field={steps_form[:temp_id]} type="hidden" />
          <button
            class="text-4xl font-bold "
            name="recipe[_action]"
            value={"remove_step:#{steps_form.index}"}
          >
            ❌
          </button>

          <div class="form-group px-1 w-full"></div>
        </div>
      </.inputs_for>

      <button
        name="recipe[_action]"
        value="add_step"
          class=" font-semibold text-md absolute right-0 bottom-0 bg-transparent  text-xl z-50"
      >
        + Add Step
      </button>
    </div>
    """
  end
end
