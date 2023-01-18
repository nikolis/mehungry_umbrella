defmodule MehungryWeb.SurveyLive do
  use MehungryWeb, :live_view

  alias Mehungry.Survey
  alias Mehungry.Food

  alias MehungryWeb.{DemographicLive, RatingLive, Endpoint}
  @survey_results_topic "survey_results"

  alias __MODULE__.Component

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_demographic
     |> assign_products}
  end

  defp assign_demographic(%{assigns: %{current_user: current_user}} = socket) do
    assign(
      socket,
      :demographic,
      Survey.get_demographic_by_user(current_user)
    )
  end

  def handle_info({:created_demographic, demographic}, socket) do
    {:noreply, handle_demographic_created(socket, demographic)}
  end

  def handle_info({:created_rating, updated_recipe, recipe_index}, socket) do
    {:noreply, handle_rating_created(socket, updated_recipe, recipe_index)}
  end

  def handle_rating_created(
        %{assigns: %{recipes: recipes}} = socket,
        updated_recipe,
        recipe_index
      ) do
    # I'm new!
    Endpoint.broadcast(@survey_results_topic, "rating_created", %{})

    socket
    |> put_flash(:info, "Rating submitted successfully")
    |> assign(
      :recipes,
      List.replace_at(recipes, recipe_index, updated_recipe)
    )
  end

  def handle_demographic_created(socket, demographic) do
    socket
    |> put_flash(:info, "Demographic created successfully")
    |> assign(:demographic, demographic)
  end

  def assign_products(%{assigns: %{current_user: current_user}} = socket) do
    assign(socket, :recipes, list_products(current_user))
  end

  defp list_products(user) do
    Food.list_recipes_with_user_rating(user)
  end
end
