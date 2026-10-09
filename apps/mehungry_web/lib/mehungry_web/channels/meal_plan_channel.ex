defmodule MehungryWeb.MealPlanChannel do
  @moduledoc """
  AI meal-plan generation progress (spec §13 `meal_plan:<user_id>`). A socket may
  only join its own topic. `MehungryWeb.Api.MealPlanWorker` broadcasts
  `"progress"` and `"result"` events here.
  """
  use MehungryWeb, :channel

  @impl true
  def join("meal_plan:" <> user_id, _payload, socket) do
    if socket.assigns[:user_id] != nil and to_string(socket.assigns.user_id) == user_id do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end
end
