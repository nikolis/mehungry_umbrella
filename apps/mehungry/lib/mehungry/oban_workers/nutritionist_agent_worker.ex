defmodule Mehungry.ObanWorkers.NutritionistAgentWorker do
  @moduledoc """
  Oban worker that runs `NutritionistMealPlanAgent` for a professional + client
  pair — the one path behind both nutritionist surfaces (the client file's
  "AI Assist" and the client calendar's draft). Because the run lives in Oban,
  leaving the page never cancels it.

  `start/1` is the single front door: it checks the nutritionist's
  `"nutritionist_meal_plan"` quota, refuses a second concurrent draft for the same
  client, and enqueues. The worker then generates the plan, writes it to the
  client's calendar in the chosen existing-meals mode, and records usage only
  when meals were actually created.

  Each tool call is broadcast over PubSub so a LiveView can show real-time
  progress without polling.

  PubSub topic: "nutritionist_agent:{professional_id}"
  Events (wrapped in `{:nutritionist_agent, client_id, event}` so a page showing
  one client ignores another client's run):
    {:started, client_name}
    {:step, human_readable_label}
    {:done, summary_text}
    {:error, message}

  (The module keeps its original name: Oban stores the worker name on every job
  row, so renaming it would orphan in-flight jobs.)
  """

  use Oban.Worker,
    queue: :ai_agents,
    max_attempts: 1,
    unique: [
      period: :infinity,
      keys: [:professional_id, :client_id],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  import Ecto.Query
  require Logger

  alias Mehungry.AI.Agents.{MealPlanCore, NutritionistMealPlanAgent}
  alias Mehungry.AI.MealPlanGenerator
  alias Mehungry.Repo
  alias Mehungry.Subscriptions

  @feature "nutritionist_meal_plan"

  @tool_labels %{
    "get_client_record" => "Reading client file…",
    "get_assigned_plan" => "Checking the assigned plan…",
    "get_client_summary" => "Reading client profile…",
    "get_recent_meals" => "Checking recent meal history…",
    "get_ratings" => "Reviewing meal ratings…",
    "search_recipes" => "Searching recipe catalog…",
    "search_ingredients" => "Finding whole-food snacks…",
    "list_snack_options" => "Picking seasonal fruit and nuts…",
    "submit_plan" => "Validating the meal plan…"
  }

  @doc "The quota feature key a nutritionist's client drafts are metered under."
  def feature, do: @feature

  @doc """
  Starts a client draft. `params`:

    * `:professional_id`, `:client_id`, `:client_name` — required
    * `:preferences` — the nutritionist's free-text guidance (default `""`)
    * `:start_date` — first day of the plan week (default: this week's Monday)
    * `:mode` — `:fill_gaps` (default) or `:replace_week`

  Returns `{:ok, job}`, `{:error, :quota_exceeded}`, `{:error, :already_running}`,
  `{:error, :week_in_past}`, or `{:error, reason}`.
  """
  def start(%{professional_id: professional_id, client_id: client_id} = params) do
    start_date = Map.get(params, :start_date) || NutritionistMealPlanAgent.default_start_date()
    mode = MealPlanGenerator.parse_mode(Map.get(params, :mode))

    with true <- plannable?(start_date) || {:error, :week_in_past},
         # Usage is recorded only when a draft succeeds, so drafts still in
         # flight count against the limit here — otherwise drafts queued for
         # several clients could all pass the check and overshoot it.
         :ok <-
           Subscriptions.check_quota(professional_id, @feature, in_flight_count(professional_id)) do
      %{
        professional_id: professional_id,
        client_id: client_id,
        client_name: Map.get(params, :client_name) || "",
        preferences: Map.get(params, :preferences) || "",
        start_date: Date.to_iso8601(start_date),
        mode: to_string(mode)
      }
      |> new()
      |> Oban.insert()
      |> case do
        {:ok, %Oban.Job{conflict?: true}} -> {:error, :already_running}
        other -> other
      end
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(8)

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{
            "professional_id" => professional_id,
            "client_id" => client_id,
            "preferences" => preferences,
            "client_name" => client_name
          } = args
      }) do
    start_date = parse_start_date(args["start_date"])
    mode = MealPlanGenerator.parse_mode(args["mode"])
    notify = fn event -> broadcast(professional_id, client_id, event) end

    notify.({:started, client_name})

    on_event = fn
      {:tool_call, name} -> notify.({:step, Map.get(@tool_labels, name, "Working…")})
      {:tool_result, _name, _result} -> :ok
    end

    Logger.info(
      "NutritionistAgentWorker: starting for professional=#{professional_id} client=#{client_id}"
    )

    result =
      try do
        draft(professional_id, client_id, preferences, start_date, mode, on_event)
      rescue
        exception ->
          Logger.error(
            "NutritionistAgentWorker crashed: " <>
              Exception.format(:error, exception, __STACKTRACE__)
          )

          {:error, :crashed}
      catch
        kind, reason ->
          Logger.error(
            "NutritionistAgentWorker crashed: " <>
              Exception.format(kind, reason, __STACKTRACE__)
          )

          {:error, :crashed}
      end

    case result do
      {:ok, summary} ->
        notify.({:done, summary})
        :ok

      {:error, reason} ->
        Logger.warning("NutritionistAgentWorker: draft failed: #{inspect(reason)}")
        notify.({:error, failure_text(reason, professional_id, client_id)})
        {:error, reason}
    end
  end

  # Generate, write to the client's calendar in the chosen mode, then meter the
  # nutritionist — only when the draft produced meals.
  defp draft(professional_id, client_id, preferences, start_date, mode, on_event) do
    opts = [on_event: on_event, start_date: start_date, mode: mode]
    # A client's past days are never planned or deleted — see `plannable?/1`.
    from = NutritionistMealPlanAgent.first_day(start_date)

    with true <- plannable?(start_date) || {:error, :week_in_past},
         {:ok, plan} <-
           NutritionistMealPlanAgent.run(professional_id, client_id, preferences, opts),
         {:ok, created, _skipped} <-
           MealPlanGenerator.persist_entries_to_calendar(
             plan.entries,
             client_id,
             start_date,
             mode,
             from: from
           ) do
      if created == [] do
        {:error, :no_meals_created}
      else
        Subscriptions.record_usage(professional_id, @feature)
        {:ok, summary_text(plan, length(created))}
      end
    end
  end

  @doc """
  Can a draft still be written for the week starting `start_date`? False once the
  whole week is in the past.
  """
  def plannable?(%Date{} = start_date) do
    Date.compare(Date.add(start_date, 6), Date.utc_today()) != :lt
  end

  @doc """
  Meals already on the client's calendar in the part of the week a draft may
  touch (today onward) — what the page checks before asking fill-gaps vs replace.
  """
  def existing_meal_count(client_id, %Date{} = start_date) do
    MealPlanGenerator.existing_meal_count(
      client_id,
      start_date,
      NutritionistMealPlanAgent.first_day(start_date)
    )
  end

  defp summary_text(plan, count) do
    note = if String.trim(plan.rationale) != "", do: plan.rationale, else: plan.summary

    String.trim(
      "#{note}\n\n✓ #{count} meal entries created.#{calorie_note(plan)}#{excluded_note(plan.avoided)}"
    )
  end

  # The band the draft was held to, and — honestly — any day it could not bring
  # inside it (a thin catalogue), so the nutritionist knows where to adjust.
  defp calorie_note(%{calorie_band: %{min: min, max: max}} = plan) do
    range = "\nCalorie range per day: #{min}–#{max} kcal."

    case Map.get(plan, :calorie_warnings, []) do
      [] ->
        range

      warnings ->
        days = Enum.map_join(warnings, ", ", &"#{&1.date} (#{&1.total} kcal)")
        range <> " ⚠ Outside the range, adjust by hand: #{days}."
    end
  end

  defp calorie_note(_plan), do: ""

  # A draft that could not be built from what the avoid list left over should
  # say so: the nutritionist can then fix a loose intake entry.
  defp failure_text(reason, professional_id, client_id)
       when reason in [:no_plan_submitted, :max_iterations_reached] do
    terms =
      try do
        NutritionistMealPlanAgent.enforced_avoid_terms(professional_id, client_id)
      rescue
        _ -> []
      end

    MealPlanCore.error_message(reason) <> excluded_note(terms)
  end

  defp failure_text(reason, _professional_id, _client_id), do: MealPlanCore.error_message(reason)

  defp excluded_note([]), do: ""

  defp excluded_note(terms) do
    shown = terms |> Enum.take(15) |> Enum.join(", ")
    more = if length(terms) > 15, do: " (+#{length(terms) - 15} more)", else: ""
    "\nFoods excluded for this client: #{shown}#{more}."
  end

  defp parse_start_date(iso) when is_binary(iso) do
    case Date.from_iso8601(iso) do
      {:ok, date} -> date
      _ -> NutritionistMealPlanAgent.default_start_date()
    end
  end

  defp parse_start_date(_), do: NutritionistMealPlanAgent.default_start_date()

  @doc "PubSub topic for a given professional."
  def topic(professional_id), do: "nutritionist_agent:#{professional_id}"

  @active_states ~w(available scheduled executing retryable)

  @doc """
  Is a draft still in flight for this professional+client? Lets a LiveView that
  re-mounts mid-run restore its "running" state instead of flashing the idle
  form (PubSub steps resume once the next tool fires).
  """
  def running?(professional_id, client_id) do
    Repo.exists?(
      from j in Oban.Job,
        where: j.worker == "Mehungry.ObanWorkers.NutritionistAgentWorker",
        where: j.state in @active_states,
        where: fragment("?->>'professional_id' = ?", j.args, ^to_string(professional_id)),
        where: fragment("?->>'client_id' = ?", j.args, ^to_string(client_id))
    )
  end

  @doc "How many of this professional's drafts are queued or running, across clients."
  def in_flight_count(professional_id) do
    Repo.aggregate(
      from(j in Oban.Job,
        where: j.worker == "Mehungry.ObanWorkers.NutritionistAgentWorker",
        where: j.state in @active_states,
        where: fragment("?->>'professional_id' = ?", j.args, ^to_string(professional_id))
      ),
      :count
    )
  end

  defp broadcast(professional_id, client_id, event) do
    Phoenix.PubSub.broadcast(
      Mehungry.PubSub,
      topic(professional_id),
      {:nutritionist_agent, client_id, event}
    )
  end
end
