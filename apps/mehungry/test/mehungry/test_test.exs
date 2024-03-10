"""
defmodule Mehungry.TestTest do
  use Mehungry.DataCase

  alias Mehungry.Test

  describe "testingers" do
    alias Mehungry.Test.Testinger

    import Mehungry.TestFixtures

    @invalid_attrs %{}

    test "list_testingers/0 returns all testingers" do
      testinger = testinger_fixture()
      assert Test.list_testingers() == [testinger]
    end

    test "get_testinger!/1 returns the testinger with given id" do
      testinger = testinger_fixture()
      assert Test.get_testinger!(testinger.id) == testinger
    end

    test "create_testinger/1 with valid data creates a testinger" do
      valid_attrs = %{}

      assert {:ok, %Testinger{} = testinger} = Test.create_testinger(valid_attrs)
    end

    test "create_testinger/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Test.create_testinger(@invalid_attrs)
    end

    test "update_testinger/2 with valid data updates the testinger" do
      testinger = testinger_fixture()
      update_attrs = %{}

      assert {:ok, %Testinger{} = testinger} = Test.update_testinger(testinger, update_attrs)
    end

    test "update_testinger/2 with invalid data returns error changeset" do
      testinger = testinger_fixture()
      assert {:error, %Ecto.Changeset{}} = Test.update_testinger(testinger, @invalid_attrs)
      assert testinger == Test.get_testinger!(testinger.id)
    end

    test "delete_testinger/1 deletes the testinger" do
      testinger = testinger_fixture()
      assert {:ok, %Testinger{}} = Test.delete_testinger(testinger)
      assert_raise Ecto.NoResultsError, fn -> Test.get_testinger!(testinger.id) end
    end

    test "change_testinger/1 returns a testinger changeset" do
      testinger = testinger_fixture()
      assert %Ecto.Changeset{} = Test.change_testinger(testinger)
    end
  end

  describe "testingers" do
    alias Mehungry.Test.Testinger

    import Mehungry.TestFixtures

    @invalid_attrs %{name: nil}

    test "list_testingers/0 returns all testingers" do
      testinger = testinger_fixture()
      assert Test.list_testingers() == [testinger]
    end

    test "get_testinger!/1 returns the testinger with given id" do
      testinger = testinger_fixture()
      assert Test.get_testinger!(testinger.id) == testinger
    end

    test "create_testinger/1 with valid data creates a testinger" do
      valid_attrs = %{name: "some name"}

      assert {:ok, %Testinger{} = testinger} = Test.create_testinger(valid_attrs)
      assert testinger.name == "some name"
    end

    test "create_testinger/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Test.create_testinger(@invalid_attrs)
    end

    test "update_testinger/2 with valid data updates the testinger" do
      testinger = testinger_fixture()
      update_attrs = %{name: "some updated name"}

      assert {:ok, %Testinger{} = testinger} = Test.update_testinger(testinger, update_attrs)
      assert testinger.name == "some updated name"
    end

    test "update_testinger/2 with invalid data returns error changeset" do
      testinger = testinger_fixture()
      assert {:error, %Ecto.Changeset{}} = Test.update_testinger(testinger, @invalid_attrs)
      assert testinger == Test.get_testinger!(testinger.id)
    end

    test "delete_testinger/1 deletes the testinger" do
      testinger = testinger_fixture()
      assert {:ok, %Testinger{}} = Test.delete_testinger(testinger)
      assert_raise Ecto.NoResultsError, fn -> Test.get_testinger!(testinger.id) end
    end

    test "change_testinger/1 returns a testinger changeset" do
      testinger = testinger_fixture()
      assert %Ecto.Changeset{} = Test.change_testinger(testinger)
    end
  end
end
"""
