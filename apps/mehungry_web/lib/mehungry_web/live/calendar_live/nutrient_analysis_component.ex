defmodule MehungryWeb.NutrientAnalysisComponent do
  use MehungryWeb, :live_component

  alias Mehungry.History
  alias Mehungry.FoodUtils

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h3>Total nutrition for day <span class="text-sm">(<%= @particular_date %>)</span></h3>
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
    """
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    user_meals =
      History.list_history_user_meals_for_user(
        socket.assigns.current_user.id,
        socket.assigns.particular_date
      )

    meals_nutrients = FoodUtils.calculate_nutrients_for_meal_list(user_meals)
    {primary_size, nutrients} = post_process_nutrient_list(meals_nutrients)
    socket = assign(socket, :nutrients, nutrients)
    socket = assign(socket, :primary_size, primary_size)

    {:ok, socket}
  end

  def post_process_nutrient_list(nutrients) do
    rest =
      Enum.filter(nutrients, fn x ->
        Float.round(x.amount, 3) != 0
      end)

    {mufa_all, rest} = get_nutrient_category(rest, "MUFA", "Fatty acids, total monounsaturated")
    {pufa_all, rest} = get_nutrient_category(rest, "PUFA", "Fatty acids, total polyunsaturated")
    {sfa_all, rest} = get_nutrient_category(rest, "SFA", "Fatty acids, total saturated")
    {tfa_all, rest} = get_nutrient_category(rest, "TFA", "Fatty acids, total trans")
    {vitamins, rest} = Enum.split_with(rest, fn x -> String.contains?(x.name, "Vitamin") end)

    vitamins_all =
      case length(vitamins) > 0 do
        true ->
          %{name: "Vitamins", amount: nil, measurement_unit: nil, children: vitamins}

        false ->
          nil
      end

    nuts_pre = [mufa_all, pufa_all, sfa_all, tfa_all, vitamins_all]
    nuts_pre = Enum.filter(nuts_pre, fn x -> !is_nil(x) end)

    nuts_pre =
      Enum.map(nuts_pre, fn x ->
        case is_map(x) do
          true ->
            x

          false ->
            Enum.into(x, %{})
        end
      end)

    nutrients = nuts_pre ++ rest
    nutrients = Enum.filter(nutrients, fn x -> !is_nil(x) end)
    energy = Enum.find(nutrients, fn x -> String.contains?(x.name, "Energy") end)
    # energy = %{energy: measurement_unit}
    energy =
      case energy.measurement_unit do
        "kilojoule" ->
          %{energy | amount: energy.amount * 0.2390057361, measurement_unit: "kcal"}

        _ ->
          energy
      end

    carb = Enum.find(nutrients, fn x -> String.contains?(x.name, "Carbohydrate") end)
    protein = Enum.find(nutrients, fn x -> String.contains?(x.name, "Protein") end)
    fiber = Enum.find(nutrients, fn x -> String.contains?(x.name, "Fiber") end)
    fat = Enum.find(nutrients, fn x -> String.contains?(x.name, "Total lipid") end)

    primaries = [energy, fat, carb, protein, fiber]
    primaries = Enum.filter(primaries, fn x -> !is_nil(x) end)
    nutrients = Enum.filter(nutrients, fn x -> x not in primaries end)
    nutrients = primaries ++ nutrients
    {length(primaries), nutrients}
  end

  defp get_nutrient_category(nutrients, category_name, category_sum_name) do
    {category, rest} =
      Enum.split_with(nutrients, fn x -> String.contains?(x.name, category_name) end)

    case length(category) > 0 do
      true ->
        {category_total, rest} =
          Enum.split_with(rest, fn x ->
            String.contains?(x.name, category_sum_name)
          end)

        case length(category_total) == 1 do
          true ->
            {Enum.into(Enum.at(category_total, 0), children: category), rest}

          false ->
            {%{
               amount: 111.1,
               measurement_unit: "to be defined",
               children: category,
               name: category_sum_name
             }, rest}
        end

      false ->
        {nil, rest}
    end
  end
end
