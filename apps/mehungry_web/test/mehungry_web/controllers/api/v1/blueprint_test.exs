defmodule MehungryWeb.Api.V1.BlueprintTest do
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.MealBlueprints

  defp public_blueprint_fixture(name) do
    user = Mehungry.AccountsFixtures.user_fixture()

    attrs =
      MealBlueprints.default_blueprint_attrs(user.id, name)
      |> Map.put(:visibility, "public")
      |> Map.put(:preferred_foods, ["spinach"])

    {:ok, blueprint} = MealBlueprints.create_blueprint(attrs)
    %{blueprint: blueprint, user: user}
  end

  describe "GET /api/v1/blueprints" do
    test "lists public blueprints with meta.total", %{conn: conn} do
      public_blueprint_fixture("Mediterranean #{System.unique_integer([:positive])}")

      conn = get(conn, ~p"/api/v1/blueprints")

      assert %{"data" => data, "meta" => %{"total" => total}} = json_response(conn, 200)
      assert is_list(data)
      assert total >= 1
      assert Enum.all?(data, &Map.has_key?(&1, "slug"))
    end

    test "filters by ?q= name search", %{conn: conn} do
      uniq = System.unique_integer([:positive])
      %{blueprint: match} = public_blueprint_fixture("Keto#{uniq}")
      public_blueprint_fixture("Vegan#{uniq}")

      conn = get(conn, ~p"/api/v1/blueprints?q=Keto#{uniq}")

      assert %{"data" => data} = json_response(conn, 200)
      assert [%{"slug" => slug}] = data
      assert slug == match.slug
    end

    test "marks saved blueprints for an authenticated caller", %{conn: conn} do
      %{blueprint: blueprint} = public_blueprint_fixture("Saved #{System.unique_integer([:positive])}")
      %{conn: conn, user: user} = register_and_log_in_api_user(%{conn: conn})
      MealBlueprints.save_blueprint_for_user(user.id, blueprint.id)

      conn = get(conn, ~p"/api/v1/blueprints")
      assert %{"data" => data} = json_response(conn, 200)
      row = Enum.find(data, &(&1["slug"] == blueprint.slug))
      assert row["saved"] == true
    end
  end

  describe "GET /api/v1/blueprints/:slug" do
    test "returns detail with the targets tree", %{conn: conn} do
      %{blueprint: blueprint} = public_blueprint_fixture("Detail #{System.unique_integer([:positive])}")

      conn = get(conn, ~p"/api/v1/blueprints/#{blueprint.slug}")

      assert %{"data" => detail} = json_response(conn, 200)
      assert detail["slug"] == blueprint.slug
      assert detail["preferred_foods"] == ["spinach"]
      assert length(detail["days"]) == 7
      assert Map.has_key?(detail, "owner")
    end

    test "404 for unknown slug", %{conn: conn} do
      assert conn |> get(~p"/api/v1/blueprints/no-such-blueprint-xyz") |> json_response(404)
    end

    test "404 for a private blueprint", %{conn: conn} do
      user = Mehungry.AccountsFixtures.user_fixture()

      {:ok, private} =
        MealBlueprints.create_blueprint(
          MealBlueprints.default_blueprint_attrs(user.id, "Private #{System.unique_integer([:positive])}")
        )

      assert conn |> get(~p"/api/v1/blueprints/#{private.slug}") |> json_response(404)
    end
  end
end
