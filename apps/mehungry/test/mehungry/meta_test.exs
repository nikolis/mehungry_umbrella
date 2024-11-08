defmodule Mehungry.MetaTest do
  use Mehungry.DataCase

  alias Mehungry.Meta

  describe "visits" do
    alias Mehungry.Meta.Visit

    import Mehungry.MetaFixtures

    @invalid_attrs %{details: nil, ip_address: nil, session_key: nil}

    test "list_visits/0 returns all visits" do
      visit = visit_fixture()
      assert Meta.list_visits() == [visit]
    end

    test "get_visit!/1 returns the visit with given id" do
      visit = visit_fixture()
      assert Meta.get_visit!(visit.id) == visit
    end

    test "create_visit/1 with valid data creates a visit" do
      valid_attrs = %{
        details: %{},
        ip_address: "some ip_address",
        session_key: "some session_key"
      }

      assert {:ok, %Visit{} = visit} = Meta.create_visit(valid_attrs)
      assert visit.details == %{}
      assert visit.ip_address == "some ip_address"
      assert visit.session_key == "some session_key"
    end

    test "create_visit/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Meta.create_visit(@invalid_attrs)
    end

    test "update_visit/2 with valid data updates the visit" do
      visit = visit_fixture()

      update_attrs = %{
        details: %{},
        ip_address: "some updated ip_address",
        session_key: "some updated session_key"
      }

      assert {:ok, %Visit{} = visit} = Meta.update_visit(visit, update_attrs)
      assert visit.details == %{}
      assert visit.ip_address == "some updated ip_address"
      assert visit.session_key == "some updated session_key"
    end

    test "update_visit/2 with invalid data returns error changeset" do
      visit = visit_fixture()
      assert {:error, %Ecto.Changeset{}} = Meta.update_visit(visit, @invalid_attrs)
      assert visit == Meta.get_visit!(visit.id)
    end

    test "delete_visit/1 deletes the visit" do
      visit = visit_fixture()
      assert {:ok, %Visit{}} = Meta.delete_visit(visit)
      assert_raise Ecto.NoResultsError, fn -> Meta.get_visit!(visit.id) end
    end

    test "change_visit/1 returns a visit changeset" do
      visit = visit_fixture()
      assert %Ecto.Changeset{} = Meta.change_visit(visit)
    end
  end
end
