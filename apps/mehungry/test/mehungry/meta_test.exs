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

    test "traffic_sources/1 aggregates visits by referrer category" do
      visit_fixture(%{details: %{"referrer" => "https://www.google.com/"}})
      visit_fixture(%{details: %{"referrer" => "https://www.google.com/search?q=pasta"}})
      visit_fixture(%{details: %{"referrer" => "https://www.facebook.com/"}})
      visit_fixture(%{details: %{"referrer" => "https://mehungry.net/browse"}})
      visit_fixture(%{details: %{"referrer" => "https://someblog.example.com/post"}})
      visit_fixture(%{details: %{"referrer" => ""}})
      visit_fixture(%{details: %{}})

      counts = Meta.traffic_sources(30) |> Map.new(fn %{source: s, count: c} -> {s, c} end)

      assert counts == %{
               "search" => 2,
               "social" => 1,
               "internal" => 1,
               "referral" => 1,
               "direct" => 2
             }
    end

    test "traffic_sources/1 sorts by count descending and excludes old visits" do
      visit_fixture(%{details: %{"referrer" => "https://www.google.com/"}})
      visit_fixture(%{details: %{"referrer" => "https://bing.com/search?q=x"}})
      visit_fixture(%{details: %{"referrer" => ""}})

      old = visit_fixture(%{details: %{"referrer" => "https://www.google.com/"}})
      before_cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -40 * 86_400, :second)

      old
      |> Ecto.Changeset.change(inserted_at: NaiveDateTime.truncate(before_cutoff, :second))
      |> Mehungry.Repo.update!()

      assert [%{source: "search", count: 2}, %{source: "direct", count: 1}] =
               Meta.traffic_sources(30)
    end
  end
end
