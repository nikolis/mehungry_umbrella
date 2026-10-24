defmodule MehungryWeb.RecipeFormComponent do
  use MehungryWeb, :live_component

  @doc """
  Human-readable list of the reasons a recipe changeset can't be saved.

  Draws from both the top-level errors (required fields, the unit/portion check
  `Food.create_recipe/1` adds, the unique-title constraint) and each ingredient
  row's own errors, so the create-recipe flash and the Review & Save panel can
  name the actual blockers instead of showing a generic "fix the highlighted
  fields" message — none of these errors are otherwise rendered in the form.
  """
  def save_error_messages(%Ecto.Changeset{} = changeset) do
    top_level =
      Enum.map(changeset.errors, fn {field, {msg, opts}} ->
        error_line(field, interpolate_error(msg, opts))
      end)

    ingredient_level =
      changeset
      |> Ecto.Changeset.get_change(:recipe_ingredients, [])
      |> Enum.reject(&(&1.action == :delete))
      |> Enum.flat_map(fn ri_cs ->
        Enum.map(ri_cs.errors, fn {field, {msg, opts}} ->
          error_line(field, interpolate_error(msg, opts))
        end)
      end)

    (top_level ++ ingredient_level) |> Enum.uniq()
  end

  # The unit/portion check adds full-sentence errors on the :recipe_ingredients
  # key — show those verbatim; give the "no ingredients" case a friendly line;
  # everything else gets a short field label.
  defp error_line(:recipe_ingredients, "can't be blank"),
    do: gettext("Add at least one ingredient.")

  defp error_line(:recipe_ingredients, msg), do: msg
  defp error_line(field, msg), do: "#{field_label(field)}: #{msg}"

  defp interpolate_error(msg, opts) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp field_label(:title), do: gettext("Title")
  defp field_label(:cooking_time_lower_limit), do: gettext("Cooking time")
  defp field_label(:preperation_time_lower_limit), do: gettext("Prep time")
  defp field_label(:language_name), do: gettext("Language")
  defp field_label(:ingredient_id), do: gettext("Ingredient")
  defp field_label(:quantity), do: gettext("Quantity")
  defp field_label(:measurement_unit_id), do: gettext("Unit")

  defp field_label(field),
    do: field |> to_string() |> String.replace("_", " ") |> String.capitalize()

  def error_to_string(:too_large), do: gettext("Too large")
  def error_to_string(:not_accepted), do: gettext("You have selected an unacceptable file type")
  def error_to_string(:too_many_files), do: gettext("You have selected too many files")
  def error_to_string(:external_client_failure), do: gettext("Upload failed, please try again")
  def error_to_string(_), do: gettext("Something went wrong with the upload")

  # The hidden `image_url` input submits "" (not nil) on every validate event,
  # and "" is truthy in Elixir. Treat blank as "no image" so the upload UI and
  # the selected-file preview keep showing until a real URL exists.
  def has_image?(value), do: value not in [nil, ""]

  def drop_hidden?(images) do
    case Enum.empty?(images) do
      true ->
        ""

      false ->
        "hidden"
    end
  end

  # True when this recipe already uses named parts — any ingredient row carries a
  # `component_name` or any step carries a `title`. Drives whether the "Part"
  # inputs start revealed (editing a split recipe) vs. hidden behind the
  # "Split into parts" opt-in (the common single-part case, which must look
  # exactly like a plain recipe).
  def show_parts?(%Phoenix.HTML.Form{source: %Ecto.Changeset{} = changeset}) do
    any_ingredient_part?(changeset) or any_step_part?(changeset)
  end

  def show_parts?(_), do: false

  defp any_ingredient_part?(changeset) do
    changeset
    |> Ecto.Changeset.get_assoc(:recipe_ingredients)
    |> Enum.any?(&present?(Ecto.Changeset.get_field(&1, :component_name)))
  end

  defp any_step_part?(changeset) do
    changeset
    |> Ecto.Changeset.get_embed(:steps)
    |> Enum.any?(&present?(Ecto.Changeset.get_field(&1, :title)))
  end

  defp present?(value), do: value not in [nil, ""]

  def render(assigns) do
    assigns = assign(assigns, :show_parts, show_parts?(assigns.f))

    ~H"""
    <form id="create-recipe-form" novalidate phx-change="validate" phx-submit="save" class="the_form flex flex-col gap-6">
      <input type="hidden" name="recipe[_action]" value="" />

      <.panel_card class="grid gap-6 md:grid-cols-2">
        <div class="flex flex-col gap-3">
          <.input required field={@f[:title]} type="text" label={gettext("Title")} class="max-h-12" />
          <.input
            required
            field={@f[:description]}
            type="text"
            label={gettext("Short description")}
            class="max-h-12"
          />

          <div class="grid grid-cols-2 gap-4">
            <.input
              required
              field={@f[:cooking_time_lower_limit]}
              type="number_subscript"
              subscript="mins"
              label={gettext("Cooking time")}
              class="w-full max-h-12 min-w-20"
            />
            <.input
              required
              field={@f[:preperation_time_lower_limit]}
              type="number_subscript"
              subscript="mins"
              label={gettext("Prep Time")}
              class="w-full max-h-12"
            />
          </div>

          <div class="grid grid-cols-2 gap-4">
            <.input required field={@f[:servings]} type="text" label={gettext("Servings")} class="w-full" />
            <.input
              required
              field={@f[:difficulty]}
              options={[{gettext("Easy"), "1"}, {gettext("Medium"), "2"}, {gettext("Difficult"), "3"}]}
              type="select"
            />
          </div>

          <.input field={@f[:language_name]} type="hidden" />
          <.input field={@f[:image_url]} type="hidden" />
        </div>

        <%= if has_image?(@f[:image_url].value) do %>
          <div class="relative">
            <img src={@f[:image_url].value} class="m-auto max-h-[30vh] rounded-lg" />
            <button
              type="button"
              phx-click="delete-image"
              aria-label={gettext("Remove image")}
              class="absolute top-2 right-2 bg-parchment rounded-full"
            >
              <.icon name="hero-x-mark-solid" class="h-6 w-6 text-red-500/70" />
            </button>
          </div>
        <% else %>
          <div class={"drop-container #{drop_hidden?(@uploads.image.entries)}"}>
            <div
              class="border-2 border-dashed border-ink-panel2 rounded-lg p-8 text-center hover:border-paprika transition cursor-pointer group h-full"
              phx-drop-target={@uploads.image.ref}
            >
              <div id="lab1" phx-hook="ImageSelect" for={@uploads.image.ref} class="h-full w-full">
                <.icon name="hero-photo" class="w-12 h-12 mx-auto text-parchment-dim mb-3 group-hover:text-paprika transition" />
                <p class="text-parchment-dim text-sm group-hover:text-parchment">
                  {gettext("Click or drag to upload image")}
                </p>
              </div>
              <.live_file_input upload={@uploads.image} class="h-full w-full" />
            </div>
          </div>
          <div :for={entry <- @uploads.image.entries} class="img_preview_container">
            <.live_img_preview entry={entry} class="m-auto max-w-full max-h-[30vh] rounded-lg" />
            <article class="upload-entry">
              <figure class="h-full">
                <progress class="w-full" value={entry.progress} max="100">{entry.progress}%</progress>
              </figure>
              <p :for={err <- upload_errors(@uploads.image, entry)} class="alert alert-danger">
                {error_to_string(err)}
              </p>
            </article>
            <button
              class="photo-delbutton text-4xl"
              type="button"
              phx-click="cancel-upload"
              phx-value-ref={entry.ref}
              aria-label={gettext("Cancel upload")}
            >
              &times;
            </button>
          </div>
        <% end %>
      </.panel_card>

      <%!--
        Opt-in to split a recipe into named parts (e.g. "Salad" + "Dressing").
        Pure client-side reveal: toggles the per-row "Part" inputs (`.js-part-field`)
        and swaps the button label. No server round-trip, no data change — a blank
        part on every row saves identically to a plain recipe.
      --%>
      <div class="flex justify-end -my-2">
        <button
          type="button"
          phx-click={
            Phoenix.LiveView.JS.toggle(to: ".js-part-field")
            |> Phoenix.LiveView.JS.toggle(to: "#split-label-off")
            |> Phoenix.LiveView.JS.toggle(to: "#split-label-on")
          }
          class="flex items-center gap-1.5 px-3 py-1.5 rounded-full border border-ink-panel2 text-parchment-dim hover:text-parchment hover:border-parchment-dim text-xs font-medium transition-colors"
        >
          <.icon name="hero-bars-3-bottom-left" class="w-3.5 h-3.5" />
          <span id="split-label-off" class={@show_parts && "hidden"}>
            {gettext("Split into parts")}
          </span>
          <span id="split-label-on" class={!@show_parts && "hidden"}>
            {gettext("Hide parts")}
          </span>
        </button>
      </div>

      <.unmatched_panel :if={@spoonacular_unmatched != []} unmatched={@spoonacular_unmatched} />

      <.panel_card>
        <h3 class="text-base font-display font-medium text-parchment mb-3">
          {gettext("Ingredients")}
        </h3>
        <.inputs_for :let={ingredient_form} field={@f[:recipe_ingredients]}>
          <input type="hidden" name="recipe[recipe_ingredients_sort][]" value={ingredient_form.index} />
          <.live_component
            module={MehungryWeb.IngredientComponent}
            id={"recipe_ingredients_component" <> Integer.to_string(ingredient_form.index)}
            f={@f}
            ingredient_form={ingredient_form}
            search_language={@search_language}
            current_user_id={@current_user_id}
            show_parts={@show_parts}
          />
        </.inputs_for>
        <.action variant={:ghost} size={:sm} type="submit" name="recipe[_action]" value="add_ingredient" id="add_ingredient" class="mt-3 text-paprika-soft hover:text-paprika">
          <.icon name="hero-plus" class="h-4 w-4" /> {gettext("Add ingredient")}
        </.action>
      </.panel_card>

      <.panel_card>
        <h3 class="text-base font-display font-medium text-parchment mb-1">
          {gettext("Steps")}
        </h3>
        <p class="text-parchment-dim text-xs mb-3">
          {gettext("The cooking instructions, one step at a time.")}
        </p>
        <.live_component module={MehungryWeb.StepComponent} id="recipe_step" f={@f} show_parts={@show_parts} />
      </.panel_card>

      <.panel_card>
        <h3 class="text-base font-display font-medium text-parchment mb-4">
          {gettext("Review & Save")}
        </h3>
        <%= if @f.source.valid? do %>
          <p class="text-sm text-emerald-400 mb-6">
            {gettext("Everything looks good — ready to save!")}
          </p>
        <% else %>
          <div class="mb-6">
            <p class="text-sm text-parchment-dim mb-2">{gettext("Before saving, please fix:")}</p>
            <ul class="list-disc list-inside space-y-1">
              <li :for={msg <- save_error_messages(@f.source)} class="text-sm text-rose-400">{msg}</li>
            </ul>
          </div>
        <% end %>
        <div class="flex items-center gap-3">
          <.action variant={:ghost} type="button" phx-click="clear-form" id="button_delete">
            {gettext("Reset")}
          </.action>
          <.action variant={:primary} type="submit" phx-disable-with={gettext("Saving…")} id="save_button">
            {gettext("Save recipe")}
          </.action>
        </div>
      </.panel_card>
    </form>
    """
  end

  # Amber "couldn't auto-match these source lines" panel. Rendered in column 2 in
  # the default side-by-side layout, or directly above the Ingredients block when
  # `stacked` (where column 2 doesn't exist) — used by the importer review pages.
  attr :unmatched, :list, required: true

  defp unmatched_panel(assigns) do
    ~H"""
    <div class="bg-amber-950/40 border border-amber-700/40 rounded-2xl p-5">
      <div class="flex items-center gap-2 mb-3">
        <svg class="w-4 h-4 text-amber-400 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M12 9v2m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"
          />
        </svg>
        <h3 class="text-base font-semibold text-amber-300">
          {gettext("Unmatched Ingredients")} ({length(@unmatched)})
        </h3>
      </div>
      <p class="text-parchment-dim text-xs mb-3">
        {gettext("Not found in the database — add them manually using the ingredients section.")}
      </p>
      <div class="space-y-1.5 md:max-h-96 overflow-y-auto noscrollbar">
        <div :for={item <- @unmatched} class="rounded-lg bg-black/20 px-3 py-2 text-sm">
          <div class="flex items-center justify-between gap-2 mb-0.5">
            <span class="text-parchment font-medium truncate">{item.name}</span>
            <span class={[
              "flex-shrink-0 px-1.5 py-0.5 rounded text-xs font-medium",
              item.reason == :ingredient_not_found && "bg-red-900/50 text-red-300",
              item.reason == :unit_not_found && "bg-orange-900/50 text-orange-300",
              item.reason == :portion_not_found && "bg-yellow-900/50 text-yellow-300"
            ]}>
              {case item.reason do
                :ingredient_not_found -> gettext("not in DB")
                :unit_not_found -> gettext("unknown unit")
                :portion_not_found -> gettext("no portion")
                _ -> to_string(item.reason)
              end}
            </span>
          </div>
          <span class="text-parchment-dim text-xs">{item.original}</span>
        </div>
      </div>
    </div>
    """
  end
end
