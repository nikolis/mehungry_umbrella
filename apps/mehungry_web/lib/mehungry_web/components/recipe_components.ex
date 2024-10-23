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
                >
                  <.icon name="hero-arrow-left" class="h-6 w-6 " />
                </button>
              </div>

              <div id={"#{@id}-content"} class="sm:p-4">
                <%= render_slot(@inner_block) %>
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
          <div><%= ingredient.ingredient.name %></div>
          <div class="font-semibold">
            <%= ingredient.quantity %> <%= ingredient.measurement_unit.name %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  def recipe_nutrients(
        %{nutrients: _nutrients, primary_size: _primary_size, recipe: recipe} = assigns
      ) do
    ~H"""
    <div
      class="accordion overflow-auto	max-h-1/2 font-normal"
      style="max-height: 300px;"
      phx-hook="AccordionHook"
      id={"nutrients"<> to_string(recipe.id)}
    >
      <%= for {{_, n}, index} <-  Mehungry.Food.RecipeUtils.sort_nutrients_from_db(@recipe.nutrients) do %>
        <%= if !is_nil(n) do %>
          <div
            class={
              if index <= @recipe.primary_nutrients_size do
                "accordion-panel relative font-semibold text-base"
              else
                "text-base accordion-panel relative"
              end
            }
            id={"nutrient" <> Integer.to_string(index)}
          >
            <h2 id={"panel" <> to_string(index) <> "-title"}>
              <%= if !is_nil(n) do %>
                <.render_nutrient_button n={n} recipe={@recipe} index={index} />
              <% else %>
                <h3>Nill nutrient</h3>
              <% end %>
            </h2>
            <div
              class="accordion-content "
              role="region"
              aria-labelledby={"panel"<>to_string(index)<>"-title"}
              aria-hidden="true"
              id={"panel"<>to_string(index) <> "-content"}
            >
              <div style="text-center: start;">
                <ul id={"ul" <>to_string(index)} phx-update="ignore">
                  <%= if Map.has_key?(n, "children") do %>
                    <div id={"ul"<> n["name"]}>
                      <%= for n_r <- n["children"] do %>
                        <li style="padding-left: 1rem; text-align: start;" id={"li" <> n_r["name"]}>
                          <%= n_r["name"] %> <%= Float.round(n_r["amount"], 4) %> <%= n_r[
                            "measurement_unit"
                          ] %>
                          <div class="w-fit h-fit rounded-xl absolute right-0 top-0 ">
                            <.icon
                              name="hero-arrow-down-circle "
                              class="h-6 w-6 rounded-xl text-complementary  "
                            />
                          </div>
                        </li>
                      <% end %>
                    </div>
                  <% end %>
                </ul>
              </div>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp render_nutrient_button(assigns) do
    ~H"""
    <div>
      <button
        class="accordion-trigger rounded-xl  pr-6 "
        style="text-align: start; width: 100%; "
        aria-expanded="false"
        aria-controls="accordion1-content"
        id={"nutrient_button" <> Integer.to_string(@index)}
      >
        <%= Map.get(@n, "name") ||
          Map.get(@n, :name, "") <>
            "" %>
        <%= if !is_nil(@n["amount"]) do %>
          <%= to_string(Float.round(@n["amount"] / @recipe.servings, 2)) %>
        <% else %>
          <%= if !is_nil(@n[:amount]) do %>
            <%= to_string(Float.round(@n[:amount] / @recipe.servings, 2)) %>
          <% else %>
            "nothing"
          <% end %>
        <% end %>
        <%= if !is_nil(@n["measurement_unit"]) do %>
          <%= @n["measurement_unit"] %>
        <% else %>
          <%= if !is_nil(@n[:measurement_unit]) do %>
            <%= @n[:measurement_unit] %>
          <% else %>
            "nothing"
          <% end %>
        <% end %>
      </button>
    </div>
    """
  end

  def recipe_steps(%{steps: _steps} = assigns) do
    ~H"""
    <div class="overflow-auto p-4 text-base text-black" style="height: 300px;">
      <%= for step <- @steps do %>
        <div class="step_details_container accordion-panel">
          <div class="font-semibold text-lg"><%= step.index %></div>
          <div class="text-lg font-normal"><%= step.description %></div>
        </div>
      <% end %>
    </div>
    """
  end

  def recipe_tags(assigns) do
    ~H"""
    <div class="w-fit m-auto px-4 flex gap-2 my-2 flex-wrap">
      <%= for recipe_ingredient <- Enum.slice(@recipe.recipe_ingredients, 0..4) do %>
        <.recipe_tag ingredient={recipe_ingredient.ingredient} />
      <% end %>
    </div>
    """
  end

  def recipe_tag(assigns) do
    ~H"""
    <a
      href={~p"/search/" <> Enum.at(String.split(@ingredient.name, ","), 0)}
      class="cursor-pointer w-fit border-2 border-red border-solid rounded-full px-2 border-primaryl2"
      id={Integer.to_string(@ingredient.id)}
    >
      <div class=" text-greyfriend3 text-base font-semibold">
        <%= Enum.at(String.split(@ingredient.name, ","), 0) %>
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
              <%= @recipe.preperation_time_lower_limit + @recipe.cooking_time_lower_limit %>
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
        <div class="recipe_attrs_text text-center"><%= @recipe.servings %></div>
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
            <%= length(@post.upvotes) %>
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
          <%= length(@post.reference.comments) %>
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
        <h1 class="recipe_title text-center"><%= @recipe.title %></h1>
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
        <h1 class="recipe_title text-center"><%= @recipe.title %></h1>
        <div class="recipe_sub_text text-center">
          Sub title
        </div>
        <.recipe_attrs_container recipe={@recipe} />
      </.link>
    </div>
    """
  end

  def recipe_like_container(%{myself: _myself} = assigns) do
    ~H"""
    <div class="bg-white p-2 rounded-full absolute top-5 right-5 md:top-8 md:left-8 md:w-12 md:h-12 ">
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
            id={@id}
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
end
