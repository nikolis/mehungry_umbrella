defmodule MehungryWeb.RecipeBrowseLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.Recipe
  @user_id 5

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :recipes, list_recipes())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Categories")
    |> assign(:category, nil)
  end

  @impl true
  def handle_event("review", %{"id" => id, "points" => points}, socket) do
    # %{"user_id" => [{recipe_id, grade}]}
    # To be fixed I need to use a map instead if I want to keep a single grade for the a particular recipe
    users = Cachex.get(:users, "data")

    new_content =
      case users do
        {:ok, nil} ->
          %{to_string(@user_id) => [{id, points}]}

        {:ok, user_content} ->
          case Map.get(user_content, to_string(@user_id)) do
            nil ->
              Map.put(user_content, to_string(@user_id), [{id, points}])

            content ->
              new_list = content ++ [{id, points}]
              Map.put(user_content, to_string(@user_id), new_list)
          end
      end

    IO.inspect(new_content, label: "Review event")

    case Cachex.put(:users, "data", new_content) do
      {:ok, true} ->
        IO.inspect("Sucess", label: "Puting to cache")

      {errorm, reason} ->
        IO.inspect(reason, label: "Puting to cache")
    end

    {:noreply, assign(socket, :recipes, list_recipes())}
  end

  defp list_recipes do
    Food.list_recipes()
  end
end
