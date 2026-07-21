defmodule MehungryWeb.RecipeFormComponent do
  use MehungryWeb, :live_component

  def error_to_string(:too_large), do: "Too large"
  def error_to_string(:not_accepted), do: "You have selected an unacceptable file type"

  def drop_hidden?(images) do
    case Enum.empty?(images) do
      true ->
        ""

      false ->
        "hidden"
    end
  end

  def render(assigns) do
    ~H"""
    <form
      novalidate
      phx-change="validate"
      phx-submit="save"
      class="the_form sm:pt-6 sm:pt-2 flex md:gap-8 flex-col mx-auto relative"
    >
      <input type="hidden" name="recipe[_action]" value="" />
      <div
        class="content_container grid md:grid-cols-2 gap-6 border border-ink-panel2 bg-ink-panel rounded-xl p-4"
        id="content-0"
      >
        <div class="flex flex-col gap-3">
          <.input required field={@f[:title]} type="text" label="Title" class="max-h-12 " />
          <.input required field={@f[:description]} type="text" label="Description" class="max-h-12" />

          <div class="grid grid-cols-2 gap-4">
            <.input
              required
              field={@f[:cooking_time_lower_limit]}
              type="number_subscript"
              subscript="mins"
              label="Cooking time"
              class="sm:w-full max-h-12 min-w-20"
              style="flex-shrink: 2;"
            />
            <.input
              required
              field={@f[:preperation_time_lower_limit]}
              type="number_subscript"
              subscript="mins"
              label="Prep Time"
              class="sm:w-full max-h-12 "
            />
          </div>

          <div class="grid grid-cols-2 gap-4">
            <.input required field={@f[:servings]} type="text" label="Servings" class=" w-full" />
            <.input
              required
              field={@f[:difficulty]}
              options={[Easy: "1", Medium: "2", Difficult: "3"]}
              type="select"
            />
          </div>

          <.input field={@f[:language_name]} type="hidden" />
          <.input field={@f[:image_url]} type="hidden" />
        </div>

        <%= if @f[:image_url].value do %>
          <div class="relative">
            <img src={@f[:image_url].value} class="m-auto relative" style="max-height: 30vh;" />
            <button
              type="button"
              phx-click="delete-image"
              class="absolute top-0 right-3 bg-parchment rounded-full"
            >
              <.icon name="hero-x-mark-solid" class="h-6 w-6" />
            </button>
          </div>
        <% else %>
          <div class={"drop-container  #{drop_hidden?(@uploads.image.entries)}"}>
            <div
              class=" border-2 border-dashed border-ink-panel2 rounded-lg p-8 text-center hover:border-paprika transition cursor-pointer group h-full "
              phx-drop-target=" {@uploads.image.ref}"
            >
              <div id="lab1" phx-hook="ImageSelect" for={@uploads.image.ref} class="h-full w-full ">
                <svg
                  class="w-12 h-12 mx-auto text-parchment-dim mb-3 group-hover:text-paprika transition"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
                  />
                </svg>

                <p class="text-parchment-dim text-sm group-hover:text-parchment">
                  Click or drag to upload image
                </p>
              </div>
              <.live_file_input upload={@uploads.image} class="h-full w-full" style="" />
            </div>
          </div>
        <% end %>
        <%= if is_nil(@f[:image_url].value) do %>
          <div class="">
            <%= for entry <- @uploads.image.entries do %>
              <div class="img_preview_container">
                <.live_img_preview
                  entry={entry}
                  width="500rem"
                  class="m-auto"
                  style="max-height: 30vh;"
                />
                <article class="upload-entry">
                  <figure class="h-full">
                    <progress class="w-full" value={entry.progress} max="100">
                      {entry.progress}%
                    </progress>
                  </figure>

                  <%= for err <- upload_errors(@uploads.image, entry) do %>
                    <p class="alert alert-danger">{error_to_string(err)}</p>
                  <% end %>
                </article>
                <button
                  class="photo-delbutton text-4xl"
                  type="button"
                  phx-click="cancel-upload"
                  phx-value-ref={entry.ref}
                  aria-label="cancel"
                >
                  &times;
                </button>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <div class="grid md:grid-cols-2 gap-6">
        <%!-- Ingredients (content-1) — always in column 1 --%>
        <div
          class="overflowx-hidden relative content_container hidden md:block border border-ink-panel2 bg-ink-panel rounded-xl p-4"
          id="content-1"
        >
          <h3 class="text-base font-display font-medium text-parchment mb-3">Ingredients</h3>
          <div class="md:min-h-96 sm:max-h-65 overflow-x-hidden noscrollbar pt-4 step_ing_cont mb-14 pb-20 md:pb-0">
            <.inputs_for :let={ingredient_form} field={@f[:recipe_ingredients]}>
              <.live_component
                module={MehungryWeb.IngredientComponent}
                id={"recipe_ingredients_component" <> Integer.to_string(ingredient_form.index)}
                f={@f}
                ingredient_form={ingredient_form}
                ingredients={@ingredients}
                measurement_units={@measurement_units}
                search_language={@search_language}
              />
            </.inputs_for>
            <button
              id="add_ingredient"
              phx-click="add_ingredient"
              name="recipe[_action]"
              value="add_ingredient"
              type="button"
              class="inline-flex items-center gap-1.5 text-sm font-semibold text-paprika-soft hover:text-paprika transition-colors self-end mt-3"
            >
              + Add
            </button>
          </div>
        </div>

        <%!-- Column 2: unmatched panel when present, otherwise steps --%>
        <%= if @spoonacular_unmatched != [] do %>
          <div class="overflowx-hidden relative content_container hidden md:block bg-amber-950/40 border border-amber-700/40 rounded-xl p-4">
            <div class="flex items-center gap-2 mb-3">
              <svg
                class="w-4 h-4 text-amber-400 flex-shrink-0"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 9v2m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"
                />
              </svg>
              <h3 class="text-base font-semibold text-amber-300">
                Unmatched Ingredients ({length(@spoonacular_unmatched)})
              </h3>
            </div>
            <p class="text-parchment-dim text-xs mb-3">
              Not found in the database — add them manually using the ingredients section.
            </p>
            <div class="space-y-1.5 md:max-h-96 overflow-y-auto noscrollbar">
              <%= for item <- @spoonacular_unmatched do %>
                <div class="rounded-lg bg-black/20 px-3 py-2 text-sm">
                  <div class="flex items-center justify-between gap-2 mb-0.5">
                    <span class="text-parchment font-medium truncate">{item.name}</span>
                    <span class={[
                      "flex-shrink-0 px-1.5 py-0.5 rounded text-xs font-medium",
                      item.reason == :ingredient_not_found && "bg-red-900/50 text-red-300",
                      item.reason == :unit_not_found && "bg-orange-900/50 text-orange-300",
                      item.reason == :portion_not_found && "bg-yellow-900/50 text-yellow-300"
                    ]}>
                      {case item.reason do
                        :ingredient_not_found -> "not in DB"
                        :unit_not_found -> "unknown unit"
                        :portion_not_found -> "no portion"
                        _ -> to_string(item.reason)
                      end}
                    </span>
                  </div>
                  <span class="text-parchment-dim text-xs">{item.original}</span>
                </div>
              <% end %>
            </div>
          </div>
        <% else %>
          <div
            class="overflowx-hidden relative content_container hidden md:block border border-ink-panel2 bg-ink-panel rounded-xl p-4"
            id="content-2"
          >
            <div class="relative h-fit">
              <h3 class="text-base font-display font-medium text-parchment mb-3">Steps</h3>
              <div class="step_ing_cont md:min-h-96 md:max-h-96 overflow-x-hidden noscrollbar pt-4 sm:p-4 pb-20 md:pb-8">
                <.live_component module={MehungryWeb.StepComponent} id="recipe_step" f={@f} />
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Steps row: only rendered when unmatched panel occupies column 2 --%>
      <%= if @spoonacular_unmatched != [] do %>
        <div class="grid gap-6">
          <div
            class="overflowx-hidden relative content_container hidden md:block border border-ink-panel2 bg-ink-panel rounded-xl p-4"
            id="content-2"
          >
            <div class="relative h-fit">
              <h3 class="text-base font-display font-medium text-parchment mb-3">Steps</h3>
              <div class="step_ing_cont md:min-h-96 md:max-h-96 overflow-x-hidden noscrollbar pt-4 sm:p-4 pb-20 md:pb-8">
                <.live_component module={MehungryWeb.StepComponent} id="recipe_step" f={@f} />
              </div>
            </div>
          </div>
        </div>
      <% end %>
      <div
        id="content-3"
        class="content_container hidden md:block border border-ink-panel2 bg-ink-panel rounded-xl p-6"
      >
        <h3 class="text-base font-display font-medium text-parchment mb-4">Review & Save</h3>
        <p class={
          if @f.source.valid?,
            do: "text-sm text-emerald-400 mb-6",
            else: "text-sm text-parchment-dim mb-6"
        }>
          <%= if @f.source.valid? do %>
            Everything looks good — ready to save!
          <% else %>
            Fill in required fields before saving.
          <% end %>
        </p>
        <div class="flex items-center gap-3">
          <button
            id="button_delete"
            type="button"
            phx-click="clear-form"
            class="px-5 py-2.5 border border-ink-panel2 text-parchment-dim rounded-lg font-medium hover:border-parchment-dim hover:text-parchment transition-colors"
          >
            Reset
          </button>
          {submit("Save Recipe",
            class:
              "px-6 py-2.5 bg-paprika hover:bg-paprika-soft text-ink rounded-lg font-bold transition-colors",
            type: "submit",
            phx_disable_with: "Saving…",
            id: "save_button"
          )}
        </div>
      </div>
    </form>
    """
  end
end
