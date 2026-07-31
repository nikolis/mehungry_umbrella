defmodule Mehungry.Food.FoodParsingRunsTest do
  use Mehungry.DataCase

  alias Mehungry.Food.FoodParsingRuns
  alias Mehungry.Food.IngredientFoodParsingRun, as: Run

  setup do
    Phoenix.PubSub.subscribe(Mehungry.PubSub, FoodParsingRuns.topic())
    :ok
  end

  test "start_run opens a pending run seeded with the coverage snapshot and broadcasts" do
    run = FoodParsingRuns.start_run()

    assert %Run{status: "pending", started_at: %DateTime{}} = run
    assert is_integer(run.processed) and is_integer(run.total)
    assert_receive {:food_parsing_run, %Run{status: "pending"}}
  end

  test "lifecycle transitions broadcast every change" do
    run = FoodParsingRuns.start_run()
    assert_receive {:food_parsing_run, _}

    FoodParsingRuns.mark_processing(run.id)
    assert_receive {:food_parsing_run, %Run{status: "processing"}}

    FoodParsingRuns.update_progress(run.id, %{processed: 3, total: 4})
    assert_receive {:food_parsing_run, %Run{processed: 3, total: 4}}

    FoodParsingRuns.mark_completed(run.id, %{processed: 4, total: 4})
    assert_receive {:food_parsing_run, %Run{status: "completed", completed_at: %DateTime{}}}
  end

  test "mark_failed records the error" do
    run = FoodParsingRuns.start_run()
    FoodParsingRuns.mark_failed(run.id, :boom)

    assert_receive {:food_parsing_run, %Run{status: "pending"}}
    assert_receive {:food_parsing_run, %Run{status: "failed", error: ":boom"}}
    assert FoodParsingRuns.latest_run().status == "failed"
  end

  test "updates tolerate a missing run row" do
    assert FoodParsingRuns.mark_processing(123_456_789) == nil
    assert FoodParsingRuns.mark_processing(nil) == nil
  end
end
