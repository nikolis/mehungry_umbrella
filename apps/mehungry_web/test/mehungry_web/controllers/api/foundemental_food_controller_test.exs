defmodule MehungryWeb.Api.FoundementalFoodControllerTest do
  use MehungryWeb.ConnCase

  alias Mehungry.Food

  @token "test-public-api-token"

  test "401 without a token", %{conn: conn} do
    conn = get(conn, ~p"/api/foundemental_foods")
    assert %{"error" => "unauthorized"} = json_response(conn, 401)
  end

  test "401 with a wrong token", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer nope")
      |> get(~p"/api/foundemental_foods")

    assert %{"error" => "unauthorized"} = json_response(conn, 401)
  end

  test "returns every species with all its fields", %{conn: conn} do
    {:ok, apple} =
      Food.create_foundemental_species(%{
        "name" => "Apple",
        "variety" => "Gala",
        "alternative_name" => "Malus",
        "scientific_name" => "Malus domestica",
        "family" => "Rosaceae"
      })

    {:ok, _kale} = Food.create_foundemental_species(%{"name" => "Kale"})

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@token}")
      |> get(~p"/api/foundemental_foods")

    assert %{"data" => data} = json_response(conn, 200)
    # Name-ordered: Apple before Kale.
    assert ["Apple", "Kale"] = Enum.map(data, & &1["name"])

    assert %{
             "id" => id,
             "name" => "Apple",
             "variety" => "Gala",
             "alternative_name" => "Malus",
             "scientific_name" => "Malus domestica",
             "family" => "Rosaceae",
             "inserted_at" => _,
             "updated_at" => _
           } = hd(data)

    assert id == apple.id
  end
end
