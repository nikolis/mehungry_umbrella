defmodule MehungryWeb.RecipeBrowseLive.Components do
  use Phoenix.Component
  embed_templates("components/*")
  alias Phoenix.LiveView.JS

  def recipe_details(assigns) do
    ~H"""
    <.recipe_details_page user_recipes={assigns.user_recipes} recipe={assigns.recipe}  />
    """
  end

  def get_color(treaty) do
    case treaty do
      true ->
        "#eb4034"

      false ->
        "none"
    end
  end

  def recipe_modal(assigns) do
    if assigns.recipe do
    end

    case assigns.recipe do
      nil ->
        ~H"""
        """

      _recipe ->
        recipe_nutrients =
          Enum.filter(assigns.recipe_nutrients.flat_recipe_nutrients, fn x -> x.amount > 0 end)
          |> Enum.sort_by(fn x -> x.amount end, :desc)
          |> Enum.map(fn x -> %{x | amount: Float.round(x.amount, 3)} end)

        ~H"""
        <.recipe_modal_page  invocations={assigns.invocations} live_action={assigns.live_action} recipe={assigns.recipe} recipe_nutrients={recipe_nutrients} nutrients = {assigns.nutrients}/>
        """
    end
  end

  alias Phoenix.LiveView.JS

  def hide_modal(js \\ %JS{}) do
    js
    |> JS.hide(transition: "fade-out", to: "#modal2")
  end

  def is_open(action, invocations) do
    IO.inspect(action, label: "action")
    IO.inspect(invocations)

    if invocations > 0 do
      "is-closing"
    else
      "is-open"
    end
  end
end
