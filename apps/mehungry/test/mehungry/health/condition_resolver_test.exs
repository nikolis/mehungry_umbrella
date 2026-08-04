defmodule Mehungry.Health.ConditionResolverTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.Health
  alias Mehungry.Health.ConditionResolver

  setup do
    {:ok, condition} =
      Health.create_condition(%{name: "Type 2 Diabetes Mellitus", synonyms: ["T2DM"]})

    %{condition: condition}
  end

  test "matches a MeSH-inverted name via token-set equality and writes the identifier",
       %{condition: condition} do
    # "Diabetes Mellitus Type 2" (MeSH preferred term) ≠ our exact name, but has the
    # same token set → matches, and the mesh id is written for identifier-first next time.
    assert {:ok, resolved} =
             ConditionResolver.resolve_normalized("mesh:D003924", "Diabetes Mellitus Type 2")

    assert resolved.id == condition.id
    assert Health.get_condition_by_identifier("mesh", "D003924").id == condition.id
  end

  test "matches an exact synonym", %{condition: condition} do
    assert {:ok, resolved} = ConditionResolver.resolve(%{name: "t2dm"})
    assert resolved.id == condition.id
  end

  test "identifier-first short-circuits the name match", %{condition: condition} do
    {:ok, _} =
      Health.upsert_condition_identifier(%{
        condition_id: condition.id,
        namespace: "mesh",
        identifier: "D003924",
        source: "test"
      })

    assert {:ok, resolved} =
             ConditionResolver.resolve(%{
               namespace: "mesh",
               identifier: "D003924",
               name: "nonsense"
             })

    assert resolved.id == condition.id
  end

  test "a token *subset* does not match (conservative)", %{condition: _c} do
    # "Diabetes Mellitus" ⊂ "Type 2 Diabetes Mellitus" but is ambiguous — left unmatched.
    assert {:error, :not_found} = ConditionResolver.resolve(%{name: "Diabetes Mellitus"})
  end

  test "an unknown disease returns :not_found" do
    assert {:error, :not_found} = ConditionResolver.resolve(%{name: "Totally Unknown Syndrome"})
  end
end
