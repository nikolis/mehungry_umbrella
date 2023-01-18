defmodule MehungryWeb.Admin.SurveyResultsLive do
  use MehungryWeb, :live_component
  use MehungryWeb, :chart_live

  alias Mehungry.Food
  alias Contex.Plot

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_age_group_filter()
     |> assign_products_with_average_ratings()
     |> assign_dataset()
     |> assign_chart()
     |> assign_chart_svg()}
  end

  def assign_age_group_filter(socket, age_group_filter) do
    assign(socket, :age_group_filter, age_group_filter)
  end

  def assign_age_group_filter(%{assigns: %{age_group_filter: age_group_filter}} = socket) do
    assign(socket, :age_group_filter, age_group_filter)
  end

  def assign_age_group_filter(socket) do
    socket
    |> assign(:age_group_filter, "all")
  end

  def assign_chart_svg(%{assigns: %{chart: chart}} = socket) do
    socket
    |> assign(:chart_svg, render_bar_chart(chart, title(), subtitle(), x_axis(), y_axis()))
  end

  defp title do
    "Recipes Ratings"
  end

  defp subtitle do
    "Average star ratings per Recipe"
  end

  defp x_axis do
    "recipes"
  end

  defp y_axis do
    "stars"
  end

  def assign_dataset(
        %{
          assigns: %{
            recipes_with_average_ratings: recipes_with_average_ratings
          }
        } = socket
      ) do
    socket
    |> assign(
      :dataset,
      make_bar_chart_dataset(recipes_with_average_ratings)
    )
  end

  defp assign_chart(%{assigns: %{dataset: dataset}} = socket) do
    socket
    |> assign(:chart, make_bar_chart(dataset))
  end

  defp assign_products_with_average_ratings(
         %{assigns: %{age_group_filter: age_group_filter}} = socket
       ) do
    socket
    |> assign(
      :recipes_with_average_ratings,
      get_recipes_with_average_ratings(%{age_group_filter: age_group_filter})
    )
  end

  defp get_recipes_with_average_ratings(filter) do
    case Food.recipes_with_average_ratings(filter) do
      [] ->
        Food.recipes_with_zero_ratings()

      recipes ->
        recipes
    end
  end

  ############ Events Handling #####################################################################333
  def handle_event(
        "age_group_filter",
        %{"age_group_filter" => age_group_filter},
        socket
      ) do
    {:noreply,
     socket
     |> assign_age_group_filter(age_group_filter)
     |> assign_products_with_average_ratings()
     |> assign_dataset()
     |> assign_chart()
     |> assign_chart_svg()}
  end
end
