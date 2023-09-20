defmodule MehungryWeb.RatingLive.Show do
  use Phoenix.Component
  use Phoenix.HTML

  def stars(assigns) do
    stars =
      filled_stars(assigns.rating.stars)
      |> Enum.concat(unfilled_stars(assigns.rating.stars))
      |> Enum.join(" ")
    assigns = assign(assigns, :stars , stars)
    ~H"""
      <div>
        <h4>
          <%= @recipe.title %>:<br/>
          <%= raw @assigns.stars %>
        </h4>
      </div>
    """
  end

  def filled_stars(stars) do
    List.duplicate("&#x2605;", stars)
  end

  def unfilled_stars(stars) do
    List.duplicate("&#x2606;", 5 - stars)
  end
end
