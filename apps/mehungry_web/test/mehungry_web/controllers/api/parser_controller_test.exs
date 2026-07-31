defmodule MehungryWeb.Api.ParserControllerTest do
  use MehungryWeb.ConnCase

  alias Mehungry.Food.ParserVocabularySeeder

  setup do
    ParserVocabularySeeder.seed()
    :ok
  end

  test "parses a description", %{conn: conn} do
    conn = post(conn, ~p"/api/parser/parse", %{"description" => "Oil, corn"})

    assert %{
             "skipped" => false,
             "canonical_food" => "corn",
             "harvest_stage" => "mature",
             "processing" => ["oil"],
             "packaging" => "na",
             "confidence" => 1.0,
             "trace" => nil
           } = json_response(conn, 200)
  end

  test "returns the meat/fat fields for a cut description", %{conn: conn} do
    conn =
      post(conn, ~p"/api/parser/parse", %{
        "description" => "Beef, ground, 85% lean 15% fat, raw"
      })

    assert %{
             "skipped" => false,
             "canonical_food" => "beef",
             "fat" => "85% lean 15% fat",
             "bone_state" => nil,
             "portion" => [],
             "grade" => nil
           } = json_response(conn, 200)
  end

  test "skips prepared/composite dishes", %{conn: conn} do
    conn = post(conn, ~p"/api/parser/parse", %{"description" => "White bread, commercial"})

    assert %{"skipped" => true, "reason" => "prepared_dish"} = json_response(conn, 200)
  end

  test "returns the skip reason for non-foods", %{conn: conn} do
    conn =
      post(conn, ~p"/api/parser/parse", %{
        "description" => "Alcoholic beverage, daiquiri, canned",
        "trace" => true
      })

    assert %{"skipped" => true, "reason" => "not_food", "trace" => [_ | _]} =
             json_response(conn, 200)
  end

  test "422 without a description", %{conn: conn} do
    conn = post(conn, ~p"/api/parser/parse", %{})
    assert %{"error" => _} = json_response(conn, 422)
  end
end
