defmodule Mehungry.Professionals.DietaryHistory.CsvParserTest do
  use ExUnit.Case, async: true

  alias Mehungry.Professionals.DietaryHistory.CsvParser

  setup_all do
    content = File.read!(Path.expand("../../../fixtures/dietary_history_sample.csv", __DIR__))
    {:ok, parsed} = CsvParser.parse(content)
    %{parsed: parsed}
  end

  describe "parse/1 intake section" do
    test "parses typed anthropometric comma-decimals", %{parsed: parsed} do
      intake = parsed.intake
      assert intake.height_m == 1.75
      assert intake.weight_kg == 98.3
      assert intake.bmi == 32.0
      assert intake.usual_weight_kg == 80.0
      assert intake.ideal_weight_kg == 62.5
      assert intake.adjusted_weight_kg == 69.38
    end

    test "parses integer energy figures", %{parsed: parsed} do
      assert parsed.intake.bmr_kcal == 1662
      assert parsed.intake.tdee_kcal == 1995
    end

    test "parses the Greek assessment date", %{parsed: parsed} do
      assert parsed.intake.assessed_on == ~D[2025-09-15]
    end

    test "routes free-text questionnaire fields into details", %{parsed: parsed} do
      details = parsed.intake.details
      assert details["reason_for_visit"] == "χάσιμο βάρους"
      assert details["allergies"] == "στην υγρασία"
      assert String.contains?(details["notes"], "Δεν έχει στάνταρ ώρες φαγητού")
    end

    test "nests the 24-hour recall under recall_24h", %{parsed: parsed} do
      recall = parsed.intake.details["recall_24h"]
      assert recall["fruit_intake"] == "καλή"
      assert String.contains?(recall["breakfast"], "brunch")
    end

    test "keeps the typed goal", %{parsed: parsed} do
      assert String.contains?(parsed.intake.goal, "89 κιλά")
    end
  end

  describe "parse/1 consultation notes" do
    test "splits into one intake + 15 notes", %{parsed: parsed} do
      assert length(parsed.consultation_notes) == 15
    end

    test "preserves real-world visit numbering (skips 3, repeats 6)", %{parsed: parsed} do
      numbers = Enum.map(parsed.consultation_notes, & &1.visit_number)
      assert numbers == [2, 4, 5, 6, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
    end

    test "detects modality from the header's third cell", %{parsed: parsed} do
      by_number = Map.new(parsed.consultation_notes, &{&1.visit_number, &1})
      # duplicate 6 collapses in the map, fine — assert distinct numbers
      assert by_number[7].modality == "phone"
      assert by_number[8].modality == "online"
      assert by_number[2].modality == "in_person"
    end

    test "preserves multi-line body text", %{parsed: parsed} do
      note = Enum.find(parsed.consultation_notes, &(&1.visit_number == 2))
      assert String.contains?(note.body, "Απώλεια 800γρ")
      assert String.contains?(note.body, "\n")
    end

    test "captures to-do rows", %{parsed: parsed} do
      note = Enum.find(parsed.consultation_notes, &(&1.visit_number == 2))
      assert String.contains?(note.todo, "Ραντεβού")
    end

    test "parses Greek visit dates", %{parsed: parsed} do
      note = Enum.find(parsed.consultation_notes, &(&1.visit_number == 8))
      assert note.visit_date == ~D[2026-01-05]
    end
  end

  describe "parse/1 edge cases" do
    test "returns error when there are no appointment blocks" do
      assert {:error, :no_appointments} = CsvParser.parse("just,some,header\nrandom,text,here")
    end
  end
end
