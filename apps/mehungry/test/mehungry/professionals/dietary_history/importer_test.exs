defmodule Mehungry.Professionals.DietaryHistory.ImporterTest do
  use Mehungry.DataCase, async: true

  import Mehungry.AccountsFixtures

  alias Mehungry.Professionals
  alias Mehungry.Professionals.DietaryHistory.Importer

  setup do
    content = File.read!(Path.expand("../../../fixtures/dietary_history_sample.csv", __DIR__))
    %{content: content, professional: user_fixture(), client_user: user_fixture()}
  end

  test "requires a linked platform user — records are never headless", %{
    content: content,
    professional: professional
  } do
    assert {:error, :user_required} = Importer.import_csv(professional.id, content)
    assert {:error, :user_required} = Importer.import_csv(professional.id, content, user_id: "")
  end

  test "imports a client record with intake and notes scoped to the professional", %{
    content: content,
    professional: professional,
    client_user: client_user
  } do
    assert {:ok, %{client: client, notes_count: 15}} =
             Importer.import_csv(professional.id, content, user_id: client_user.id)

    assert client.professional_id == professional.id
    assert client.user_id == client_user.id

    # scoped listing returns the imported record
    assert [listed] = Professionals.list_client_records(professional.id)
    assert listed.id == client.id

    intake = Professionals.get_latest_intake(client.id)
    assert intake.bmi == 32.0
    assert intake.tdee_kcal == 1995
    assert intake.details["recall_24h"]["fruit_intake"] == "καλή"

    notes = Professionals.list_consultation_notes(client.id)
    assert length(notes) == 15
    # ordered chronologically
    assert Enum.map(notes, & &1.visit_date) == Enum.sort(Enum.map(notes, & &1.visit_date), Date)
  end

  test "falls back to the name override when the sheet has no name", %{
    content: content,
    professional: professional,
    client_user: client_user
  } do
    assert {:ok, %{client: client}} =
             Importer.import_csv(professional.id, content,
               user_id: client_user.id,
               full_name: "Maria K."
             )

    assert client.full_name == "Maria K."
  end

  test "records are isolated per professional", %{
    content: content,
    professional: professional,
    client_user: client_user
  } do
    other = user_fixture()
    {:ok, _} = Importer.import_csv(professional.id, content, user_id: client_user.id)

    assert Professionals.list_client_records(other.id) == []
    assert length(Professionals.list_client_records(professional.id)) == 1
  end
end
