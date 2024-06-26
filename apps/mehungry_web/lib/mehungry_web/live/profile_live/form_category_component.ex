defmodule MehungryWeb.ProfileLive.FormCategoryComponent do
  use Phoenix.Component

  def render(assigns) do
    assigns = assign(assigns, :deleted, Phoenix.HTML.Form.input_value(assigns.f, :delete) == true)

    ~H"""
    <div class={" fields-row-container3" <> if(@deleted, do: "opacity-50", else: "")}>
      <input
        type="hidden"
        name={Phoenix.HTML.Form.input_name(@f, :delete)}
        value={to_string(Phoenix.HTML.Form.input_value(@f, :delete))}
      />
      <input
        type="hidden"
        name={Phoenix.HTML.Form.input_name(@f, :user_id)}
        value={to_string(Phoenix.HTML.Form.input_value(@f, :user_id))}
      />
       <input
        type="hidden"
        name={Phoenix.HTML.Form.input_name(@f, :user_profile_id)}
        value={to_string(Phoenix.HTML.Form.input_value(@f, :user_profile_id))}
      />

      <input
        type="hidden"
        id= {"select_outer_layer" <> to_string(@f.index)}
        name={Phoenix.HTML.Form.input_name(@f, :category_id)}
        value={to_string(Phoenix.HTML.Form.input_value(@f, :category_id))}
      />
       <input
        type="hidden"
        id= {"select2_outer_layer" <> to_string(@f.index)}
        name={Phoenix.HTML.Form.input_name(@f, :food_restriction_type_id)}
        value={to_string(Phoenix.HTML.Form.input_value(@f, :food_restriction_type_id))}
      />
      
      <div class="input-form">
        <div  phx-hook="Select2Multi" phx-update="ignore" id= {"hook_layer" <> to_string(@f.index)} class="" data-hidden-id = {"select_outer_layer" <> to_string(@f.index)} data-index= {to_string(@f.index)} style="position: relative">
          <select class="input select_internal ", style=" height: 100%",  id= {"select_layer" <> to_string(@f.index)}}>
                <%= for i <- @categories do %>
                  <option value= {i.id} >
                    <%= i.name %>
                  </option>
                <% end %>
          </select>
        </div>
      </div>

      <div class="input-form">
        <div  phx-hook="Select2Multi" phx-update="ignore" id= {"hook2_layer" <> to_string(@f.index)} class="" data-hidden-id = {"select2_outer_layer" <> to_string(@f.index)} data-index= {to_string(@f.index)} style="position: relative">
          <select class="input select2_internal ", style=" height: 100%",  id= {"select2_layer" <> to_string(@f.index)}}>
                <%= for i <- @food_restrictions do %>
                  <option value= {i.id} >
                    <%= i.title %>
                  </option>
                <% end %>
          </select>
        </div>
      </div>



      <div class="flex gap-4 items-end">
        <div
          class=""
          type=""
          phx-click="delete_category_rule"
          phx-value-index={@f.index}
          phx-target= {@parent}
          disabled={@deleted}
        >
     <svg phx-click="remove-ingredient"  style="height: 2rem; width=2rem; " viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" style="margin: auto" >
      <path d="M10 12V17" stroke="#000000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M14 12V17" stroke="#000000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M4 7H20" stroke="#000000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M6 10V18C6 19.6569 7.34315 21 9 21H15C16.6569 21 18 19.6569 18 18V10" stroke="#000000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M9 5C9 3.89543 9.89543 3 11 3H13C14.1046 3 15 3.89543 15 5V7H9V5Z" stroke="#000000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>

        </div>
      </div>
    </div>
    """
  end
end
