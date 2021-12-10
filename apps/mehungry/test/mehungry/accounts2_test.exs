defmodule Mehungry.Accounts2Test do
  use Mehungry.DataCase

  alias Mehungry.Accounts2

  describe "u2sers" do
    alias Mehungry.Accounts2.U2ser

    import Mehungry.Accounts2Fixtures

    @invalid_attrs %{age: nil, name: nil}

    test "list_u2sers/0 returns all u2sers" do
      u2ser = u2ser_fixture()
      assert Accounts2.list_u2sers() == [u2ser]
    end

    test "get_u2ser!/1 returns the u2ser with given id" do
      u2ser = u2ser_fixture()
      assert Accounts2.get_u2ser!(u2ser.id) == u2ser
    end

    test "create_u2ser/1 with valid data creates a u2ser" do
      valid_attrs = %{age: 42, name: "some name"}

      assert {:ok, %U2ser{} = u2ser} = Accounts2.create_u2ser(valid_attrs)
      assert u2ser.age == 42
      assert u2ser.name == "some name"
    end

    test "create_u2ser/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Accounts2.create_u2ser(@invalid_attrs)
    end

    test "update_u2ser/2 with valid data updates the u2ser" do
      u2ser = u2ser_fixture()
      update_attrs = %{age: 43, name: "some updated name"}

      assert {:ok, %U2ser{} = u2ser} = Accounts2.update_u2ser(u2ser, update_attrs)
      assert u2ser.age == 43
      assert u2ser.name == "some updated name"
    end

    test "update_u2ser/2 with invalid data returns error changeset" do
      u2ser = u2ser_fixture()
      assert {:error, %Ecto.Changeset{}} = Accounts2.update_u2ser(u2ser, @invalid_attrs)
      assert u2ser == Accounts2.get_u2ser!(u2ser.id)
    end

    test "delete_u2ser/1 deletes the u2ser" do
      u2ser = u2ser_fixture()
      assert {:ok, %U2ser{}} = Accounts2.delete_u2ser(u2ser)
      assert_raise Ecto.NoResultsError, fn -> Accounts2.get_u2ser!(u2ser.id) end
    end

    test "change_u2ser/1 returns a u2ser changeset" do
      u2ser = u2ser_fixture()
      assert %Ecto.Changeset{} = Accounts2.change_u2ser(u2ser)
    end
  end
end
