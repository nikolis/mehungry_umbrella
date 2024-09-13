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
      class="relative z-50 hidden max-w-1/2"
    >
      <div
        id={"#{@id}-bg"}
        class="bg-zinc-50/90 fixed inset-0 transition-opacity top-0 left-0 right-0"
        aria-hidden="true"
      />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full  justify-center " style="padding-top: 80px;">
          <div class="w-full sm:w-7/12" style="">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-2xl bg-white  shadow-lg ring-1 transition "
            >
              <div class="absolute sm:hidden top-2 left-2 bg-white rounded-full">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class=" flex-none p-2   hover:opacity-40"
                  aria-label="close"
                >
                  <.icon name="hero-arrow-left" class="h-5 w-5" />
                </button>
              </div>

              <div id={"#{@id}-content"}>
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
    <div class="w-11/12  m-auto" style="height: 300px;">
      <.live_component
        module={MehungryWeb.TabsLiveComponent}
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
    <div style="max-height: 300px;" class="overflow-auto">
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

  def recipe_nutrients(%{nutrients: _nutrients, primary_size: _primary_size} = assigns) do
    ~H"""
    <div class="accordion overflow-auto	max-h-1/2 font-normal" style="max-height: 300px;">
      <%= for {n, index} <-  Enum.with_index(@nutrients) do %>
        <%= if !is_nil(n) do %>
          <div class="accordion-panel">
            <h2 id={"panel" <> to_string(index) <> "-title"}>
              <%= if !is_nil(n[:children]) do %>
                <button
                  class="accordion-trigger rounded-xl  pr-6"
                  style="text-align: start; width: 100%; "
                  aria-expanded="false"
                  aria-controls="accordion1-content"
                >
                  <div class="w-fit h-fit rounded-xl absolute right-0 top-0 ">
                    <.icon
                      name="hero-arrow-down-circle "
                      class="h-6 w-6 rounded-xl text-complementary  "
                    />
                  </div>

                  <%= Map.get(n, :name, "Default") <>
                    " " <>
                    if !is_nil(n[:amount]) do
                      to_string(Float.round(n[:amount], 2))
                    else
                      "."
                    end %>
                  <%= if !is_nil(n[:measurement_unit]) do
                    n[:measurement_unit]
                  else
                    ""
                  end %>
                </button>
              <% else %>
                <%= if index < @primary_size do %>
                  <button
                    class="accordion_reccord font-bold	"
                    style="text-align: start; width: 100%;"
                    aria-expanded="false"
                    aria-controls=""
                  >
                    <%= Map.get(n, :name, "Default") <>
                      " " <>
                      if !is_nil(n[:amount]) do
                        to_string(Float.round(n[:amount], 2))
                      else
                        "."
                      end %>
                    <%= if !is_nil(n[:measurement_unit]) do
                      n[:measurement_unit]
                    else
                      ""
                    end %>
                  </button>
                <% else %>
                  <button
                    class="accordion_reccord"
                    style="text-align: start; width: 100%;"
                    aria-expanded="false"
                    aria-controls=""
                  >
                    <%= Map.get(n, :name, "Default") <>
                      " " <>
                      if !is_nil(n[:amount]) do
                        to_string(Float.round(n[:amount], 2))
                      else
                        "."
                      end %>
                    <%= if !is_nil(n[:measurement_unit]) do
                      n[:measurement_unit]
                    else
                      ""
                    end %>
                  </button>
                <% end %>
              <% end %>
            </h2>
            <div
              class="accordion-content"
              role="region"
              aria-labelledby={"panel"<>to_string(index)<>"-title"}
              aria-hidden="true"
              id={"panel"<>to_string(index) <> "-content"}
            >
              <div style="text-center: start;">
                <ul>
                  <%= if !is_nil(n[:children]) do
                  for n_r <- n[:children] do %>
                    <li style="padding-left: 1rem; text-align: start;">
                      <%= n_r.name %> <%= Float.round(n_r.amount, 4) %> <%= n_r.measurement_unit %>
                    </li>
                  <% end end %>
                </ul>
              </div>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  def recipe_steps(%{steps: _steps} = assigns) do
    ~H"""
    <div class="overflow-auto" style="height: 300px;">
      <%= for step <- @steps do %>
        <div class="step_details_container ">
          <div><%= step.index %></div>
          <div class="font-normal"><%= step.description %></div>
        </div>
      <% end %>
    </div>
    """
  end

  def recipe_card(assigns) do
    ~H"""
    <.link
      phx-mounter={Phoenix.LiveView.JS.transition("animate-bounce", time: 2000)}
      id={"recipe-card-details-link-#{@recipe.id}"}
      class="recipe_card"
      patch={@path_to_details}
    >
      <img class="w-full rounded-xl m-auto" src={@recipe.image_url} />
      <div class="recipe_like_container">
        <%= case @type do %>
          <% "saved" -> %>
            <button phx-click="unsave-recipe" phx-value-id={@recipe.id}>
              <.icon name="hero-trash-solid" class="h-5 w-5" />
            </button>
          <% "browse" -> %>
            <svg
              width="35px"
              height="35px"
              viewBox="0 0 24 24"
              fill={get_color(Enum.any?(@user_recipes, fn x -> x == @recipe.id end))}
              XMLNS="http://www.w3.org/2000/svg"
              phx-click="save_user_recipe"
              ,
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
      <h1 class="recipe_title text-center"><%= @recipe.title %></h1>
      <div class="recipe_sub_text text-center">
        Sub title
      </div>
      <div class="recipe_attrs_container mt-6">
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
    </.link>
    """
  end
end
