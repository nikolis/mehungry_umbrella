defmodule MehungryWeb.ShoppingBasketLive.Components do
  use Phoenix.Component
  use MehungryWeb, :verified_routes

  def get_active_class(basket_1, basket_2) do
    case basket_1.id == basket_2.id do
      true ->
        "active"

      false ->
        ""
    end
  end

  def render_basket_titles(assigns) do
    ~H"""
       <ul id="shopping_baskets_list" class="titles_list"> 

        <%= for shopping_basket <- @shopping_baskets do %>
        <li id={ "li" <> Integer.to_string(shopping_basket.id)}  class={"side_nav_list_item " <> 
        get_active_class(shopping_basket, @shopping_basket)} 
        phx-click ={
    Phoenix.LiveView.JS.push("select_shopping_basket")
              |> Phoenix.LiveView.JS.remove_class("active", to: "#basket-side-navbar.active")
              |> Phoenix.LiveView.JS.add_class("active", to: "#basket-side-navbar:not(.active)")
    }  phx-value-id={shopping_basket.id}> 
          <div class="li_title"> <%= shopping_basket.title %> </div>
          <div class="shopping_list_utils">

            <.link patch={~p"/basket/import_items/#{shopping_basket.id}"}>  <img width="30vw" style="height: 100%;" src="/images/calendar.svg"/> </.link>

            <img width="30vw" src="/images/edit_color.svg" />

            <img width="25vw" src="/images/delete_color.svg" phx-value-id={shopping_basket.id} phx-click="delete_basket" />
          </div>
        </li>
      <% end %>
        </ul>

    """
  end

  def render_basket_items(assigns) do
    ~H"""
       <%= if length(@shopping_basket.basket_ingredients) > 0 do %>
                <table  style="max-height: 650px ;  overflow: scroll; margin-top: 3vh">
                  <%= for rec_ing <- @shopping_basket.basket_ingredients do %>
                    <tr>
                        <td> 
                            <button phx-click="toggle_basket" class={"checkbox " <> get_class_for_toggle_button(rec_ing.in_storage)} phx-value-id={rec_ing.id} >
                              Cla
                            </button>
                        </td>
                        <td style="border-bottom: 1px solid var(--clr-grey-friend_3);
    "> <span style="font-weight: bold;"> <%= rec_ing.quantity %>  <%= rec_ing.measurement_unit.name %> </span> <%= rec_ing.ingredient.name %> </td>
                                                                 </tr>
                  <% end %>
                </table>
             <% end %>
    """
  end

  def get_class_for_toggle_button(in_stock) do
    case in_stock do
      true ->
        "checked"

      false ->
        "unchecked"
    end
  end
end
