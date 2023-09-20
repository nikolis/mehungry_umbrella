defmodule MehungryWeb.OnlineRecommender do
  @moduledoc false

  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{})
  end

  @impl true
  def init(state) do
    # Schedule work to be performed on start
    schedule_work()
    {:ok, state}
  end

  @impl true
  def handle_info(:work, state) do
    users = Cachex.get(:users, "data")

    case users do
      {:ok, nil} ->
        schedule_work()
        {:noreply, state}

      {:ok, data} ->
        process_data(data)
        schedule_work()
        {:noreply, state}
    end
  end

  defp process_data(data) do
    users_data_list = Map.to_list(data)

    Enum.each(users_data_list, fn {x, grades} ->
      if length(grades) > 5 do
        {:ok, pid} = GenServer.start_link(MehungryWeb.ModelTrainer, [:hello])
        GenServer.cast(pid, {:train, x})
      else
        nil
      end
    end)
  end

  defp schedule_work do
    # Alternatively, one might write :timer.hours(2)
    Process.send_after(self(), :work, 1 * 500)
  end
end
