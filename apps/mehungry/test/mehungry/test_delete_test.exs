defmodule Mehungry.TestDeleteTest do
  use Mehungry.DataCase

  alias Mehungry.TestDelete

  describe "deletes" do
    alias Mehungry.TestDelete.DeleteTest

    import Mehungry.TestDeleteFixtures

    @invalid_attrs %{name: nil}

    test "list_deletes/0 returns all deletes" do
      delete_test = delete_test_fixture()
      assert TestDelete.list_deletes() == [delete_test]
    end

    test "get_delete_test!/1 returns the delete_test with given id" do
      delete_test = delete_test_fixture()
      assert TestDelete.get_delete_test!(delete_test.id) == delete_test
    end

    test "create_delete_test/1 with valid data creates a delete_test" do
      valid_attrs = %{name: "some name"}

      assert {:ok, %DeleteTest{} = delete_test} = TestDelete.create_delete_test(valid_attrs)
      assert delete_test.name == "some name"
    end

    test "create_delete_test/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = TestDelete.create_delete_test(@invalid_attrs)
    end

    test "update_delete_test/2 with valid data updates the delete_test" do
      delete_test = delete_test_fixture()
      update_attrs = %{name: "some updated name"}

      assert {:ok, %DeleteTest{} = delete_test} =
               TestDelete.update_delete_test(delete_test, update_attrs)

      assert delete_test.name == "some updated name"
    end

    test "update_delete_test/2 with invalid data returns error changeset" do
      delete_test = delete_test_fixture()

      assert {:error, %Ecto.Changeset{}} =
               TestDelete.update_delete_test(delete_test, @invalid_attrs)

      assert delete_test == TestDelete.get_delete_test!(delete_test.id)
    end

    test "delete_delete_test/1 deletes the delete_test" do
      delete_test = delete_test_fixture()
      assert {:ok, %DeleteTest{}} = TestDelete.delete_delete_test(delete_test)
      assert_raise Ecto.NoResultsError, fn -> TestDelete.get_delete_test!(delete_test.id) end
    end

    test "change_delete_test/1 returns a delete_test changeset" do
      delete_test = delete_test_fixture()
      assert %Ecto.Changeset{} = TestDelete.change_delete_test(delete_test)
    end
  end
end
