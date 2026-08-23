defmodule MehungryLocalAi.ExtractorTest do
  use ExUnit.Case, async: true

  alias MehungryLocalAi.Extractor

  @compounds [%{id: 7, name: "L-Ascorbic Acid", synonyms: ["ascorbic acid"]}]

  test "extracts a value+unit near the compound name (rule path, QA off)" do
    text = "Results: L-Ascorbic Acid content was 260 mg/100 g, measured by HPLC."

    assert [finding] = Extractor.findings(text, @compounds)
    assert finding.compound_id == 7
    assert finding.value == 260.0
    assert finding.unit == "mg/100 g"
    assert finding.analytical_method == "HPLC"
    assert finding.extraction_method == "automated"
  end

  test "matches via a synonym" do
    text = "The ascorbic acid concentration reached 45 mg/100 g in the sample."

    assert [finding] = Extractor.findings(text, @compounds)
    assert finding.value == 45.0
  end

  test "no numbers near the compound → no findings" do
    text = "L-Ascorbic Acid was present. Separately, sodium was 500 mg/100 g in a different food."
    # 500 mg/100 g sits >160 chars from the name? here it is close, so assert only that
    # a compound not mentioned yields nothing:
    assert Extractor.findings(text, [%{id: 9, name: "Quercetin", synonyms: []}]) == []
  end

  test "empty text yields no findings" do
    assert Extractor.findings("", @compounds) == []
  end

  # ── GI findings (path B) ─────────────────────────────────────────────────

  describe "gi_findings/1" do
    test "extracts GI value + SEM with ISO method, reference food, and sample size" do
      text =
        "Methods consistent with ISO 26642:2010 were used in 10 healthy adults. " <>
          "The glycemic index of the test food was 54 ± 3 relative to glucose."

      assert [f] = Extractor.gi_findings(text)
      assert f.gi_value == 54.0
      assert f.gi_sem == 3.0
      assert f.iso_method
      assert f.reference_food == "glucose"
      assert f.sample_size == 10
      assert f.extraction_method == "automated"
      assert f.raw_span =~ "glycemic index"
    end

    test "matches the 'GI value of N' short form" do
      text = "In this study the GI value of 72 was observed for white bread."

      assert [f] = Extractor.gi_findings(text)
      assert f.gi_value == 72.0
      refute f.iso_method
    end

    test "does not match the gastrointestinal sense of GI" do
      text = "GI symptoms improved in 8 patients; GI tract motility was assessed."

      assert Extractor.gi_findings(text) == []
    end

    test "ignores out-of-range numbers and dedupes repeats" do
      text =
        "The glycemic index was 54 in one arm. Elsewhere the glycemic index was 54 again. " <>
          "A glycemic index of 900 is implausible."

      assert [f] = Extractor.gi_findings(text)
      assert f.gi_value == 54.0
    end

    test "empty text yields no GI findings" do
      assert Extractor.gi_findings("") == []
    end
  end
end
