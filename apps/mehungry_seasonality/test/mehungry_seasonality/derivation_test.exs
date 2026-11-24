defmodule MehungrySeasonality.DerivationTest do
  use ExUnit.Case, async: true

  alias MehungrySeasonality.Derivation

  defp local(quoted_by_month) do
    Map.new(1..12, fn month ->
      {month, %{weeks_quoted: Map.get(quoted_by_month, month, 0), weeks_possible: 4}}
    end)
  end

  defp imports(tonnes_by_month) do
    Map.new(1..12, fn month ->
      {month,
       %{
         tonnes_avg: Map.get(tonnes_by_month, month, 0.0),
         origins: [%{"country" => "TR", "share" => 0.8}]
       }}
    end)
  end

  defp by_month(derived, key), do: Map.new(derived, &{&1.month, Map.fetch!(&1, key)})

  test "unmapped sources read unknown" do
    derived = Derivation.derive(nil, nil)

    assert length(derived) == 12
    assert Enum.all?(derived, &(&1.local == "unknown" and &1.imported == "unknown"))
  end

  test "a month is in season when quoted in at least half its weeks" do
    local = by_month(Derivation.derive(local(%{6 => 4, 7 => 2, 8 => 1}), nil), :local)

    assert local[6] == "in_season"
    assert local[7] == "in_season"
    assert local[8] == "none"
    assert local[1] == "none"
  end

  test "a product on the market all year is unresolved, not in season" do
    all_year = Map.new(1..12, &{&1, 4})
    local = by_month(Derivation.derive(local(all_year), nil), :local)

    assert local |> Map.values() |> Enum.uniq() == ["unresolved"]
  end

  test "a mapped local source with no quotes at all reads none" do
    local = by_month(Derivation.derive(%{}, nil), :local)
    assert local |> Map.values() |> Enum.uniq() == ["none"]
  end

  test "imports are graded against the product's own peak month" do
    derived = Derivation.derive(nil, imports(%{9 => 8000.0, 8 => 5000.0, 3 => 300.0, 1 => 4.0}))
    imported = by_month(derived, :imported)
    origins = by_month(derived, :top_origins)

    assert imported[9] == "major"
    assert imported[8] == "major"
    assert imported[3] == "some"
    assert imported[1] == "none"
    assert imported[2] == "none"

    assert origins[9] == [%{"country" => "TR", "share" => 0.8}]
    assert origins[1] == []
  end

  test "local and imported are independent in the same month" do
    [july] =
      Derivation.derive(local(%{7 => 4}), imports(%{7 => 5000.0}))
      |> Enum.filter(&(&1.month == 7))

    assert july.local == "in_season"
    assert july.imported == "major"
  end
end
