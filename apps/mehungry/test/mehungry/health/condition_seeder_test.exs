defmodule Mehungry.Health.ConditionSeederTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.Health
  alias Mehungry.Health.ConditionSeeder

  @fixture Path.join(System.tmp_dir!(), "conds_#{System.unique_integer([:positive])}.json")

  setup do
    # Child listed BEFORE its parent, to prove the second-pass linking is
    # order-independent.
    json =
      Jason.encode!([
        %{
          "main_name" => "Ulcerative Colitis",
          "parent" => "Inflammatory Bowel Disease",
          "category" => "Digestive"
        },
        %{"main_name" => "Inflammatory Bowel Disease", "synonyms" => ["IBD"], "category" => "Digestive"},
        %{"main_name" => "Standalone Thing", "category" => "Other"}
      ])

    File.write!(@fixture, json)
    on_exit(fn -> File.rm(@fixture) end)
    :ok
  end

  test "links a child to its parent by name (order-independent)" do
    assert {:ok, %{inserted: 3}} = ConditionSeeder.seed(@fixture)

    uc = Health.get_condition_by_name("Ulcerative Colitis")
    ibd = Health.get_condition_by_name("Inflammatory Bowel Disease")
    standalone = Health.get_condition_by_name("Standalone Thing")

    assert uc.parent_condition_id == ibd.id
    assert is_nil(ibd.parent_condition_id)
    assert is_nil(standalone.parent_condition_id)
  end

  test "re-seeding is idempotent and re-asserts the parent link" do
    assert {:ok, %{inserted: 3}} = ConditionSeeder.seed(@fixture)
    assert {:ok, %{inserted: 0}} = ConditionSeeder.seed(@fixture)

    uc = Health.get_condition_by_name("Ulcerative Colitis")
    ibd = Health.get_condition_by_name("Inflammatory Bowel Disease")
    assert uc.parent_condition_id == ibd.id
  end
end
