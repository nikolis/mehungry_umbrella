defmodule Mehungry.Professionals.DietaryHistory.FieldsTest do
  use ExUnit.Case, async: true

  alias Mehungry.Professionals.DietaryHistory.Fields

  test "every questionnaire key is assigned to exactly one lifecycle group" do
    all_keys = Fields.detail_labels() |> Enum.map(&elem(&1, 0)) |> Enum.sort()

    grouped_keys =
      Fields.detail_groups() |> Keyword.values() |> List.flatten() |> Enum.sort()

    assert grouped_keys == Enum.uniq(grouped_keys),
           "a questionnaire key appears in more than one group"

    assert grouped_keys == all_keys,
           "detail_groups/0 must cover exactly the detail_labels/0 keys — " <>
             "when adding a questionnaire field, assign it to a group"
  end
end
