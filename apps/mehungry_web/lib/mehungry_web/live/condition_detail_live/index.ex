defmodule MehungryWeb.ConditionDetailLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.Health

  # Display order + copy for the recommendation groups.
  @recommendation_order ["avoid", "limit", "caution", "monitor", "encourage"]

  @recommendation_labels %{
    "avoid" => "Avoid",
    "limit" => "Limit",
    "caution" => "Approach with caution",
    "monitor" => "Monitor",
    "encourage" => "Encourage"
  }

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Health.get_condition(id) do
      nil ->
        {:ok, push_navigate(socket, to: "/conditions")}

      condition ->
        {:ok,
         socket
         |> assign(:condition, condition)
         |> assign_async([:recommendations, :ingredients], fn ->
           {:ok,
            %{
              recommendations: Health.recommendations_for_condition(condition.id),
              ingredients: Health.ingredients_for_condition(condition.id)
            }}
         end)
         |> assign(:page_title, "#{condition.name} — Dietary Guidance")
         |> assign(
           :page_description,
           "Dietary guidance for #{condition.name}: bioactive compounds to be mindful of and the foods that contain them."
         )}
    end
  end

  # Groups recommendation rows by their `recommendation` value, ordered for display.
  def grouped_recommendations(recommendations) do
    recommendations
    |> Enum.group_by(& &1.recommendation)
    |> Enum.sort_by(fn {rec, _} -> group_order(rec) end)
  end

  defp group_order(rec) do
    case Enum.find_index(@recommendation_order, &(&1 == rec)) do
      nil -> length(@recommendation_order)
      idx -> idx
    end
  end

  def recommendation_label(rec), do: Map.get(@recommendation_labels, rec, String.capitalize(rec))

  # URL slug for the /foods/:slug detail page — mirrors FoodsLive.Index.ingredient_slug/1.
  def ingredient_slug(%{search_name: name}) when is_binary(name) and name != "",
    do: String.replace(name, " ", "-")

  def ingredient_slug(%{name: name}) when is_binary(name), do: String.replace(name, " ", "-")
  def ingredient_slug(_), do: nil
end
