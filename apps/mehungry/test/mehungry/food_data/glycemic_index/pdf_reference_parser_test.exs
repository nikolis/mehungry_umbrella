defmodule Mehungry.FoodData.GlycemicIndex.PdfReferenceParserTest do
  use ExUnit.Case, async: true

  alias Mehungry.FoodData.GlycemicIndex.PdfReferenceParser

  # A representative slice of `pdftotext -layout` output: a preamble page (no value
  # rows), a form-feed page break, then a data page with a category heading, a
  # subcategory, a name-above entry (with right-column cell wrap "Venous,"), an inline
  # entry, and an unpublished (UO) entry. The food-item column is wide and the data
  # columns sit far right, matching the real A4 layout; cells are 2+-space separated.
  @layout """
  Online Supplemental Material - Atkinson FS, Brand-Miller JC. International tables.
  TABLE OF CONTENTS FOR SUPPLEMENTAL TABLE 1
  BAKERY PRODUCTS: pages 2- 6
  \fSupplemental Table 1. Glycemic index (GI) values determined using ISO 26642:2010.
   Food Number and Item                                                       food          SEM      GL
            BAKERY PRODUCTS
            Average available carbohydrate portion = 30 g, used for the nominal GL.
            Cakes
            Cake, NS, decreased GI variant                                              Venous,
     1                                                                       Belgium       2010*     20±4     6    Normal, 10    25    54.4    Glucose, 2h    Standard    Enzymatic    1
            (Bakery School, Herk-de-Stad, Belgium)

     2      Carrot cake, coconut flour                                       Philippines   2002      37±2     11   Normal, 10    50    NS    Bread, 2h    Standard    Enzymatic    2

     3      Chocolate mudcake                                                Australia     2009      43±4     13   Normal, 9     50    109.4    Glucose, 2h    Standard    Enzymatic    UO5
  Atkinson FS, Brand-Miller JC. International tables of glycemic index 2021.
  """

  test "parses value rows with structured fields, skipping preamble/furniture" do
    rows = PdfReferenceParser.parse_text(@layout, "table1")

    assert length(rows) == 3
    assert Enum.map(rows, & &1.food_number) == ["1", "2", "3"]
    assert Enum.all?(rows, &(&1.category == "BAKERY PRODUCTS"))
    assert Enum.all?(rows, &(&1.source_table == "table1"))
  end

  test "recovers a wrapped name from the line above the value row" do
    [row1 | _] = PdfReferenceParser.parse_text(@layout, "table1")

    assert row1.food_item =~ "Cake, NS, decreased GI variant"
    # page furniture / headings / the carbohydrate-portion note never leak into a name
    refute row1.food_item =~ "Supplemental Table"
    refute row1.food_item =~ "available carbohydrate"
    refute row1.food_item =~ "BAKERY PRODUCTS"
    assert row1.gi_value == 20.0
    assert row1.gi_sem == 4.0
    assert row1.country == "Belgium"
    assert row1.year == 2010
    assert row1.ref_code == "1"
    refute row1.unpublished
  end

  test "reads an inline name off the value row" do
    [_, row2, _] = PdfReferenceParser.parse_text(@layout, "table1")

    assert row2.food_item == "Carrot cake, coconut flour"
    assert row2.gi_value == 37.0
    assert row2.country == "Philippines"
  end

  test "flags unpublished-observation rows via the UO ref code" do
    [_, _, row3] = PdfReferenceParser.parse_text(@layout, "table1")

    assert row3.ref_code == "UO5"
    assert row3.unpublished
    assert row3.food_item == "Chocolate mudcake"
  end
end
