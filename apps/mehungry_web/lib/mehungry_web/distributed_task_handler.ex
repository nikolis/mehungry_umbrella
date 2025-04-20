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

  def init(_), do: {:ok, %{}, @intervals}

  # Public entry point to trigger tasks
  def run(task_payload) do
    GenServer.cast(via_swarm(__MODULE__), {:run_task, task_payload})
  end

  # Handle different task types dynamically
  def handle_cast({:run_task, %{type: type, data: data}}, state) do
    nodes = [node() | Node.list()]
    IO.inspect(nodes, label: "Dhte nodes")
    # Logger.info("Spawning task on nodes: #{inspect(nodes)}")

    Enum.each(nodes, fn n ->
      :rpc.call(n, __MODULE__, :spawn_task, [%{file_name: data.file_url}])
    end)

    {:noreply, %{working: nodes, waiting: []}, @interval}
  end

  defp handle_task(:parse_and_insert, %{file_url: {:ok, file_url}}) do
    %HTTPoison.Response{body: body} = HTTPoison.get!(file_url)
    Mehungry.FdcFoodParserLeg.get_ingredients_from_json_body(body)
    # parsed = MehungryWeb.Parser.parse(%{raw: raw})
    # MehungryWeb.Repo.insert!(parsed)
  end

  defp handle_task(:notify_user, %{user_id: id, message: msg}) do
    IO.puts("📣 Notify user #{id}: #{msg}")
    # Maybe call your mailer or PubSub here
  end

  defp handle_task(:export_csv, %{report_id: id}) do
    IO.puts("📤 Exporting CSV for report #{id}")
    # Imagine generating and saving a report here
  end

  defp handle_task(other, _) do
    IO.puts("❓ Unknown task type: #{inspect(other)}")
  end
end
