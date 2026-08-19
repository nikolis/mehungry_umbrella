defmodule Mehungry.AI.AgentTest do
  use ExUnit.Case, async: false

  alias Mehungry.AI.Agent

  # Stubs Mehungry.AI.Client. Each test process registers a queue of canned
  # responses under a key in the process dictionary of an Agent that responds
  # from an ETS-free Agent GenServer... simplest: use an Agent process holding
  # the script, referenced via the test pid in the application env.
  defmodule StubClient do
    # Returns the next scripted response and, for tool_use turns, records the
    # request messages so the test can inspect what the loop sent back.
    def request(_params) do
      case :persistent_term.get({__MODULE__, :script}) do
        [next | rest] ->
          :persistent_term.put({__MODULE__, :script}, rest)
          {:ok, next}

        [] ->
          {:ok, %{stop_reason: "end_turn", content: [%{"type" => "text", "text" => "done"}]}}
      end
    end
  end

  setup do
    Application.put_env(:mehungry, :ai_client, StubClient)
    on_exit(fn -> Application.delete_env(:mehungry, :ai_client) end)
    :ok
  end

  defp script(responses), do: :persistent_term.put({StubClient, :script}, responses)

  defp tool_use(id, name, input) do
    %{
      stop_reason: "tool_use",
      content: [%{"type" => "tool_use", "id" => id, "name" => name, "input" => input}]
    }
  end

  defp end_turn(text) do
    %{stop_reason: "end_turn", content: [%{"type" => "text", "text" => text}]}
  end

  test "threads the accumulator through tool calls and returns it" do
    script([
      tool_use("t1", "remember", %{"n" => 1}),
      tool_use("t2", "remember", %{"n" => 2}),
      end_turn("finished")
    ])

    handler = fn "remember", %{"n" => n}, acc ->
      {%{ok: n}, %{acc | seen: [n | acc.seen]}}
    end

    assert {:ok, "finished", %{seen: [2, 1]}} =
             Agent.run("sys", "go", [], handler, %{seen: []}, telemetry_metadata: %{agent: "test"})
  end

  test "a raising tool handler is caught, preserves acc, and reports error status" do
    ref = attach([:mehungry, :ai, :agent, :tool, :stop])
    script([tool_use("t1", "boom", %{}), end_turn("ok")])

    handler = fn "boom", _input, _acc -> raise "kaboom" end

    assert {:ok, "ok", %{seen: []}} = Agent.run("sys", "go", [], handler, %{seen: []})
    assert_receive {^ref, _measurements, %{tool: "boom", status: "error"}}
  end

  test "emits run start/stop with iterations and end_turn outcome" do
    start_ref = attach([:mehungry, :ai, :agent, :run, :start])
    stop_ref = attach([:mehungry, :ai, :agent, :run, :stop])

    script([tool_use("t1", "noop", %{}), end_turn("ok")])
    handler = fn _n, _i, acc -> {%{}, acc} end

    assert {:ok, "ok", _} =
             Agent.run("sys", "go", [], handler, %{}, telemetry_metadata: %{agent: "recipe"})

    assert_receive {^start_ref, _m, %{agent: "recipe"}}
    assert_receive {^stop_ref, %{iterations: 1}, %{agent: "recipe", outcome: "end_turn"}}
  end

  test "reports max_iterations outcome when the loop never ends the turn" do
    stop_ref = attach([:mehungry, :ai, :agent, :run, :stop])
    # Always returns tool_use, so the loop hits the ceiling.
    script(List.duplicate(tool_use("t", "noop", %{}), 10))
    handler = fn _n, _i, acc -> {%{}, acc} end

    assert {:error, :max_iterations_reached} =
             Agent.run("sys", "go", [], handler, %{}, max_iterations: 3)

    assert_receive {^stop_ref, %{iterations: 3}, %{outcome: "max_iterations"}}
  end

  # Forwards a telemetry event to the test process; returns the correlation ref.
  defp attach(event) do
    ref = make_ref()
    test_pid = self()

    :telemetry.attach(
      "test-#{inspect(ref)}",
      event,
      fn _e, measurements, metadata, _cfg ->
        send(test_pid, {ref, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach("test-#{inspect(ref)}") end)
    ref
  end
end
