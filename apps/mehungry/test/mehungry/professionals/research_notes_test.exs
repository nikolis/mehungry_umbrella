defmodule Mehungry.Professionals.ResearchNotesTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.Literature
  alias Mehungry.Professionals.ResearchNotes

  setup do
    user = Mehungry.AccountsFixtures.user_fixture()
    {:ok, condition} = Mehungry.Health.create_condition(%{name: "Gout"})
    {:ok, study} = Literature.upsert_study(%{pmid: 77_001, title: "Cherries and urate"})
    %{user: user, condition: condition, study: study}
  end

  defp suggested_attrs(condition, study) do
    %{
      condition_id: condition.id,
      study_id: study.id,
      claim_id: "c1",
      body: "Cherries — lower — Urate (positive)",
      section_id: "sec-a",
      paragraph_id: "par-a",
      quoted_text: "cherry intake lowered urate"
    }
  end

  test "save_suggested persists a note and is idempotent", %{
    user: user,
    condition: condition,
    study: study
  } do
    attrs = suggested_attrs(condition, study)

    assert {:ok, note} = ResearchNotes.save_suggested(user.id, attrs)
    assert note.kind == "suggested"
    assert note.user_id == user.id
    assert note.paragraph_id == "par-a"
    assert note.quoted_text == "cherry intake lowered urate"

    # Re-saving the same claim returns the existing row (no duplicate, no error).
    assert {:ok, same} = ResearchNotes.save_suggested(user.id, attrs)
    assert same.id == note.id
    assert [_only] = ResearchNotes.list_for_user(user.id)
  end

  test "saved_claim_keys reflects saved suggestions as {study_id, claim_id}", %{
    user: user,
    condition: condition,
    study: study
  } do
    assert ResearchNotes.saved_claim_keys(user.id, condition.id) == MapSet.new()

    {:ok, _} = ResearchNotes.save_suggested(user.id, suggested_attrs(condition, study))

    keys = ResearchNotes.saved_claim_keys(user.id, condition.id)
    assert MapSet.member?(keys, {study.id, "c1"})
  end

  test "delete_suggested removes it and clears the saved key", %{
    user: user,
    condition: condition,
    study: study
  } do
    {:ok, _} = ResearchNotes.save_suggested(user.id, suggested_attrs(condition, study))

    assert {:ok, 1} = ResearchNotes.delete_suggested(user.id, study.id, "c1")
    assert ResearchNotes.saved_claim_keys(user.id, condition.id) == MapSet.new()
    assert ResearchNotes.list_for_user(user.id) == []
  end

  test "create_custom stores a free-text note without a claim", %{
    user: user,
    condition: condition,
    study: study
  } do
    assert {:ok, note} =
             ResearchNotes.create_custom(user.id, %{
               condition_id: condition.id,
               study_id: study.id,
               body: "Ask client about cherry supplements."
             })

    assert note.kind == "custom"
    assert is_nil(note.claim_id)
    assert note.body =~ "cherry supplements"
  end

  test "notes are private per user", %{user: user, condition: condition, study: study} do
    other = Mehungry.AccountsFixtures.user_fixture()
    {:ok, _} = ResearchNotes.save_suggested(user.id, suggested_attrs(condition, study))

    assert ResearchNotes.list_for_user(other.id) == []
    assert ResearchNotes.saved_claim_keys(other.id, condition.id) == MapSet.new()
  end

  test "delete_note is ownership-scoped", %{user: user, condition: condition, study: study} do
    other = Mehungry.AccountsFixtures.user_fixture()
    {:ok, note} = ResearchNotes.save_suggested(user.id, suggested_attrs(condition, study))

    # Another user can't delete it.
    assert {:ok, 0} = ResearchNotes.delete_note(other.id, note.id)
    assert [_still_there] = ResearchNotes.list_for_user(user.id)

    assert {:ok, 1} = ResearchNotes.delete_note(user.id, note.id)
    assert ResearchNotes.list_for_user(user.id) == []
  end
end
