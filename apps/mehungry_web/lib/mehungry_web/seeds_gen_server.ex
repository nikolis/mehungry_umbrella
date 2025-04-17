defmodule MehungryWeb.SeedGenServerSuperServer do 

  use Supervisor 

  def start_link do 
    Supervisor.start_link(__MODULE__, []) 
  end

  def init([]) do 
    children = [
      worker(MehungryWeb.SeedsGenWorkerServer, [[]])
    ]
    supervise(children, strategy: :one_for_one) 
  end

end

defmodule MehungryWeb.SeedsGenWorkerServer do 

  use GenServer 

  def start_link(url) do 
    schedule_work()
    pid = GenServer.start_link(__MODULE__, %{}, name: {:global, :seed_worker})
    pid
  end

  #Demands reply/synchronous 
  def handle_call(:submit_task_list, _from, %{agent: agent}) do
     tasks_list = Agent.get(agent, fn x -> x.work_items end)
    {:reply, [], %{work_items: tasks_list}} 
  end

  def get_tasks() do 
    pid = :global.whereis_name(:seed_worker)
    GenServer.call(pid, :get_work_items) 
  end

  def handle_call(:get_work_items, _from, state)
  do 
    tasks_list = Agent.get(state.agent, fn x -> x.work_items end)
    {:reply,  tasks_list, state
    }
  end

  def schedule_work() do 
    Process.send_after(self(), :work, 10000)
  end

  def handle_info(:work, state) do
    # Do your work here
    url_list = Agent.get(state.agent, fn x -> x.work_items end)

    list = process_list(url_list) 
    Agent.update(state.agent, fn state -> %{work_items: list} end)
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
      Mehungry.FdcFoodParserLeg.get_ingredients_from_json_body(body)
    rescue 
      the_error -> 
      []
    end
  end
  
  def process_list([url | rest]) do
    {:ok, url} = url
    try do
      %HTTPoison.Response{body: body} = HTTPoison.get!(url)
      Mehungry.FdcFoodParserLeg.get_ingredients_from_json_body(body)
    rescue 
      the_error -> 
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


  #Can't reply 
  def handle_cast({:submit_tasks, task_list}, state) do
    tasks_list = Agent.get(state.agent, fn x -> x.work_items end)
    Agent.update(state.agent, fn state -> %{work_items: task_list} end)
    {:noreply, state}
  end

  def init(url) do 
    {:ok, agent} = Agent.start_link(fn  -> %{work_items: 0} end)
    schedule_work()
    {:ok,  %{agent: agent}} 
  end

end
