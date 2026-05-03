defmodule Mehungry.ComponentsTest do
  use Mehungry.DataCase

  alias Mehungry.Components

  describe "search_selects" do
    alias Mehungry.Components.SearchSelect

    import Mehungry.ComponentsFixtures

    @invalid_attrs %{}

    test "list_search_selects/0 returns all search_selects" do
      search_select = search_select_fixture()
      assert Components.list_search_selects() == [search_select]
    end

    test "get_search_select!/1 returns the search_select with given id" do
      search_select = search_select_fixture()
      assert Components.get_search_select!(search_select.id) == search_select
    end

    test "create_search_select/1 with valid data creates a search_select" do
      valid_attrs = %{}

      assert {:ok, %SearchSelect{} = search_select} = Components.create_search_select(valid_attrs)
    end

    test "create_search_select/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Components.create_search_select(@invalid_attrs)
    end

    test "update_search_select/2 with valid data updates the search_select" do
      search_select = search_select_fixture()
      update_attrs = %{}

      assert {:ok, %SearchSelect{} = search_select} =
               Components.update_search_select(search_select, update_attrs)
    end

    test "update_search_select/2 with invalid data returns error changeset" do
      search_select = search_select_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Components.update_search_select(search_select, @invalid_attrs)

      assert search_select == Components.get_search_select!(search_select.id)
    end

    test "delete_search_select/1 deletes the search_select" do
      search_select = search_select_fixture()
      assert {:ok, %SearchSelect{}} = Components.delete_search_select(search_select)
      assert_raise Ecto.NoResultsError, fn -> Components.get_search_select!(search_select.id) end
    end

    test "change_search_select/1 returns a search_select changeset" do
      search_select = search_select_fixture()
      assert %Ecto.Changeset{} = Components.change_search_select(search_select)
    end
  end
end
