defmodule Mehungry.ObanWorkers.NutritionistAgentWorker do
  @moduledoc """
  Oban worker that runs the NutritionistAgent for a professional + client pair.

  Each tool call is broadcast over PubSub so the LiveView can show real-time
  progress without polling.

  PubSub topic: "nutritionist_agent:{professional_id}"
  Events (wrapped in {:nutritionist_agent, event}):
    {:started, client_name}
    {:step, human_readable_label}
    {:done, summary_text}
    {:error, reason}
  """

  use Oban.Worker, queue: :ai_agents, max_attempts: 1

  require Logger
  alias Mehungry.AI.Agents.NutritionistAgent

  @tool_labels %{
    "get_client_summary" => "Reading client profile…",
    "get_recent_meals" => "Checking recent meal history…",
    "get_ratings" => "Reviewing meal ratings…",
    "search_recipes" => "Searching recipe catalog…",
    "submit_plan" => "Validating and creating meal plan…"
  }

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "professional_id" => professional_id,
          "client_id" => client_id,
          "preferences" => preferences,
          "client_name" => client_name
        }
      }) do
    topic = topic(professional_id)

    broadcast(topic, {:started, client_name})

    on_event = fn
      {:tool_call, name} ->
        label = Map.get(@tool_labels, name, "Working…")
        broadcast(topic, {:step, label})

      {:tool_result, _name, _result} ->
        :ok
    end

    Logger.info(
      "NutritionistAgentWorker: starting for professional=#{professional_id} client=#{client_id}"
    )

    case NutritionistAgent.run(professional_id, client_id, preferences, on_event: on_event) do
      {:ok, summary} ->
        broadcast(topic, {:done, summary})
        :ok

      {:error, reason} ->
        Logger.warning("NutritionistAgentWorker: agent error: #{inspect(reason)}")
        broadcast(topic, {:error, to_string(reason)})
        {:error, reason}
    end
  end

  @doc "Enqueue a plan-drafting job. Returns {:ok, job} or {:error, reason}."
  def enqueue(professional_id, client_id, client_name, preferences \\ "") do
    %{
      professional_id: professional_id,
      client_id: client_id,
      client_name: client_name,
      preferences: preferences
    }
    |> new()
    |> Oban.insert()
  end

  @doc "PubSub topic for a given professional."
  def topic(professional_id), do: "nutritionist_agent:#{professional_id}"

  defp broadcast(topic, event) do
    Phoenix.PubSub.broadcast(Mehungry.PubSub, topic, {:nutritionist_agent, event})
  end
end
