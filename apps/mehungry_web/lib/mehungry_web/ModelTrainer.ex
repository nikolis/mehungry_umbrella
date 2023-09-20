defmodule MehungryWeb.ModelTrainer do
  @moduledoc false

  use GenServer
  alias Mehungry.Food
  alias Mehungry.Reccomendations

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{})
  end

  @impl true
  def init(state) do
    # Schedule work to be performed on start
    {:ok, state}
  end

  @impl true
  def handle_cast({:train, user_id}, _) do
    users = Cachex.get(:users, "data")

    case users do
      {:ok, data} ->
        case Map.get(data, user_id) do
          nil ->
            {:noreply, :end_of_liefe}

          _data ->
            train_set(data)
            {:noreply, :end_of_liefe}
        end

      _ ->
        {:noreply, :end_of_liefe}
    end
  end

  defp train_set(data) do
    grades =
      Enum.map(data, fn {_x, grade} ->
        {int_grade, _rest} = Integer.parse(grade)
        int_grade
      end)

    recipies =
      Enum.map(data, fn {x, _grade} ->
        {int_id, _rest} = Integer.parse(x)
        recipe = Food.get_recipe!(int_id)
        recipe
      end)

    result = Reccomendations.create_reccomender_model(recipies, grades)

    xs =
      Enum.map(result, fn x ->
        x = [1] ++ x
        Numexy.new(x)
      end)

    {_thetas, _error} = Reccomendations.optimize_thetas([0, 0, 0, 0], xs, grades, 1_500)
  end
end
