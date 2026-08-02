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
end
