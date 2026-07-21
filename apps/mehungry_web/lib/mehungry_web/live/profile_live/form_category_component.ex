defmodule MehungryWeb.ProfileLive.FormCategoryComponent do
  use Phoenix.Component

  def render(assigns) do
    assigns = assign(assigns, :deleted, Phoenix.HTML.Form.input_value(assigns.f, :delete) == true)

    ~H"""
    <div class={"flex items-center gap-2 sm:gap-4 rounded-lg border border-ink-panel2 bg-black/20 p-2 sm:p-2.5" <> if(@deleted, do: " hidden", else: "")}>
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

      <div class="flex-1 min-w-0">
        <.live_component
          module={MehungryWeb.SelectComponent}
          form={@f}
          items={Enum.map(@categories, fn x -> {Integer.to_string(x.id), x.name} end)}
          input_variable={:category_id}
          id={"category_search_component" <> Integer.to_string(@f.index)}
        />
      </div>

      <div class="flex-1 min-w-0">
        <.live_component
          module={MehungryWeb.SelectComponent}
          form={@f}
          items={Enum.map(@food_restrictions, fn x -> {Integer.to_string(x.id), x.title} end)}
          input_variable={:food_restriction_type_id}
          id={"food_restriction_search_component" <> Integer.to_string(@f.index)}
        />
      </div>

      <button
        type="button"
        phx-click="delete_category_rule"
        phx-value-index={@f.index}
        phx-target={@parent}
        disabled={@deleted}
        aria-label="Remove rule"
        class="flex-none text-parchment-dim hover:text-red-400 transition-colors p-1.5"
      >
        <svg
          viewBox="0 0 24 24"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
          style="height: 1.375rem; width: 1.375rem;"
        >
          <path
            d="M10 12V17"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
          <path
            d="M14 12V17"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
          <path
            d="M4 7H20"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
          <path
            d="M6 10V18C6 19.6569 7.34315 21 9 21H15C16.6569 21 18 19.6569 18 18V10"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
          <path
            d="M9 5C9 3.89543 9.89543 3 11 3H13C14.1046 3 15 3.89543 15 5V7H9V5Z"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
      </button>
    </div>
    """
  end
end
