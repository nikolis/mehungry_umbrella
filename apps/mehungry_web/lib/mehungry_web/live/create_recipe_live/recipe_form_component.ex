defmodule MehungryWeb.RecipeFormComponent do
  use MehungryWeb, :live_component

  alias MehungryWeb.CreateRecipeLive.Components

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
      class=" sm:pt-6 sm:pt-2 flex md:gap-8 flex-col mx-auto mb-2 relative"
    >
      <input type="hidden" name="recipe[_action]" value="" />
      <div class="basic_2_col_grid_cont   content_container" id="content-0">
        <div class="flex flex-col gap-2 sm:gap-3 h-full p-2 sm:p-4 ">
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
              type="text"
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
        </div>

        <%= if @f.data.image_url do %>
          <div class="relative">
            <img src={@f.data.image_url} class="m-auto relative" style="max-height: 30vh;" />
            <button
              type="button"
              phx-click="delete-image"
              class="absolute top-0 right-3 bg-white rounded-full"
            >
              <.icon name="hero-x-mark-solid" class="h-6 w-6 " phx-click="clear-image" />
            </button>
          </div>
        <% else %>
          <div class={"drop-container  #{drop_hidden?(@uploads.image.entries)}"}>
            <div class="file-drop-area w-full h-full " phx-drop-target=" {@uploads.image.ref}">
              <div id="lab1" phx-hook="ImageSelect" for={@uploads.image.ref} class="h-full w-full ">
                <div class="drag_label">Drag n Drop or click to upload</div>
              </div>
              <.live_file_input upload={@uploads.image} class="h-full w-full" style="" />
            </div>
          </div>
        <% end %>
        <%= if is_nil(@f.data.image_url) do %>
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

      <div class="basic_2_col_grid_cont md:pb-32 " style="">
        <div class="overflowx-hidden  relative content_container hidden md:block" id="content-1">
          <h3 class="text-center">Ingredients</h3>
          <div class="md:min-h-96  sm:max-h-65 overflow-x-hidden noscrollbar	pt-4  step_ing_cont mb-14">
            <.inputs_for :let={ingredient_form} field={@f[:recipe_ingredients]}>
              <.live_component
                module={MehungryWeb.IngredientComponent}
                id={"recipe_ingredients_component" <> Integer.to_string(ingredient_form.index)}
                f={@f}
                ingredient_form={ingredient_form}
                ingredients={@ingredients}
                measurement_units={@measurement_units}
                measurement_units={@measurement_units}
              />
            </.inputs_for>
            <button
              name="recipe[_action]"
              value="add_ingredient"
              class="p-4 font-semibold text-md fixed sm:absolute bottom-20 right-6 text-xl bg-white"
            >
              + Add
            </button>
          </div>
        </div>

        <div
          class="overflowx-hidden  relative content_container hidden md:block"
          id="content-2"
          style="max-height: 70vh;"
        >
          <div class="relative h-fit">
            <h3 class="text-center">Creation Steps</h3>
            <div
              class="step_ing_cont md:min-h-96 md:max-h-96  overflow-x-hidden noscrollbar	pt-4 sm:p-4"
              style=" padding-bottom: 2rem;"
            >
              <.live_component module={MehungryWeb.StepComponent} id="recipe_step" f={@f} />
            </div>
          </div>
        </div>
      </div>
      <div
        id="content-3"
        class=" content_container hidden md:block h-full "
        style={" padding-bottom: 1rem; " <> if @f.source.valid? do "color: var(--clr-primary);" else "" end}
      >
        <div class="flex justify-around h-full min-h-80 sm:min-h-fit	">
          <div class="w-1/8"></div>
          <.icon name="hero-check-badge" class="h-full w-full md:hidden" phx-click="clear-image" />
          <div class="w-1/8"></div>
        </div>
        <div class="flex bottom-0">
          <div id="something wierd" class="md:absolute  sm:right-56  mx-auto bottom-0 w-40">
            <button
              class="button text-secondary-500 border-2 border-secondary-500  w-full md:absolute right-0 left-0 bottom-0 md:mx-auto text-2xl font-bold   mb-14"
              id="button_delete"
              type="button"
              phx-click="clear-form"
            >
              Reset
            </button>
          </div>
          <div class="md:absolute right-0 sm:right-10 mx-auto bottom-0 w-40">
            {submit("Save",
              class:
                "button bg-primary-400  border-2 border-transparent  w-full md:absolute right-0 left-0 bottom-0 mx-auto text-2xl font-bold mb-14",
              type: "submit",
              phx_disable_with: "Saving...",
              id: "save_button"
            )}
          </div>
        </div>
      </div>
    </form>
    """
  end
end
