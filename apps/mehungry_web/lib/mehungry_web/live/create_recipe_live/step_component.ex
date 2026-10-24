defmodule MehungryWeb.StepComponent do
  use MehungryWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="space-y-3">
      <.inputs_for :let={steps_form} field={@f[:steps]}>
        <input type="hidden" name="recipe[steps_sort][]" value={steps_form.index} />
        <div class="group rounded-xl border border-ink-panel2 bg-black/20 p-3 transition-colors hover:border-paprika/30">
          <%!--
            Optional "Part" label for this step, stored in the embedded Step.title.
            Shares the same `.js-part-field` reveal as ingredient parts so a step's
            part and its ingredients' parts are named together. Blank = ungrouped.
          --%>
          <div class={["js-part-field mb-3", !@show_parts && "hidden"]}>
            <span class="mb-1 block text-[11px] font-medium uppercase tracking-wide text-parchment-dim">
              {gettext("Part (optional)")}
            </span>
            <.input
              field={steps_form[:title]}
              type="text"
              placeholder={gettext("e.g. Dressing")}
              class="w-full text-sm"
            />
          </div>

          <div class="flex items-start gap-3">
            <span class="mt-2 flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-ink-panel2 text-sm font-bold tabular-nums text-basil">
              {steps_form.index + 1}
            </span>
            <div class="min-w-0 flex-1">
              <.input
                required
                field={steps_form[:description]}
                type="textarea"
                placeholder={gettext("Describe this step…")}
                class="w-full"
              />
            </div>
            <.input required field={steps_form[:index]} type="hidden" value={steps_form.index} />
            <.input required field={steps_form[:temp_id]} type="hidden" />
            <button
              name="recipe[_action]"
              value={"remove_step:#{steps_form.index}"}
              aria-label={gettext("Remove step")}
              class="mt-1 h-10 w-10 shrink-0 grid place-items-center rounded-lg text-parchment-dim hover:text-red-400 hover:bg-ink-panel2 transition-colors"
            >
              <.icon name="hero-trash" class="h-5 w-5" />
            </button>
          </div>
        </div>
      </.inputs_for>

      <.action
        variant={:ghost}
        size={:sm}
        type="submit"
        name="recipe[_action]"
        value="add_step"
        class="text-paprika-soft hover:text-paprika"
      >
        <.icon name="hero-plus" class="h-4 w-4" /> {gettext("Add step")}
      </.action>
    </div>
    """
  end
end
