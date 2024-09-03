defmodule MehungryWeb.RecipeBrowserLive.RecipeDetailsComponent do
  use MehungryWeb, :live_component

  def get_color(treaty) do
    case treaty do
      true ->
        "#eb4034"

      false ->
        "none"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div phx-hook="SwapElement" id="recipe_presentation_modal">
      <div style="min-height: 140vh" class="mt-8">
        <h3 class="recipe_details_title text-center mt-10"><%= @recipe.title %></h3>
        <h2 class="recipe_details_sub_title text-center"><%= @recipe.description %></h2>
        <div
          class="recipe_attrs_container md:w-1/3"
          ,
          style="margin: auto; padding-bottom: 1.5rem; padding-top: 0rem;"
        >
          <div>
            <div>
              <img style="margin:auto;width:35px;height:35px;" src="/images/time_spent.svg" />
            </div>
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

        <div class="recipe_ingredients_steps_container">
          <div class="relative">
            <img
              class="recipe_img img_cnt lg:w-fit "
              src={@recipe.image_url}
              style="height: 70vh; border-radius: 7px;"
            />
            <div class="recipe_like_container">
              <svg
                width="35px"
                height="35px"
                viewBox="0 0 24 24"
                fill={get_color(Enum.any?(@user_recipes, fn x -> x == @recipe.id end))}
                xmlns="http://www.w3.org/2000/svg"
                phx-click="save_user_recipe_dets"
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
            </div>
          </div>
          <div
            id="flip_card"
            class="recipe_ingredients_container md:max-w-xl	 flip_card"
            style="width: 95%;"
          >
            <button class="switch_button" id="button_swap_ingredients">
              <svg
                id="button_swap_ingredients"
                width="2rem"
                height="2rem"
                viewBox="0 0 64 64"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                stroke-width="2"
                stroke="#000000"
              >
                <polyline points="32 24 40 24 40 16 56 28 40 40 40 32 24 32 24 24 8 36 24 48 24 40 32 40" />
              </svg>
            </button>

            <div class="flip_card_inner" style="height: 60vh">
              <div class="flip_card_front overflow-x-auto">
                <h3 class="recipe_section_header">Recipe Ingredients</h3>
                <%= for ingredient <- @recipe.recipe_ingredients do %>
                  <div class="ingredient_details_container text-sm md:text-base lg:text-lg font-medium">
                    <div><%= ingredient.ingredient.name %></div>
                    <div><%= ingredient.quantity %> <%= ingredient.measurement_unit.name %></div>
                  </div>
                <% end %>
              </div>
              <div
                class="flip_card_back wrapper overflow-x-auto"
                phx-hook="AccordionHook"
                id="recipe_nutrients_accordion"
                ,
                style="overflow-x: scroll; height: 100%; width: 100%"
              >
                <h3 class="recipe_section_header">Recipe Nutrients</h3>

                <div class="accordion text-sm md:text-base lg:text-lg font-medium	">
                  <%= for {n, index} <-  Enum.with_index(@nutrients) do %>
                    <%= if !is_nil(n) do %>
                      <div class="accordion-panel">
                        <h2 id={"panel" <> to_string(index) <> "-title"}>
                          <%= if !is_nil(n[:children]) do %>
                            <button
                              class="accordion-trigger rounded-xl  pr-6"
                              style="text-align: start; width: 100%; background-color:white ; "
                              aria-expanded="false"
                              aria-controls="accordion1-content"
                            >
                              <div class="w-fit h-fit bg-white rounded-xl absolute right-0 top-0 ">
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
              </div>
            </div>
          </div>
          <div class="recipe_steps_container" , style="width: 95%;">
            <h3 class="recipe_section_header text-center">Preperation Steps</h3>
            <%= for step <- @recipe.steps do %>
              <div class="step_details_container text-sm md:text-base lg:text-lg font-medium	">
                <div><%= step.index %></div>
                <div><%= step.description %></div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      assign(socket, assigns)

    {:ok, socket}
  end
end
