defmodule Mehungry.NewsLetterTest do
  use Mehungry.DataCase

  alias Mehungry.NewsLetter

  describe "nusers" do
    alias Mehungry.NewsLetter.Nuser

    import Mehungry.NewsLetterFixtures

    @invalid_attrs %{email: nil}

    test "list_nusers/0 returns all nusers" do
      nuser = nuser_fixture()
      assert NewsLetter.list_nusers() == [nuser]
    end

    test "get_nuser!/1 returns the nuser with given id" do
      nuser = nuser_fixture()
      assert NewsLetter.get_nuser!(nuser.id) == nuser
    end

    test "create_nuser/1 with valid data creates a nuser" do
      valid_attrs = %{email: "some email"}

      assert {:ok, %Nuser{} = nuser} = NewsLetter.create_nuser(valid_attrs)
      assert nuser.email == "some email"
    end

    test "create_nuser/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = NewsLetter.create_nuser(@invalid_attrs)
    end

    test "update_nuser/2 with valid data updates the nuser" do
      nuser = nuser_fixture()
      update_attrs = %{email: "some updated email"}

      assert {:ok, %Nuser{} = nuser} = NewsLetter.update_nuser(nuser, update_attrs)
      assert nuser.email == "some updated email"
    end

    test "update_nuser/2 with invalid data returns error changeset" do
      nuser = nuser_fixture()
      assert {:error, %Ecto.Changeset{}} = NewsLetter.update_nuser(nuser, @invalid_attrs)
      assert nuser == NewsLetter.get_nuser!(nuser.id)
    end

    test "delete_nuser/1 deletes the nuser" do
      nuser = nuser_fixture()
      assert {:ok, %Nuser{}} = NewsLetter.delete_nuser(nuser)
      assert_raise Ecto.NoResultsError, fn -> NewsLetter.get_nuser!(nuser.id) end
    end

    test "change_nuser/1 returns a nuser changeset" do
      nuser = nuser_fixture()
      assert %Ecto.Changeset{} = NewsLetter.change_nuser(nuser)
    end
  end
end
