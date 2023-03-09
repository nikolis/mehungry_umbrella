defmodule Mehungry.TobedelTest do
  use Mehungry.DataCase

  alias Mehungry.Tobedel

  describe "bedels" do
    alias Mehungry.Tobedel.Bedel

    import Mehungry.TobedelFixtures

    @invalid_attrs %{age: nil, url: nil}

    test "list_bedels/0 returns all bedels" do
      bedel = bedel_fixture()
      assert Tobedel.list_bedels() == [bedel]
    end

    test "get_bedel!/1 returns the bedel with given id" do
      bedel = bedel_fixture()
      assert Tobedel.get_bedel!(bedel.id) == bedel
    end

    test "create_bedel/1 with valid data creates a bedel" do
      valid_attrs = %{age: 42, url: "some url"}

      assert {:ok, %Bedel{} = bedel} = Tobedel.create_bedel(valid_attrs)
      assert bedel.age == 42
      assert bedel.url == "some url"
    end

    test "create_bedel/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Tobedel.create_bedel(@invalid_attrs)
    end

    test "update_bedel/2 with valid data updates the bedel" do
      bedel = bedel_fixture()
      update_attrs = %{age: 43, url: "some updated url"}

      assert {:ok, %Bedel{} = bedel} = Tobedel.update_bedel(bedel, update_attrs)
      assert bedel.age == 43
      assert bedel.url == "some updated url"
    end

    test "update_bedel/2 with invalid data returns error changeset" do
      bedel = bedel_fixture()
      assert {:error, %Ecto.Changeset{}} = Tobedel.update_bedel(bedel, @invalid_attrs)
      assert bedel == Tobedel.get_bedel!(bedel.id)
    end

    test "delete_bedel/1 deletes the bedel" do
      bedel = bedel_fixture()
      assert {:ok, %Bedel{}} = Tobedel.delete_bedel(bedel)
      assert_raise Ecto.NoResultsError, fn -> Tobedel.get_bedel!(bedel.id) end
    end

    test "change_bedel/1 returns a bedel changeset" do
      bedel = bedel_fixture()
      assert %Ecto.Changeset{} = Tobedel.change_bedel(bedel)
    end
  end
end
