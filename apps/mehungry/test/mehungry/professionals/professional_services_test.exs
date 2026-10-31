defmodule Mehungry.Professionals.ProfessionalServicesTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.Professionals
  alias Mehungry.Professionals.ProfessionalService

  setup do
    %{user: Mehungry.AccountsFixtures.user_fixture()}
  end

  describe "create_service/1" do
    test "creates a paid session", %{user: user} do
      assert {:ok, %ProfessionalService{} = s} =
               Professionals.create_service(%{
                 professional_id: user.id,
                 kind: "session",
                 name: "Initial consultation",
                 price_cents: 4000,
                 duration_minutes: 60
               })

      assert s.kind == "session"
      assert s.price_cents == 4000
      assert s.active == true
    end

    test "creates a package with a session count", %{user: user} do
      assert {:ok, s} =
               Professionals.create_service(%{
                 professional_id: user.id,
                 kind: "package",
                 name: "2-month support",
                 description: "1 initial + 4 follow-ups",
                 price_cents: 13_000,
                 session_count: 5
               })

      assert s.kind == "package"
      assert s.session_count == 5
    end

    test "rejects an unknown kind", %{user: user} do
      assert {:error, cs} =
               Professionals.create_service(%{
                 professional_id: user.id,
                 kind: "bogus",
                 name: "x"
               })

      assert "is invalid" in errors_on(cs).kind
    end

    test "rejects a negative price", %{user: user} do
      assert {:error, cs} =
               Professionals.create_service(%{
                 professional_id: user.id,
                 kind: "session",
                 name: "x",
                 price_cents: -1
               })

      refute Enum.empty?(errors_on(cs).price_cents)
    end
  end

  describe "intro invariants" do
    test "an intro is forced to free / 15 min / single session regardless of input", %{user: user} do
      assert {:ok, intro} =
               Professionals.create_service(%{
                 professional_id: user.id,
                 kind: "intro",
                 name: "My intro",
                 price_cents: 9999,
                 duration_minutes: 90,
                 session_count: 3
               })

      assert intro.price_cents == 0
      assert intro.duration_minutes == 15
      assert intro.session_count == 1
    end

    test "only one intro per professional is allowed", %{user: user} do
      assert {:ok, _} = Professionals.ensure_intro_service(user.id)

      assert {:error, cs} =
               Professionals.create_service(%{
                 professional_id: user.id,
                 kind: "intro",
                 name: "second intro"
               })

      refute Enum.empty?(errors_on(cs).professional_id)
    end

    test "the intro cannot be deleted or archived", %{user: user} do
      {:ok, intro} = Professionals.ensure_intro_service(user.id)

      assert {:error, :intro_undeletable} = Professionals.delete_service(intro)
      assert {:ok, ^intro} = Professionals.archive_service(intro)
      assert Professionals.get_service!(intro.id).active == true
    end
  end

  describe "ensure_intro_service/1" do
    test "is idempotent — seeds once, then returns the same row", %{user: user} do
      assert {:ok, first} = Professionals.ensure_intro_service(user.id)
      assert {:ok, second} = Professionals.ensure_intro_service(user.id)
      assert first.id == second.id
    end
  end

  describe "listing" do
    test "intro sorts first, then by position; active filter works", %{user: user} do
      {:ok, _intro} = Professionals.ensure_intro_service(user.id)

      {:ok, _a} =
        Professionals.create_service(%{
          professional_id: user.id,
          kind: "session",
          name: "B",
          position: 2
        })

      {:ok, b} =
        Professionals.create_service(%{
          professional_id: user.id,
          kind: "session",
          name: "A",
          position: 1
        })

      {:ok, _archived} = Professionals.archive_service(b)

      all = Professionals.list_services(user.id)
      assert hd(all).kind == "intro"
      assert length(all) == 3

      active = Professionals.list_active_services(user.id)
      assert length(active) == 2
      assert hd(active).kind == "intro"
    end
  end

  describe "tenant scoping" do
    test "get_service_for_professional/2 rejects another nutritionist's service", %{user: user} do
      other = Mehungry.AccountsFixtures.user_fixture()

      {:ok, s} =
        Professionals.create_service(%{professional_id: user.id, kind: "session", name: "x"})

      assert Professionals.get_service_for_professional(user.id, s.id).id == s.id
      assert Professionals.get_service_for_professional(other.id, s.id) == nil
    end
  end
end
