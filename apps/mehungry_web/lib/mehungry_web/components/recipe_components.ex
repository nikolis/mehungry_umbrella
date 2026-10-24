defmodule MehungryWeb.RecipeComponents do
  @moduledoc """
  Same idea as CoreComponents but instead here we only put basic 
  ui building blocks that are related to recipes and are utilized 
  in more than one LiveViews so as not to drawn Core Components
  """
  use Phoenix.VerifiedRoutes,
    endpoint: MehungryWeb.Endpoint,
    router: MehungryWeb.Router

  use Phoenix.Component
  use Gettext, backend: MehungryWeb.Gettext
  alias Phoenix.LiveView.JS
  import MehungryWeb.CoreComponents
  import MehungryWeb.TabsComponent

  # Same reveal as CoreComponents.show_modal/2 but with no entrance transition —
  # the modal appears in a single frame. Used when a client-side loading
  # skeleton was already on screen (the home feed): replaying the 300ms
  # fade+scale would read as the modal "re-rendering" once the data lands, so we
  # swap the skeleton for the finished modal in place instead.
  def show_modal_instant(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(to: "##{id}-bg")
    |> JS.show(to: "##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def get_color(treaty) do
    case treaty do
      true ->
        "#eb4034"

      false ->
        "none"
    end
  end

  @doc """
  Renders a modal.

  ## Examples

      <.modal id="confirm-modal">
        This is a modal.
      </.modal>

  JS commands may be passed to the `:on_cancel` to configure
  the closing/cancel event, for example:

      <.modal id="confirm" on_cancel={JS.navigate(~p"/posts")}>
        This is another modal.
      </.modal>

  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :animate, :boolean, default: true
  attr :on_cancel, JS, default: %JS{}
  slot :inner_block, required: true

  def recipe_modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && if(@animate, do: show_modal(@id), else: show_modal_instant(@id))}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden max-w-1/2 "
    >
      <div
        id={"#{@id}-bg"}
        class="bg-ink/80 backdrop-blur-sm fixed inset-0 transition-opacity top-0 left-0 right-0"
        aria-hidden="false"
      />
      <div
        class="fixed right-0 inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full sm:mt-20">
          <div class="w-full sm:w-7/12 m-auto">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="relative hidden rounded-2xl bg-ink-panel ring-1 ring-ink-panel2 shadow-2xl shadow-black/50 transition"
            >
              <div class="absolute top-10 left-5 z-50">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class="inline-flex items-center gap-2 text-parchment-dim hover:text-parchment mb-6 transition"
                  aria-label="close"
                  id="close-recipe-modal"
                >
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M10 19l-7-7m0 0l7-7m-7 7h18"
                    />
                  </svg>
                  Back
                </button>
              </div>

              <div id={"#{@id}-content"} class="">
                {render_slot(@inner_block)}
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def ingredient_modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden max-w-1/2 m-auto"
    >
      <div
        id={"#{@id}-bg"}
        class="bg-ink/80 backdrop-blur-sm fixed inset-0 transition-opacity top-0 left-0 right-0"
        aria-hidden="false"
      />
      <div
        class="fixed right-0 inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full sm:mt-20">
          <div class="w-full sm:w-7/12 m-auto">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="relative hidden rounded-2xl bg-ink-panel ring-1 ring-ink-panel2 shadow-2xl shadow-black/50 transition"
            >
              <div class="sm:hidden absolute top-5 left-5 rounded-full w-12 h-12 bg-ink-panel2">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class=" flex-none p-2   hover:opacity-40 w-full h-full "
                  aria-label="close"
                >
                  <.icon name="hero-arrow-left" class="h-6 w-6 " />
                </button>
              </div>

              <div id={"#{@id}-content"} class="sm:p-4">
                {render_slot(@inner_block)}
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def recipe_details(
        %{recipe: _recipe, nutrients: _nutrients, primary_size: _primary_size} = assigns
      ) do
    ~H"""
    <div class="">
      <div style="height: 280px;">
        <.render_tabs
          id="live_comp_tabs_rec"
          contents={MehungryWeb.RecipeDetailsTabsConfig}
          current_user={@current_user}
          recipe={@recipe}
          nutrients={@nutrients}
          primary_size={@primary_size}
          locale={Map.get(assigns, :locale, "en")}
          ingredient_display_names={Map.get(assigns, :ingredient_display_names, %{})}
          ingredient_flags={Map.get(assigns, :ingredient_flags, %{})}
        />
      </div>
    </div>
    """
  end

  def recipe_ingredients(%{recipe_ingredients: recipe_ingredients} = assigns) do
    assigns =
      assigns
      |> component_assigns()
      |> assign(:ingredient_groups, group_by_part(recipe_ingredients, & &1.component_name))

    ~H"""
    <div class=" my-4 ">
      <div class="px-4">
        <div class="bg-ink-panel border border-ink-panel2 divide-y custom-scrollbar divide-ink-panel2 overflow-auto max-h-72">
          <%= for {part, ingredients} <- @ingredient_groups do %>
            <.part_header :if={part} name={part} />
            <%= for ingredient <- ingredients do %>
              <% display_names = Map.get(assigns, :ingredient_display_names, %{}) %>
              <% name =
                Map.get(display_names, ingredient.ingredient_id) ||
                  Mehungry.Utils.remove_parenthesis(ingredient.ingredient.name) %>
              <div class="flex justify-between items-center p-4 hover:bg-black/20 transition">
                <span class="text-parchment">
                  {name}
                </span>
                <span class="font-bold text-basil [font-variant-numeric:tabular-nums]">
                  {ingredient.quantity} {Mehungry.Food.RecipeIngredient.unit_label(ingredient)}
                </span>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def recipe_steps(%{steps: steps} = assigns) do
    assigns =
      assigns
      |> component_assigns()
      |> assign(:step_groups, group_by_part(steps, & &1.title))
      |> assign(:source_url, Map.get(assigns, :original_url))
      |> assign(:source_author, Map.get(assigns, :author))
      |> assign(:source_license, Map.get(assigns, :license))

    ~H"""
    <div class=" my-4 ">
      <div class="px-4">
        <div class="overflow-auto text-base custom-scrollbar bg-ink-panel border border-ink-panel2 max-h-72 px-4   ">
          <%= for {part, steps} <- @step_groups do %>
            <.part_header :if={part} name={part} />
            <%!--
              Number steps per part (1..n within each component), not one
              continuous count across parts — components are often prepared in
              parallel, so a global 1..N would imply a false ordering.
            --%>
            <div
              :for={{step, display_index} <- Enum.with_index(steps, 1)}
              class="step_details_container p-4 border-b border-ink-panel2 "
            >
              <div class="w-8 h-8 rounded-full bg-paprika/20 text-paprika flex items-center justify-center font-bold flex-shrink-0 [font-variant-numeric:tabular-nums] ">
                {display_index}
              </div>
              <div class="text-parchment">{step.description}</div>
            </div>
          <% end %>
        </div>
        <.recipe_source
          :if={@source_url}
          url={@source_url}
          author={@source_author}
          license={@source_license}
        />
      </div>
    </div>
    """
  end

  # Visible source credit for imported recipes (public-domain USDA MyPlate etc.).
  # Only rendered when the recipe carries an `original_url`; app-authored recipes
  # have none and show nothing.
  attr :url, :string, required: true
  attr :author, :string, default: nil
  attr :license, :string, default: nil

  defp recipe_source(assigns) do
    ~H"""
    <p class="px-4 py-3 text-xs text-parchment-dim">
      {gettext("Source")}:
      <a
        href={@url}
        target="_blank"
        rel="noopener nofollow"
        class="underline hover:text-parchment"
      >
        {@author || gettext("Original recipe")}
      </a>
      <%!-- License notice for sources that carry a reuse obligation (e.g.
            UniTools CC BY-SA 4.0). ShareAlike requires the license to travel
            with the adapted recipe. --%>
      <span :if={@license} class="ml-1">· {gettext("Licensed under")} {@license}</span>
    </p>
    """
  end

  # Sub-header marking a recipe part (e.g. "Dressing") inside the ingredient/step
  # lists. Only rendered when a part name is present — single-part recipes show no
  # header and read exactly as before.
  attr :name, :string, required: true

  defp part_header(assigns) do
    ~H"""
    <div class="px-4 pt-4 pb-1 text-xs font-semibold uppercase tracking-wide text-basil">
      {@name}
    </div>
    """
  end

  # These components are invoked as plain functions (e.g. from
  # `RecipeDetailsTabsConfig`) with a raw `%Recipe{}` struct as their assigns.
  # `assign/3` rejects a bare struct — it needs the change-tracking map a HEEx
  # `<.component/>` call injects — so demote the struct to a plain map and add an
  # empty `__changed__` before any `assign/3` call.
  defp component_assigns(%_{} = assigns),
    do: assigns |> Map.from_struct() |> Map.put_new(:__changed__, %{})

  defp component_assigns(assigns), do: Map.put_new(assigns, :__changed__, %{})

  # Groups a list of ingredients/steps by their part label, preserving the order
  # in which each part first appears. A blank/nil label normalises to `nil` (the
  # ungrouped bucket, rendered without a header). When nothing is labelled this
  # returns a single `{nil, items}` group — i.e. the pre-parts flat list.
  defp group_by_part(items, key_fun) when is_list(items) do
    Enum.reduce(items, [], fn item, acc ->
      key = normalize_part(key_fun.(item))

      case List.keyfind(acc, key, 0) do
        {^key, list} -> List.keyreplace(acc, key, 0, {key, list ++ [item]})
        nil -> acc ++ [{key, [item]}]
      end
    end)
  end

  defp group_by_part(_items, _key_fun), do: []

  defp normalize_part(value) when value in [nil, ""], do: nil
  defp normalize_part(value) when is_binary(value), do: String.trim(value) |> nilify_blank()
  defp normalize_part(_value), do: nil

  defp nilify_blank(""), do: nil
  defp nilify_blank(value), do: value

  def recipe_tags(assigns) do
    assigns = assign(assigns, :tags, loaded_hashtags(assigns.recipe))

    ~H"""
    <div :if={@tags != []} class=" m-auto px-4 flex gap-2 my-2 flex-wrap">
      <%= for tag <- @tags do %>
        <.recipe_tag hashtag={tag.hashtag} />
      <% end %>
    </div>
    """
  end

  # Only the recipe_hashtags whose hashtag is actually loaded with a title —
  # tolerates an un-preloaded assoc (%Ecto.Association.NotLoaded{}) or nil hashtag
  # so callers on the cached recipe path can't crash the render.
  defp loaded_hashtags(%{recipe_hashtags: recipe_hashtags}) when is_list(recipe_hashtags) do
    Enum.filter(recipe_hashtags, fn rh ->
      case rh.hashtag do
        %{title: title} when is_binary(title) -> true
        _ -> false
      end
    end)
  end

  defp loaded_hashtags(_), do: []

  def recipe_tag(%{hashtag: %{title: nil}} = assigns),
    do: ~H"""
    """

  def recipe_tag(assigns) do
    uri = ~p"/search/hashtag/" <> assigns.hashtag.title
    assigns = assign(assigns, :uri, uri)

    ~H"""
    <a
      href={@uri}
      class=" inline cursor-pointer w-fit border-2 border-red border-solid rounded-full  border-primary-400 bg-primary-400 px-2"
      id={Integer.to_string(@hashtag.id)}
    >
      <div class="inline bg-primary-400 rounded-full text-white text-base font-semibold">
        {"#" <> @hashtag.title}
      </div>
    </a>
    """
  end

  def recipe_attrs_container(assigns) do
    ~H"""
    <div class="recipe_attrs_container mt-4">
      <div>
        <div><img style="margin:auto;width:35px;height:35px;" src="/images/time_spent.svg" /></div>

        <div class="recipe_attrs_text text-center">
          <%= case is_nil(@recipe.preperation_time_lower_limit) or is_nil(@recipe.cooking_time_lower_limit) do %>
            <% true -> %>
              <div>N/A</div>
            <% false -> %>
              {@recipe.preperation_time_lower_limit + @recipe.cooking_time_lower_limit}
          <% end %>
        </div>
      </div>
      <div>
        <div><img style="margin:auto;width:35px;height:35px;" src="/images/food_dif.svg" /></div>

        <div class="recipe_attrs_text text-center">
          <%= case @recipe.difficulty do %>
            <% 1 -> %>
              Easy
            <% 2 -> %>
              Medium
            <% 3 -> %>
              Difficult
            <% _ -> %>
              N/A
          <% end %>
        </div>
      </div>
      <div>
        <div><img src="/images/bowl.svg" style="margin: auto;width:35px;height:35px;" /></div>
        <div class="recipe_attrs_text text-center">{@recipe.servings}</div>
      </div>
    </div>
    """
  end

  @doc """
  The live recipe-card preview rendered beside the Create Recipe form. It is
  purely presentational — it reads a flat `preview` map (projected from the
  form changeset by `CreateRecipeLive.Index`) plus the image `uploads`, so it
  never touches the changeset or the database itself. Borrows the browse
  `recipe_card` visual language (image-on-top card, basil numbers, editorial
  numbered steps) so what the author builds reads like what they'll publish.
  """
  attr :preview, :map, required: true
  attr :uploads, :map, required: true

  def recipe_preview(assigns) do
    ~H"""
    <div class="recipe-preview overflow-hidden rounded-2xl border border-ink-panel2 bg-ink-panel">
      <div class="flex items-center justify-between gap-2 px-4 pt-4">
        <span class="inline-flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wider text-parchment-dim">
          <span class="relative flex h-2 w-2">
            <span class="absolute inline-flex h-full w-full rounded-full bg-basil/60 animate-ping motion-reduce:hidden">
            </span>
            <span class="relative inline-flex h-2 w-2 rounded-full bg-basil"></span>
          </span>
          {gettext("Live preview")}
        </span>
        <span
          :if={@preview.valid?}
          class="inline-flex items-center gap-1 rounded-full bg-paprika/15 px-2.5 py-1 text-[11px] font-semibold text-paprika-soft"
        >
          <.icon name="hero-check-circle" class="h-3.5 w-3.5" /> {gettext("Ready to save")}
        </span>
      </div>

      <div class="mt-3 px-4">
        <div class="aspect-video w-full overflow-hidden rounded-xl bg-ink-panel2">
          <%= cond do %>
            <% filled?(@preview.image_url) -> %>
              <img src={@preview.image_url} alt="" class="h-full w-full object-cover" />
            <% @uploads.image.entries != [] -> %>
              <%!-- The live client-side preview lives in the form's drop zone (one
                    per upload entry); here we just confirm an image is attached. --%>
              <div class="flex h-full w-full flex-col items-center justify-center gap-1 text-basil">
                <.icon name="hero-check-circle" class="h-8 w-8" />
                <span class="text-xs font-medium">{gettext("Image added")}</span>
              </div>
            <% true -> %>
              <div class="flex h-full w-full items-center justify-center text-parchment-dim">
                <.icon name="hero-photo" class="h-10 w-10" />
              </div>
          <% end %>
        </div>
      </div>

      <div class="space-y-4 p-4">
        <div>
          <h2 class={["font-display text-xl leading-tight", title_class(@preview.title)]}>
            {@preview.title || gettext("Your recipe title")}
          </h2>
          <p class={["mt-1 text-sm", desc_class(@preview.description)]}>
            {@preview.description || gettext("A short description will appear here.")}
          </p>
        </div>

        <div class="flex items-center gap-4 border-y border-ink-panel2 py-3 text-sm">
          <div class="flex items-center gap-1.5">
            <.icon name="hero-clock" class="h-4 w-4 text-parchment-dim" />
            <span class="font-bold tabular-nums text-basil">{total_time(@preview)}</span>
            <span class="text-parchment-dim">{gettext("min")}</span>
          </div>
          <div class="flex items-center gap-1.5">
            <.icon name="hero-user-group" class="h-4 w-4 text-parchment-dim" />
            <span class="font-bold tabular-nums text-basil">{display_servings(@preview.servings)}</span>
            <span class="text-parchment-dim">{gettext("servings")}</span>
          </div>
          <div class="flex items-center gap-1.5">
            <.icon name="hero-signal" class="h-4 w-4 text-parchment-dim" />
            <span class="text-parchment">{difficulty_label(@preview.difficulty)}</span>
          </div>
        </div>

        <div>
          <h3 class="mb-2 text-xs font-semibold uppercase tracking-wide text-parchment-dim">
            {gettext("Ingredients")}
            <span :if={@preview.ingredients != []} class="tabular-nums text-basil">
              ({length(@preview.ingredients)})
            </span>
          </h3>
          <p :if={@preview.ingredients == []} class="text-sm text-parchment-dim/70">
            {gettext("Add ingredients to see them here.")}
          </p>
          <ul :if={@preview.ingredients != []} class="space-y-1">
            <li
              :for={ing <- @preview.ingredients}
              class="flex items-baseline gap-2 text-sm text-parchment"
            >
              <span :if={filled?(ing.quantity)} class="min-w-8 font-bold tabular-nums text-basil">
                {ing.quantity}
              </span>
              <span>{ing.name}</span>
            </li>
          </ul>
        </div>

        <div>
          <h3 class="mb-2 text-xs font-semibold uppercase tracking-wide text-parchment-dim">
            {gettext("Steps")}
            <span :if={@preview.steps != []} class="tabular-nums text-basil">
              ({length(@preview.steps)})
            </span>
          </h3>
          <p :if={@preview.steps == []} class="text-sm text-parchment-dim/70">
            {gettext("Your method will appear here, step by step.")}
          </p>
          <ol :if={@preview.steps != []} class="space-y-3">
            <li :for={{step, i} <- Enum.with_index(@preview.steps, 1)} class="flex gap-3">
              <span class="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-ink-panel2 text-xs font-bold tabular-nums text-basil">
                {i}
              </span>
              <div class="min-w-0">
                <p
                  :if={filled?(step.title)}
                  class="text-xs font-semibold uppercase tracking-wide text-paprika-soft"
                >
                  {step.title}
                </p>
                <p class="text-sm text-parchment">{step.description}</p>
              </div>
            </li>
          </ol>
        </div>
      </div>
    </div>
    """
  end

  defp filled?(value), do: value not in [nil, ""]

  defp title_class(value) when value in [nil, ""], do: "text-parchment-dim/60"
  defp title_class(_), do: "text-parchment"

  defp desc_class(value) when value in [nil, ""], do: "text-parchment-dim/60 italic"
  defp desc_class(_), do: "text-parchment-dim"

  defp display_servings(value) when value in [nil, ""], do: "—"
  defp display_servings(value), do: value

  defp difficulty_label(value) when value in [1, "1"], do: gettext("Easy")
  defp difficulty_label(value) when value in [2, "2"], do: gettext("Medium")
  defp difficulty_label(value) when value in [3, "3"], do: gettext("Difficult")
  defp difficulty_label(_), do: "—"

  defp total_time(%{cooking_time: cooking, prep_time: prep}) do
    case {to_minutes(cooking), to_minutes(prep)} do
      {nil, nil} -> "—"
      {c, p} -> (c || 0) + (p || 0)
    end
  end

  defp to_minutes(nil), do: nil
  defp to_minutes(value) when is_integer(value), do: value

  defp to_minutes(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp to_minutes(_), do: nil

  def post_card_interaction(assigns) do
    ~H"""
    <div class="post_card_details max-w-20  absolute h-full w-1/5 top-0 bottom-0 right-0 sm:-right-20 ">
      <div class="my-auto">
        <div class="utils_container gap-3">
          <div class="cursor-pointer ">
            <MehungryWeb.SvgComponents.upvote_svg post={@post} user={@user} />
          </div>
          <div
            style="display: none; font-size: 1rem; height: 20px; margin-top: auto; margin-bottom: auto;"
            class="font-semibold"
          >
            {length(@post.upvotes)}
          </div>
          <div class="cursor-pointer">
            <MehungryWeb.SvgComponents.downvote_svg post={@post} user={@user} />
          </div>
          <div class="fill-white hidden">
            <.icon name="hero-chat-bubble-oval-left" class="h-7 w-8 flex-none text-white		" />
          </div>
          <.share_button post={@post}></.share_button>
        </div>

        <div
          style="display: none; font-size: 1rem; height: 20px; margin-top: auto; margin-bottom: auto;"
          class="font-semibold"
        >
          {length(@post.reference.comments)}
        </div>
        <div
          style="font-size: 1rem; height: 20px; margin-top: auto; margin-bottom: auto;"
          class="md:block hidden"
        >
        </div>
      </div>
    </div>
    """
  end

  @doc """
  The high-tier nutrient-claim badges to show on a recipe card / detail (the
  truthful EU "High in X" claims, see `Mehungry.Food.NutrientClaims`). Reads the
  persisted, already-coverage-gated `recipe.badges` (string-keyed), filters to the
  `"high"` tier, and keeps the first `limit` (they are stored strongest-first).
  """
  def high_badges(recipe, limit \\ 2) do
    (Map.get(recipe, :badges) || [])
    |> Enum.filter(&(&1["level"] == "high"))
    |> Enum.take(limit)
  end

  def recipe_card(assigns) do
    # Opt-in full live navigation (e.g. cross-LiveView to /browse/:id) instead of
    # the default same-LiveView patch. Existing callers keep patch behavior.
    assigns =
      assigns
      |> assign_new(:navigate_details, fn -> false end)
      |> assign(:nutrient_badges, high_badges(assigns.recipe))

    ~H"""
    <div id={"recipe-card-details-container-#{@id}-#{@recipe.id}"} class="py-2 relative">
      <div
        :if={@nutrient_badges != []}
        class="absolute top-3 left-3 z-10 flex flex-col items-start gap-1"
      >
        <span
          :for={badge <- @nutrient_badges}
          class="rounded-full bg-paprika/90 text-white text-[10px] font-semibold px-2 py-0.5 shadow-sm backdrop-blur-sm"
        >
          {MehungryWeb.NutrientLabels.claim_label(badge["nutrient"])} · {badge["percent_nrv"]}% NRV
        </span>
      </div>
      <.link
        phx-mounter={Phoenix.LiveView.JS.transition("animate-bounce", time: 2000)}
        id={"recipe-card-details-link-#{@id}-#{@recipe.id}"}
        navigate={if @navigate_details, do: @path_to_details}
        patch={unless @navigate_details, do: @path_to_details}
      >
        <div class="bg-ink-panel rounded-xl overflow-hidden border border-ink-panel2 hover:border-paprika/50 transition-all duration-200 group-hover:transform group-hover:-translate-y-1 relative">
          <!-- Image Container -->
          <div class="aspect-video overflow-hidden bg-ink-panel2 w-full ">
            <%= if @recipe.image_url do %>
              <img
                src={@recipe.image_url}
                alt={@recipe.title}
                class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
              />
            <% else %>
              <div class="w-full h-full flex items-center justify-center">
                <svg
                  class="w-12 h-12 text-parchment-dim"
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
              </div>
            <% end %>
          </div>
          <!-- Content -->
          <div class="p-4">
            <h3 class="recipe_title text-parchment font-semibold text-lg line-clamp-1 group-hover:text-paprika transition">
              {@recipe.title}
            </h3>
            <p class="text-parchment-dim text-sm mt-1 line-clamp-2">
              {@recipe.description || "No description available"}
            </p>

            <!-- Recipe Stats -->
            <div class="flex items-center justify-between mt-4 pt-3 border-t border-ink-panel2">
              <div class="flex items-center gap-3">
                <!-- Cooking Time -->
                <div class="flex items-center gap-1">
                  <svg
                    class="w-4 h-4 text-parchment-dim"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  <span class="text-parchment-dim text-xs">
                    <span class="font-bold text-basil [font-variant-numeric:tabular-nums]">{@recipe.cooking_time_lower_limit}</span>
                    min
                  </span>
                </div>

                <!-- Difficulty -->
                <div class="flex items-center gap-1">
                  <%= case @recipe.difficulty do %>
                    <% 1 -> %>
                      <svg
                        class="w-4 h-4 text-green-500"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M5 13l4 4L19 7"
                        />
                      </svg>
                    <% 2 -> %>
                      <svg
                        class="w-4 h-4 text-yellow-500"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                        />
                      </svg>
                    <% 3 -> %>
                      <svg
                        class="w-4 h-4 text-red-500"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M6 18L18 6M6 6l12 12"
                        />
                      </svg>
                    <% _ -> %>
                  <% end %>
                  <span class="text-basil text-xs font-bold capitalize [font-variant-numeric:tabular-nums]">{@recipe.difficulty}</span>
                </div>

                <!-- Servings -->
                <div class="flex items-center gap-1">
                  <svg
                    class="w-4 h-4 text-parchment-dim"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"
                    />
                  </svg>
                  <span class="text-basil text-xs font-bold [font-variant-numeric:tabular-nums]">{@recipe.servings}</span>
                </div>
              </div>

              <!-- Save Count -->
              <div class="flex items-center gap-1">
                <svg
                  class="w-4 h-4 text-red-400"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"
                  />
                </svg>
                <span class="text-basil text-xs font-bold [font-variant-numeric:tabular-nums]">{0}</span>
              </div>
            </div>
          </div>
        </div>
      </.link>
      <%!-- Buttons outside the link so browser clicks reach phx-click, not the link --%>
      <%= if @type != "created" do %>
        <button
          id={"button_save_recipe#{@recipe.id}"}
          phx-click="save_user_recipe"
          phx-value-recipe_id={@recipe.id}
          class="absolute top-5 right-5 z-10 p-2 rounded-full bg-black/50 hover:bg-black/70 transition backdrop-blur-sm"
          type="button"
        >
          <svg
            class="w-5 h-5"
            fill={
              get_color(Enum.any?(Map.get(assigns, :user_recipes, []), fn x -> x == @recipe.id end))
            }
            stroke="#eb4034"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"
            />
          </svg>
        </button>
      <% end %>
      <%= if @type == "created" do %>
        <div class="absolute top-2 right-2 z-10 flex items-center gap-2">
          <button
            id={"edit-recipe-#{@recipe.id}"}
            phx-click="edit-recipe"
            phx-value-id={@recipe.id}
            class="cursor-pointer text-parchment rounded-full p-2 bg-ink-panel hover:bg-ink-panel2 transition"
            type="button"
            aria-label="Edit recipe"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="24"
              height="24"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path d="M12 20h9" />
              <path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4 12.5-12.5z" />
            </svg>
          </button>
          <button
            id={"delete-recipe-#{@recipe.id}"}
            phx-click="delete_recipe"
            phx-value-id={@recipe.id}
            data-confirm={"Delete \"#{@recipe.title}\"? This can't be undone."}
            class="cursor-pointer text-parchment rounded-full p-2 bg-ink-panel hover:bg-red-600 transition"
            type="button"
            aria-label="Delete recipe"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="24"
              height="24"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path d="M3 6h18" />
              <path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6" />
              <path d="M10 11v6" />
              <path d="M14 11v6" />
              <path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2" />
            </svg>
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  def recipe_like_container2(assigns) do
    ~H"""
    <div class="bg-white  ">
      <%= case @type do %>
        <% "saved" -> %>
          <button
            phx-click="unsave-recipe"
            phx-value-id={@recipe.id}
            id={"button_save_recipe#{@recipe.id}"}
          >
            <.icon name="hero-trash-solid" class="h-5 w-5" />
          </button>
        <% "browse" -> %>
          <%= if ! is_nil(@user_recipes)  and ! is_nil(@recipe) do %>
            <svg
              class="w-7 h-7"
              viewBox="0 0 24 24"
              fill={get_color(Enum.any?(@user_recipes, fn x -> x == @recipe.id end))}
              phx-click="save_user_recipe"
              id={"svg-"<> Integer.to_string(@id)}
              phx-value-recipe_id={@recipe.id}
              phx-value-dom_id={@id}
            >
              <path
                fill-rule="evenodd"
                clip-rule="evenodd"
                d="M12 6.00019C10.2006 3.90317 7.19377 3.2551 4.93923 5.17534C2.68468 7.09558 2.36727 10.3061 4.13778 12.5772C5.60984 14.4654 10.0648 18.4479 11.5249 19.7369C11.6882 19.8811 11.7699 19.9532 11.8652 19.9815C11.9483 20.0062 12.0393 20.0062 12.1225 19.9815C12.2178 19.9532 12.2994 19.8811 12.4628 19.7369C13.9229 18.4479 18.3778 14.4654 19.8499 12.5772C21.6204 10.3061 21.3417 7.07538 19.0484 5.17534C16.7551 3.2753 13.7994 3.90317 12 6.00019Z"
                stroke="#eb1111"
                stroke-width="1"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
            </svg>
          <% end %>
        <% "created" -> %>
          <button phx-click="edit-recipe" phx-value-id={@recipe.id}>
            <.icon name="hero-pencil-square-solid" />
          </button>
      <% end %>
    </div>
    """
  end

  def recipe_like_container(%{myself: _myself} = assigns) do
    ~H"""
    <%= if !is_nil(Map.get(assigns, :current_user)) do %>
      <button
        id={@id}
        phx-click="save_user_recipe"
        phx-value-recipe_id={@recipe.id}
        phx-value-dom_id={@id}
        class="absolute top-4 right-4 p-2 rounded-full bg-black/50 hover:bg-black/70 transition backdrop-blur-sm"
      >
        <svg
          class={[
            "w-6 h-6 transition",
            (@type == "saved" && "text-red-500 fill-red-500") || "text-white"
          ]}
          fill={get_color(Enum.any?(@user_recipes, fn x -> x == @recipe.id end))}
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"
          />
        </svg>
      </button>
    <% else %>
      <a
        href="/users/log_in"
        class="absolute top-4 right-4 p-2 rounded-full bg-black/50 hover:bg-black/70 transition backdrop-blur-sm"
      >
        <svg
          class={[
            "w-6 h-6 transition",
            (@type == "saved" && "text-red-500 fill-red-500") || "text-white"
          ]}
          fill={get_color(Enum.any?(@user_recipes, fn x -> x == @recipe.id end))}
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"
          />
        </svg>
      </a>
    <% end %>
    """
  end

  def recipe_like_container(assigns) do
    ~H"""
    <button
      phx-click="toggle_save"
      class="absolute top-4 right-4 p-2 rounded-full bg-black/50 hover:bg-black/70 transition backdrop-blur-sm"
    >
      <svg
        class={[
          "w-6 h-6 transition",
          (@type == "saved" && "text-red-500 fill-red-500") || "text-white"
        ]}
        fill={(@recipe.is_saved && "currentColor") || "none"}
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"
        />
      </svg>
    </button>
    """
  end

  def recipe_nutrients(recipe, locale \\ "en")

  def recipe_nutrients(%Mehungry.Food.Recipe{} = recipe, locale) do
    assigns = %{
      id: recipe.id,
      nutrients: recipe.nutrients,
      primary_size: recipe.primary_nutrients_size || 3,
      servings: recipe.servings || 1,
      locale: locale,
      class: ""
    }

    ~H"""
    <div class="my-4 bg-ink-panel border border-ink-panel2 rounded-xl overflow-hidden">
      <MehungryWeb.NutritionAccordion.nutrition_accordion
        nutrients={@nutrients}
        title={gettext("Nutrition Facts")}
        max_height="600px"
        show_title={true}
        locale={@locale}
        accordion_id={"nutrition-#{@id}"}
      />
    </div>
    """
  end

  @doc """
  Renders an accordion for recipe nutrients - with visual indicators for clickable items.
  Accepts an assigns map; `:locale` localizes the nutrient names, falling back to
  the `locale` argument (default "en") when the map carries none.
  """
  def recipe_nutrients(assigns, locale) do
    assigns = %{
      id: assigns[:id],
      nutrients: assigns[:nutrients],
      primary_size: assigns[:primary_size] || 3,
      servings: assigns[:servings] || 1,
      locale: assigns[:locale] || locale,
      class: assigns[:class] || ""
    }

    ~H"""
    <div class="my-4 bg-ink-panel border border-ink-panel2 rounded-xl overflow-hidden">
      <MehungryWeb.NutritionAccordion.nutrition_accordion
        nutrients={@nutrients}
        title={gettext("Nutrition Facts")}
        max_height="600px"
        show_title={true}
        locale={@locale}
        accordion_id={"nutrition-#{@id}"}
      />
    </div>
    """
  end

  def get_value(map, key) do
    get_value_specific(map, key) || get_value_specific(map, Atom.to_string(key))
  end

  def get_value_specific(map, key) when is_atom(key), do: map[key] || map[to_string(key)]
  def get_value_specific(map, key) when is_binary(key), do: map[key] || map[String.to_atom(key)]

  def render_nutrient_button(assigns) do
    ~H"""
    <button
      id={"nutrient-button-#{@accordion_id}-#{@index}"}
      class={[
        "w-full text-left rounded-lg transition-all duration-150",
        if(@has_children,
          do: "cursor-pointer hover:bg-gray-100 active:scale-[0.99]",
          else: "cursor-default opacity-75"
        ),
        if(@is_primary, do: "font-semibold", else: "font-normal"),
        if(@has_children and @is_primary, do: "bg-gray-50 p-3"),
        if(@has_children and not @is_primary, do: "p-2"),
        if(not @has_children and @is_primary, do: "p-3"),
        if(not @has_children and not @is_primary, do: "p-2")
      ]}
      aria-expanded="false"
      aria-controls={"nutrient-content-#{@accordion_id}-#{@index}"}
      disabled={!@has_children}
    >
      <div class="flex justify-between items-center">
        <div class="flex items-center gap-2 flex-1">
          <div class="w-4 h-4 flex-shrink-0">
            <%= if @has_children do %>
              <div class="transition-transform duration-200 group-[.open]:rotate-90">
                <.icon name="hero-chevron-right" class="w-4 h-4 text-gray-400" />
              </div>
            <% else %>
              <div class="w-1.5 h-1.5 rounded-full bg-gray-300 mt-1.5"></div>
            <% end %>
          </div>

          <span class={
            "flex-1 " <>
            if(@is_primary, do: "text-gray-900 ", else: "text-gray-700 ") <>
            if(not @has_children, do: "text-gray-400", else: "")
          }>
            {format_nutrient_name(@nutrient)}
          </span>
        </div>

        <div class="flex items-center gap-3">
          <span class={
            "text-sm font-mono " <>
            if(@has_children, do: "text-gray-600", else: "text-gray-400")
          }>
            {format_amount(@nutrient, @servings)}
          </span>
          <span class={
            "text-xs " <>
            if(@has_children, do: "text-gray-400", else: "text-gray-300")
          }>
            {format_unit(@nutrient)}
          </span>

          <%= if @has_children do %>
            <div class="w-4 h-4 text-gray-400 transition-transform duration-200">
              <.icon name="hero-chevron-down" class="w-4 h-4" />
            </div>
          <% else %>
            <div class="w-4 h-4"></div>
          <% end %>
        </div>
      </div>
    </button>
    """
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp format_nutrient_name(nutrient) do
    name = Map.get(nutrient, "name", Map.get(nutrient, :name, ""))

    Mehungry.Food.NutrientMapper.humanize_nutrient_name(name)
  end

  defp format_amount(nutrient, servings) do
    amount =
      case nutrient do
        %{"amount" => amt} -> amt
        %{amount: amt} -> amt
        _ -> 0
      end

    cond do
      not is_number(amount) -> "0"
      amount >= 10 -> Float.round(amount / servings, 0) |> to_string()
      amount >= 1 -> Float.round(amount / servings, 1) |> to_string()
      true -> Float.round(amount / servings, 2) |> to_string()
    end
  end

  defp format_unit(nutrient) do
    case nutrient do
      %{"measurement_unit" => unit} when not is_nil(unit) and unit != "" -> unit
      %{measurement_unit: unit} when not is_nil(unit) and unit != "" -> unit
      _ -> "g"
    end
  end
end
