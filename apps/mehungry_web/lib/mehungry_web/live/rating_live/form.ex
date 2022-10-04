defmodule MehungryWeb.RatingLive.Form do
  use MehungryWeb, :live_component
  alias Mehungry.Survey
  alias Mehungry.Survey.Rating

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_rating()
     |> assign_changeset()}
  end

  def handle_event("validate", %{"rating" => rating_params}, socket) do
    {:noreply, validate_rating(socket, rating_params)}
  end

  def handle_event("save", %{"rating" => rating_params}, socket) do
    {:noreply, save_rating(socket, rating_params)}
  end

  def assign_rating(%{assigns: %{current_user: user, recipe: recipe}} = socket) do
    assign(socket, :rating, %Rating{user_id: user.id, recipe_id: recipe.id})
  end

  def assign_changeset(%{assigns: %{rating: rating}} = socket) do
    assign(socket, :changeset, Survey.change_rating(rating))
  end

  def save_rating(
        %{assigns: %{recipe_index: recipe_index, recipe: recipe}} = socket,
        rating_params
      ) do
    case Survey.create_rating(rating_params) do
      {:ok, rating} ->
        recipe = %{recipe | ratings: [rating]}
        send(self(), {:created_rating, recipe, recipe_index})
        socket

      {:error, %Ecto.Changeset{} = changeset} ->
        assign(socket, changeset: changeset)
    end
  end

  def validate_rating(socket, rating_params) do
    changeset =
      socket.assigns.rating
      |> Survey.change_rating(rating_params)
      |> Map.put(:action, :validate)

    assign(socket, :changeset, changeset)
  end
end
