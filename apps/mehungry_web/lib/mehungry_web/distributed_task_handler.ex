defmodule MehungryWeb.DistributedTaskHandler do
  use GenServer

  # Note: Swarm expects a module with :start/1 function
  def start_link(_) do
    Swarm.register_name(__MODULE__, __MODULE__, :start, [[]])
  end

  # This is what Swarm calls
  def start([]) do
    # GenServer.start_link(__MODULE__, nil, name: via_swarm(__MODULE__))
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  # 5 seconds
  @interval 5_000

  defp via_swarm(name), do: {:via, :swarm, name}

  def init(_), do: {:ok, %{}, @interval}

  # Public entry point to trigger tasks
  def run(task_payload) do
    GenServer.cast(via_swarm(__MODULE__), {:run_task, task_payload})
  end

  # Handle different task types dynamically
  def handle_cast({:run_task, %{type: _type, data: data}}, _state) do
    nodes = [node() | Node.list()]
    # Logger.info("Spawning task on nodes: #{inspect(nodes)}")

    Enum.each(nodes, fn n ->
      :rpc.call(n, __MODULE__, :spawn_task, [%{file_name: data.file_url}])
    end)

    {:noreply, %{working: nodes, waiting: []}, @interval}
  end
end
