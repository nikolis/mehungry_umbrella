defmodule MehungryWeb.Api.V1.FoodHealthTest do
  use MehungryWeb.ConnCase, async: true

  defp species_fixture(name) do
    {:ok, species} =
      Mehungry.Food.FoundementalFoods.create_species(%{
        name: name,
        scientific_name: "Testus #{name}",
        family: "Testaceae"
      })

    species
  end

  describe "species" do
    test "GET /api/v1/species lists species with meta.total", %{conn: conn} do
      species_fixture("Spinach #{System.unique_integer([:positive])}")
      conn = get(conn, ~p"/api/v1/species")

      assert %{"data" => data, "meta" => %{"total" => total}} = json_response(conn, 200)
      assert is_list(data)
      assert total >= 1
    end

    test "GET /api/v1/species/:slug returns detail", %{conn: conn} do
      name = "Kaleuniq#{System.unique_integer([:positive])}"
      species_fixture(name)
      slug = String.downcase(name)

      conn = get(conn, ~p"/api/v1/species/#{slug}")
      assert %{"data" => detail} = json_response(conn, 200)
      assert detail["name"] == name
      assert Map.has_key?(detail, "compounds")
      assert Map.has_key?(detail, "ingredients")
      refute Map.has_key?(detail, "related_conditions")
    end

    test "GET /api/v1/species/:slug 404 for unknown", %{conn: conn} do
      assert conn |> get(~p"/api/v1/species/no-such-species-xyz") |> json_response(404)
    end
  end

  describe "search" do
    test "GET /api/v1/search returns an envelope", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/search?q=nothing-matches-xyz")
      assert %{"data" => data} = json_response(conn, 200)
      assert is_list(data)
    end
  end
end
