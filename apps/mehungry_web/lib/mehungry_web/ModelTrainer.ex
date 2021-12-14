defmodule MehungryWeb.ModelTrainer do
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
    IO.inspect("Training the user with " <> user_id, label: "Model Trainer")
    users = Cachex.get(:users, "data")

    case users do
      {:ok, data} ->
        case Map.get(data, user_id) do
          nil ->
            {:noreply, :end_of_liefe}

          data ->
            IO.inspect(data, label: "Trainer data")

            grades =
              Enum.map(data, fn {x, grade} ->
                #{int_id, _rest} = Integer.parse(x)
                #recipe = Food.get_recipe!(int_id)
                {int_grade, _rest} = Integer.parse(grade)
                int_grade
              end)
            recipies = 
              Enum.map(data, fn {x, grade} ->
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
          
            {thetas, error} = Reccomendations.optimize_thetas([0, 0, 0, 0], xs, grades, 1_500)

            IO.inspect(recipies, label: "The processed data")
            IO.inspect(grades, label: "The processed grades")
            IO.inspect(thetas, label: "Training paragontas")
            IO.inspect(error, label: "The total model error")

            {:noreply, :end_of_liefe}
        end

      _ ->
        {:noreply, :end_of_liefe}
    end
  end
end
