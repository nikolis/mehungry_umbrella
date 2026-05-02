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
  alias Phoenix.LiveView.JS
  import MehungryWeb.CoreComponents
  import MehungryWeb.TabsComponent

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
  attr :on_cancel, JS, default: %JS{}
  slot :inner_block, required: true

  def recipe_modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden max-w-1/2 m-auto "
    >
      <div
        id={"#{@id}-bg"}
        class="bg-zinc-50/90 fixed inset-0 transition-opacity top-0 left-0 right-0"
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
        <div class="flex min-h-full  sm:mt-20">
          <div class="w-full sm:w-7/12 m-auto" style="">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-2xl bg-white  shadow-lg ring-1 transition "
            >
              <div class=" sm:hidden  absolute top-5 left-5 rounded-full w-12 h-12  bg-white">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class=" flex-none p-2   hover:opacity-40 w-full h-full "
                  aria-label="close"
                  id="close-recipe-modal"
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

  def ingredient_modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden max-w-1/2 m-auto "
    >
      <div
        id={"#{@id}-bg"}
        class="bg-zinc-50/90 fixed inset-0 transition-opacity top-0 left-0 right-0"
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
        <div class="flex min-h-full  sm:mt-20">
          <div class="w-full sm:w-7/12 m-auto" style="">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-2xl bg-white  shadow-lg ring-1 transition "
            >
              <div class=" sm:hidden  absolute top-5 left-5 rounded-full w-12 h-12  bg-white">
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
    <div class="w-11/12  m-auto" style="height: 280px;">
      <.render_tabs
        id="live_comp_tabs_rec"
        contents={MehungryWeb.RecipeDetailsTabsConfig}
        recipe={@recipe}
        nutrients={@nutrients}
        primary_size={@primary_size}
      />
    </div>
    """
  end

  def recipe_ingredients(%{recipe_ingredients: _recipe_ingredients} = assigns) do
    ~H"""
    <div style="max-height: 300px;" class="overflow-auto p-4 text-base text-black">
      <%= for ingredient <- @recipe_ingredients do %>
        <div class="ingredient_details_container font-normal	 ">
          <div>{Mehungry.Utils.remove_parenthesis(ingredient.ingredient.name)}</div>
          <div class="font-semibold">
            {ingredient.quantity} {Mehungry.Utils.remove_parenthesis(ingredient.measurement_unit.name)}
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  def recipe_steps(%{steps: _steps} = assigns) do
    ~H"""
    <div class="overflow-auto p-4 text-base text-black" style="height: 300px;">
      <%= for step <- @steps do %>
        <div class="step_details_container">
          <div class="font-semibold text-lg w-fit">{step.index}</div>
          <div class="text-lg font-normal">{step.description}</div>
        </div>
      <% end %>
    </div>
    """
  end

  def recipe_tags(assigns) do
    ~H"""
    <div class=" m-auto px-4 flex gap-2 my-2 flex-wrap">
      <%= for tag <- @recipe.recipe_hashtags do %>
        <.recipe_tag hashtag={tag.hashtag} />
      <% end %>
    </div>
    """
  end

  def recipe_tag(%{hashtag: %{title: nil}} = assigns),
    do: ~H"""
    """

  def recipe_tag(assigns) do
    uri = ~p"/search/hashtag/" <> assigns.hashtag.title
    assigns = assign(assigns, :uri, uri)

    ~H"""
    <a
      href={@uri}
      class=" inline cursor-pointer w-fit border-2 border-red border-solid rounded-full px-2 border-primaryl2"
      id={Integer.to_string(@hashtag.id)}
    >
      <div class="inline text-greyfriend3 text-base font-semibold">
        {@hashtag.title}
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

  def recipe_card(%{myself: _myself} = assigns) do
    ~H"""
    <div id={"recipe-card-details-container-#{@recipe.id}"} } class="recipe_card">
      <.recipe_like_container
        type={@type}
        user_recipes={@user_recipes}
        recipe={@recipe}
        id={@id}
        myself={@myself}
      />
      <.link
        phx-mounter={Phoenix.LiveView.JS.transition("animate-bounce", time: 2000)}
        id={"recipe-card-details-link-#{@recipe.id}"}
        patch={@path_to_details}
      >
        <img class="w-full rounded-xl m-auto" src={@recipe.image_url} />
        <h1 class="recipe_title text-center">{@recipe.title}</h1>
        <div class="recipe_sub_text text-center">
          Sub title
        </div>
        <.recipe_attrs_container recipe={@recipe} />
      </.link>
    </div>
    """
  end

  def recipe_card(assigns) do
    ~H"""
    <div id={"recipe-card-details-container-#{@recipe.id}"} } class="recipe_card">
      <.recipe_like_container type={@type} user_recipes={@user_recipes} recipe={@recipe} id={@id} />
      <.link
        phx-mounter={Phoenix.LiveView.JS.transition("animate-bounce", time: 2000)}
        id={"recipe-card-details-link-#{@recipe.id}"}
        patch={@path_to_details}
      >
        <img class="w-full rounded-xl m-auto" src={@recipe.image_url} />
        <h1 class="recipe_title text-center">{@recipe.title}</h1>
        <div class="recipe_sub_text text-center">
          Sub title
        </div>
        <.recipe_attrs_container recipe={@recipe} />
      </.link>
    </div>
    """
  end

  def recipe_like_container2(%{myself: _myself} = assigns) do
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
              phx-target={@myself}
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
    <div class="z-40 bg-transparent p-2 rounded-full absolute top-5 right-5 md:top-8 md:left-8 md:w-12 md:h-12 ">
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
          <svg
            width="35px"
            height="35px"
            viewBox="0 0 24 24"
            fill={get_color(Enum.any?(@user_recipes, fn x -> x == @recipe.id end))}
            phx-click="save_user_recipe"
            phx-target={@myself}
            id={"svg-"<> (if is_integer(@id), do: Integer.to_string(@id), else: @id)}
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
        <% "created" -> %>
          <button phx-click="edit-recipe" phx-value-id={@recipe.id}>
            <.icon name="hero-pencil-square-solid" />
          </button>
      <% end %>
    </div>
    """
  end

  def recipe_like_container(assigns) do
    ~H"""
    <div class="recipe_like_container z-10">
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
          <svg
            width="35px"
            height="35px"
            viewBox="0 0 24 24"
            fill={get_color(Enum.any?(@user_recipes, fn x -> x == @recipe.id end))}
            phx-click="save_user_recipe"
            phx-value-recipe_id={@recipe.id}
            phx-value-dom_id={@id}
            id={"button_save_recipe#{@recipe.id}"}
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
        <% "created" -> %>
          <button phx-click="edit-recipe" phx-value-id={@recipe.id}>
            <.icon name="hero-pencil-square-solid" />
          </button>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders an accordion for recipe nutrients - with visual indicators for clickable items
  """
  def recipe_nutrients(assigns) do
    assigns = %{
      id: assigns[:id],
      nutrients: assigns[:nutrients],
      primary_size: assigns[:primary_size] || 3,
      servings: assigns[:servings] || 1,
      class: assigns[:class] || ""
    }

    ~H"""
    <div
      id={"accordion-#{@id}"}
      class={"accordion overflow-auto font-normal #{@class}"}
      style="max-height: 300px;"
      phx-hook="AccordionHook"
    >
      <%= for {_key, nutrient} <- sort_nutrients(@nutrients) do %>
        <%= if !is_nil(nutrient) do %>
          <.render_nutrient_panel
            nutrient={nutrient}
            servings={@servings}
            is_primary={is_primary?(nutrient, sort_nutrients(@nutrients), @primary_size)}
            index={get_nutrient_index(nutrient, sort_nutrients(@nutrients))}
            accordion_id={@id}
            has_children={has_children?(nutrient)}
          />
        <% end %>
      <% end %>
    </div>
    """
  end
  def get_value(map, key) do
    get_value_specific(map, key) || get_value_specific(map, Atom.to_string(key))
  end
  
  def get_value_specific(map, key) when is_atom(key), do: map[key] || map[to_string(key)]
  def get_value_specific(map, key) when is_binary(key), do: map[key] || map[String.to_atom(key)]

  defp render_nutrient_panel(assigns) do
    ~H"""
    <div class={[
      "accordion-panel relative border-b border-gray-200 last:border-0",
      @is_primary && "bg-gray-50"
    ]}>
      <!-- Header Button with visual indicators for clickability -->
      <.render_nutrient_button
        nutrient={@nutrient}
        servings={@servings}
        index={@index}
        accordion_id={@accordion_id}
        is_primary={@is_primary}
        has_children={@has_children}
      />
      
    <!-- Content Panel - only rendered if there are children -->
      <%= if @has_children do %>
        <div class="accordion-content hidden" role="region" aria-hidden="true">
          <div class="px-3 pb-3 pt-1 border-t border-gray-100 bg-white">
            <ul class="space-y-1">
              <%= for child <- get_value(@nutrient, :children) || [] do %>
                <li class="flex justify-between items-center text-sm py-1">
                  <span class="text-gray-600 pl-2">
                    {format_nutrient_name(child)}
                  </span>
                  <span class="font-mono text-gray-500 text-xs">
                    {Float.round(get_value(child, :amount), 2)} {get_value(child, :measurement_unit)}
                  </span>
                </li>
              <% end %>
            </ul>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

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

  defp sort_nutrients(nutrients) do
    Enum.sort_by(nutrients, fn {key, nutrient} ->
      priority =
        case Map.get(nutrient, "name", Map.get(nutrient, :name, "")) do
          "Energy" -> 1
          "Total Fat" -> 2
          "Saturated Fat" -> 3
          "Protein" -> 4
          "Carbohydrates" -> 5
          "Fiber" -> 6
          "Sugars" -> 7
          "Sodium" -> 8
          _ -> 10
        end

      {priority, Map.get(nutrient, "name", "")}
    end)
  end

  defp get_nutrient_index(nutrient, sorted_nutrients) do
    Enum.find_index(sorted_nutrients, fn {_k, v} -> v == nutrient end) || 0
  end

  defp is_primary?(nutrient, sorted_nutrients, primary_size) do
    index = get_nutrient_index(nutrient, sorted_nutrients)
    index <= primary_size
  end

  defp format_nutrient_name(nutrient) do
    name = Map.get(nutrient, "name", Map.get(nutrient, :name, ""))

    case MehungryWeb.FattyAcidFormatter.format(name) do
      "Unknown Fatty Acid" ->
        MehungryWeb.NutrientFormatter.format("", name)

      formatted ->
        formatted
    end
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

  defp has_children?(nutrient) do
  result =
    case nutrient do
      %{"children" => children} when is_list(children) and length(children) > 0 -> true
      %{children: children} when is_list(children) and length(children) > 0 -> true
      _ -> false
    end
    IO.inspect(nutrient, label: "Nutrient")
    IO.inspect(result, label: "----------------------------------------------------------------------------------------------")

    result
  end
end
