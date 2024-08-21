defmodule MehungryWeb.RatingLive.Index do
  use Phoenix.Component
  alias MehungryWeb.RatingLive
  import Phoenix.HTML
  use PhoenixHTMLHelpers

  def recipes(assigns) do
    ~H"""
    <div class="survey-component-container">
      <.heading recipes={@recipes} />
      <.list recipes={@recipes} current_user={@current_user} />
    </div>
    """
  end

  def heading(assigns) do
    ~H"""
    <h2>
      Ratings <%= if ratings_complete?(@recipes), do: raw("&#x2713;") %>
    </h2>
    """
  end

  defp ratings_complete?(recipes) do
    Enum.all?(recipes, fn product ->
      length(product.ratings) == 1
    end)
  end

  def list(assigns) do
    ~H"""
    <%= for {recipe, index} <- Enum.with_index(@recipes) do %>
      <%= if rating = List.first(recipe.ratings) do %>
        <RatingLive.Show.stars rating={rating} recipe={recipe} />
      <% else %>
        <.live_component
          module={RatingLive.Form}
          id={"rating-form-#{recipe.id}"}
          recipe={recipe}
          recipe_index={index}
          current_user={@current_user}
        />
      <% end %>
    <% end %>
    """
  end
end
