defmodule MehungryWeb.Worker do 
  use GenServer

  def start_link(task_args) do
    GenServer.start_link(__MODULE__, task_args, name: :via_swarm)
  end

  def init(task_args) do
    %HTTPoison.Response{body: body} = HTTPoison.get!(task_args["file_url"])
    Mehungry.FdcFoodParserLeg.get_ingredients_from_json_body(body)
    {:ok, task_args}
  end

end 
