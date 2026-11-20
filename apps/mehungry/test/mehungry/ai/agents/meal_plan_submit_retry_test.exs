defmodule Mehungry.AI.Agents.MealPlanSubmitRetryTest do
  # Pure: drives MealPlanCore.run_until_submitted/2 with scripted pass results,
  # no Anthropic client or database.
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Mehungry.AI.Agents.MealPlanCore

  @plan %{entries: [%{day_index: 1}], rationale: ""}

  # A run_fun that returns the scripted results in order and records the extra
  # instruction it was handed on each pass.
  defp scripted(results) do
    {:ok, script} = Elixir.Agent.start_link(fn -> {results, []} end)

    run_fun = fn extra ->
      Elixir.Agent.get_and_update(script, fn {[next | rest], extras} ->
        {next, {rest, [extra | extras]}}
      end)
    end

    extras = fn -> script |> Elixir.Agent.get(&elem(&1, 1)) |> Enum.reverse() end
    {run_fun, extras}
  end

  test "a first pass that submits is returned as-is, with no retry" do
    {run_fun, extras} = scripted([{:ok, "done", %{submitted: @plan}}])

    assert {:ok, "done", %{submitted: @plan}} =
             MealPlanCore.run_until_submitted("user_meal_plan", run_fun)

    assert extras.() == [""]
  end

  test "a prose-only first pass is logged and retried once with a firmer instruction" do
    ref = attach_retry()

    {run_fun, extras} =
      scripted([
        {:ok, "Which days would you like me to plan?", %{submitted: nil}},
        {:ok, "done", %{submitted: @plan}}
      ])

    log =
      capture_log(fn ->
        assert {:ok, "done", %{submitted: @plan}} =
                 MealPlanCore.run_until_submitted("user_meal_plan", run_fun)
      end)

    assert log =~ "Which days would you like me to plan?"
    assert [first, second] = extras.()
    assert first == ""
    assert second =~ "submit_plan"
    assert_receive {^ref, %{count: 1}, %{agent: "user_meal_plan"}}
  end

  test "two prose-only passes fail with :no_plan_submitted" do
    {run_fun, _} =
      scripted([
        {:ok, "first answer", %{submitted: nil}},
        {:ok, "second answer", %{submitted: nil}}
      ])

    log =
      capture_log(fn ->
        assert {:error, :no_plan_submitted} =
                 MealPlanCore.run_until_submitted("user_meal_plan", run_fun)
      end)

    assert log =~ "second answer"
  end

  test "an agent error is not retried" do
    {run_fun, extras} = scripted([{:error, :max_iterations_reached}])

    assert {:error, :max_iterations_reached} =
             MealPlanCore.run_until_submitted("user_meal_plan", run_fun)

    assert extras.() == [""]
  end

  defp attach_retry do
    ref = make_ref()
    test_pid = self()
    id = "retry-#{inspect(ref)}"

    :telemetry.attach(
      id,
      [:mehungry, :ai, :agent, :no_submit_retry],
      fn _e, m, meta, _ -> send(test_pid, {ref, m, meta}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
    ref
  end
end
