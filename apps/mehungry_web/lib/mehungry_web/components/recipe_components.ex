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
      class="relative z-50 hidden max-w-1/2 "
    >
      <div
        id={"#{@id}-bg"}
        class="bg-slate-950/75 backdrop-blur-sm fixed inset-0 transition-opacity top-0 left-0 right-0"
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
              class="relative hidden rounded-2xl bg-slate-900 ring-1 ring-slate-700 shadow-2xl shadow-black/50 transition"
            >
              <div class="absolute top-10 left-5 z-50">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class="inline-flex items-center gap-2 text-slate-300 hover:text-white mb-6 transition"
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
        class="bg-slate-950/75 backdrop-blur-sm fixed inset-0 transition-opacity top-0 left-0 right-0"
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
              class="relative hidden rounded-2xl bg-slate-800 ring-1 ring-slate-700 shadow-2xl shadow-black/50 transition"
            >
              <div class="sm:hidden absolute top-5 left-5 rounded-full w-12 h-12 bg-slate-700">
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
    <div class="" style="height: 280px;">
      <.render_tabs
        id="live_comp_tabs_rec"
        contents={MehungryWeb.RecipeDetailsTabsConfig}
        current_user={@current_user}
        recipe={@recipe}
        nutrients={@nutrients}
        primary_size={@primary_size}
        ingredient_display_names={Map.get(assigns, :ingredient_display_names, %{})}
      />
    </div>
    """
  end

  def recipe_ingredients(%{recipe_ingredients: _recipe_ingredients} = assigns) do
    ~H"""
    <div class=" my-4 ">
      <div class="px-4">
        <div class="bg-slate-800 border border-slate-700 divide-y custom-scrollbar divide-slate-700 overflow-auto max-h-72">
          <%= for ingredient <- @recipe_ingredients do %>
            <% display_names = Map.get(assigns, :ingredient_display_names, %{}) %>
            <% name = Map.get(display_names, ingredient.ingredient_id) ||
                      Mehungry.Utils.remove_parenthesis(ingredient.ingredient.name) %>
            <div class="flex justify-between items-center p-4 hover:bg-slate-700/30 transition">
              <span class="text-white">
                {name}
              </span>
              <span class="text-slate-400">
                {ingredient.quantity} {ingredient.measurement_unit.name}
              </span>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def recipe_steps(%{steps: _steps} = assigns) do
    ~H"""
    <div class=" my-4 ">
      <div class="px-4">
        <div class="overflow-auto text-base custom-scrollbar text-black  bg-slate-800 max-h-72 px-4   ">
          <%= for step <- @steps do %>
            <div class="step_details_container p-4 border-b border-slate-700 ">
              <div class="w-8 h-8 rounded-full bg-primary-500/20 text-primary-500 flex items-center justify-center font-semibold flex-shrink-0  ">
                {step.index}
              </div>
              <div class="text-white">{step.description}</div>
            </div>
          <% end %>
        </div>
      </div>
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
    <div id={"recipe-card-details-container-#{@id}-#{@recipe.id}"} class="group">
      <.recipe_like_container
        type={@type}
        user_recipes={@user_recipes}
        recipe={@recipe}
        id={@id}
        current_user={@current_user}
        myself={@myself}
      />
      <.link
        phx-mounter={Phoenix.LiveView.JS.transition("animate-bounce", time: 2000)}
        id={"recipe-card-details-link-#{@id}-#{@recipe.id}"}
        patch={@path_to_details}
      >
        <div class="bg-slate-800 rounded-xl overflow-hidden border border-slate-700 hover:border-primary-500/50 transition-all duration-200 group-hover:transform group-hover:-translate-y-1">
          
    <!-- Image Container -->
          <div class="relative aspect-video overflow-hidden bg-slate-700">
            <%= if ! is_nil(@recipe.image_url) do %>
              {inspect(@recipe.image_url)}
              <img class="w-full rounded-xl m-auto" src={@recipe.image_url} />
            <% else %>
              <div class="w-full h-full flex items-center justify-center">
                <svg
                  class="w-12 h-12 text-slate-500"
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
          <h1 class="recipe_title text-center">{@recipe.title}</h1>
          <div class="recipe_sub_text text-center">
            Sub title
          </div>
          <.recipe_attrs_container recipe={@recipe} />
        </div>
      </.link>
    </div>
    """
  end

  def recipe_card(assigns) do
    ~H"""
    <div id={"recipe-card-details-container-#{@id}-#{@recipe.id}"} class="py-2 relative">
      <.link
        phx-mounter={Phoenix.LiveView.JS.transition("animate-bounce", time: 2000)}
        id={"recipe-card-details-link-#{@id}-#{@recipe.id}"}
        patch={@path_to_details}
      >
        <div class="bg-slate-800 rounded-xl overflow-hidden border border-slate-700 hover:border-primary-500/50 transition-all duration-200 group-hover:transform group-hover:-translate-y-1 relative">
          <!-- Image Container -->
          <div class="aspect-video overflow-hidden bg-slate-700 w-full ">
            <%= if @recipe.image_url do %>
              <img
                src={@recipe.image_url}
                alt={@recipe.title}
                class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
              />
            <% else %>
              <div class="w-full h-full flex items-center justify-center">
                <svg
                  class="w-12 h-12 text-slate-500"
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
            <h3 class="recipe_title text-white font-semibold text-lg line-clamp-1 group-hover:text-primary-500 transition">
              {@recipe.title}
            </h3>
            <p class="text-slate-400 text-sm mt-1 line-clamp-2">
              {@recipe.description || "No description available"}
            </p>
            
    <!-- Recipe Stats -->
            <div class="flex items-center justify-between mt-4 pt-3 border-t border-slate-700">
              <div class="flex items-center gap-3">
                <!-- Cooking Time -->
                <div class="flex items-center gap-1">
                  <svg
                    class="w-4 h-4 text-slate-500"
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
                  <span class="text-slate-400 text-xs">{@recipe.cooking_time_lower_limit} min</span>
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
                  <span class="text-slate-400 text-xs capitalize">{@recipe.difficulty}</span>
                </div>
                
    <!-- Servings -->
                <div class="flex items-center gap-1">
                  <svg
                    class="w-4 h-4 text-slate-500"
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
                  <span class="text-slate-400 text-xs">{@recipe.servings}</span>
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
                <span class="text-slate-400 text-xs">{0}</span>
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
            fill={get_color(Enum.any?(Map.get(assigns, :user_recipes, []), fn x -> x == @recipe.id end))}
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
        <button
          id={"edit-recipe-#{@recipe.id}"}
          phx-click="edit-recipe"
          phx-value-id={@recipe.id}
          class="absolute top-2 right-2 cursor-pointer text-white z-10 rounded-full p-2 bg-slate-800 hover:bg-slate-700 transition"
          type="button"
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

  def recipe_nutrients(%Mehungry.Food.Recipe{} = recipe) do
    assigns = %{
      id: recipe.id,
      nutrients: recipe.nutrients,
      primary_size: recipe.primary_nutrients_size || 3,
      servings: recipe.servings || 1,
      class: ""
    }

    ~H"""
    <div class="my-4 ">
      <MehungryWeb.NutritionAccordion.nutrition_accordion
        nutrients={@nutrients}
        title="Nutrition Facts"
        max_height="600px"
        show_title={true}
      />
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
    <div class="my-4">
      <MehungryWeb.NutritionAccordion.nutrition_accordion
        nutrients={@nutrients}
        title="Nutrition Facts"
        max_height="600px"
        show_title={true}
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

    MehungryWeb.NutrientMapper.humanize_nutrient_name(name)
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
