defmodule MehungryWeb.SeedGenServerSuperServer do
  require Logger

  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    children = [
      {MehungryWeb.SeedsGenWorkerServer, [[]]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

defmodule MehungryWeb.SeedsGenWorkerServer do
  use GenServer

  def start_link(_url) do
    schedule_work()
    pid = GenServer.start_link(__MODULE__, %{}, name: {:global, :seed_worker})
    pid
  end

  # Demands reply/synchronous
  def handle_call(:submit_task_list, _from, %{agent: agent}) do
    _tasks_list = Agent.get(agent, fn x -> x.work_items end)
    {:reply, [], %{work_items: []}}
  end

  def handle_call(:get_work_items, _from, state) do
    tasks_list = Agent.get(state.agent, fn x -> x.work_items end)
    {:reply, tasks_list, state}
  end

  def get_tasks() do
    pid = :global.whereis_name(:seed_worker)
    GenServer.call(pid, :get_work_items)
  end

  def schedule_work() do
    Process.send_after(self(), :work, 10000)
  end

  def handle_info(:work, state) do
    # Do your work here
    url_list = Agent.get(state.agent, fn x -> x.work_items end)

    # IO.inspect(url_list, label: "\n Work Schedule \n")
    list = process_list(url_list)
    Agent.update(state.agent, fn _state -> %{work_items: list} end)
    # Reschedule next work
    schedule_work()
    {:noreply, state}
  end

  def process_list([]) do
    []
  end

  def process_list([url]) do
    try do
      %HTTPoison.Response{body: body} = HTTPoison.get!(url)
      Mehungry.FoodData.Usda.FoodParser.get_ingredients_from_json_body(body)
    rescue
      _the_error ->
        []
    end
  end

  def process_list([url | rest]) do
    try do
      %HTTPoison.Response{body: body} = HTTPoison.get!(url)
      Mehungry.FoodData.Usda.FoodParser.get_ingredients_from_json_body(body)
    rescue
      _the_error ->
        rest
    end

    rest
  end

  def process_list(_) do
    []
  end

  def put_work_list(work_list) do
    pid = :global.whereis_name(:seed_worker)
    GenServer.cast(pid, {:submit_tasks, work_list})
  end

  @doc """
  Clears the pending work queue so a fresh seeding run can be submitted.

  Returns `:ok` when the reset was dispatched, or `{:error, :not_running}`
  when the worker isn't registered.
  """
  def reset() do
    case :global.whereis_name(:seed_worker) do
      :undefined ->
        {:error, :not_running}

      pid ->
        GenServer.cast(pid, :reset)
    end
  end

  # Can't reply
  def handle_cast({:submit_tasks, task_list}, state) do
    _tasks_list = Agent.get(state.agent, fn x -> x.work_items end)
    Agent.update(state.agent, fn _state -> %{work_items: task_list} end)
    {:noreply, state}
  end

  def handle_cast(:reset, state) do
    Agent.update(state.agent, fn _state -> %{work_items: []} end)
    {:noreply, state}
  end

  def init(_url) do
    {:ok, agent} = Agent.start_link(fn -> %{work_items: 0} end)
    schedule_work()
    {:ok, %{agent: agent}}
  end
end
