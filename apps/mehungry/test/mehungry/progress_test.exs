defmodule Mehungry.ProgressTest do
  # async: false — the photo-deletion tests pin the global `:storage_impl` seam.
  use Mehungry.DataCase, async: false

  import Mehungry.AccountsFixtures

  alias Mehungry.Professionals
  alias Mehungry.Progress
  alias Mehungry.Progress.Period

  defmodule StorageSpy do
    @behaviour Mehungry.Storage.Behaviour

    def put(_key, _binary, _opts), do: {:ok, %{url: "https://stub/x", key: "x"}}
    def get(_key), do: {:ok, <<>>}

    def delete(key) do
      send(Process.get(:storage_spy_pid) || self(), {:storage_delete, key})
      {:ok, :deleted}
    end

    def list(_prefix), do: {:ok, []}
    def public_url(key), do: "https://stub/#{key}"
    def signed_upload(_key, _opts), do: {:error, :not_supported}
  end

  defp stub_storage(test_pid) do
    prev = Application.get_env(:mehungry, :storage_impl)
    Application.put_env(:mehungry, :storage_impl, StorageSpy)
    Process.put(:storage_spy_pid, test_pid)

    on_exit(fn ->
      if prev,
        do: Application.put_env(:mehungry, :storage_impl, prev),
        else: Application.delete_env(:mehungry, :storage_impl)
    end)
  end

  defp nutritionist_with_invite(client) do
    pro = user_fixture()
    {:ok, inv} = Professionals.invite_client(pro.id, client.email)
    {pro, inv}
  end

  describe "period lifecycle" do
    test "ensure_active_period creates one self period, idempotently" do
      user = user_fixture()

      {:ok, period} = Progress.ensure_active_period(user.id)
      assert period.kind == "self"
      assert period.started_on == Date.utc_today()
      assert is_nil(period.ended_on)

      {:ok, same} = Progress.ensure_active_period(user.id)
      assert same.id == period.id
      assert length(Progress.list_periods(user.id)) == 1
    end

    test "the one-active-period invariant is DB-enforced" do
      user = user_fixture()
      {:ok, _} = Progress.ensure_active_period(user.id)

      assert {:error, changeset} =
               %Period{}
               |> Period.changeset(%{
                 user_id: user.id,
                 kind: "self",
                 started_on: Date.utc_today()
               })
               |> Repo.insert()

      assert %{user_id: ["already has an active period"]} = errors_on(changeset)
    end

    test "reset_period closes the active period and opens a fresh one" do
      user = user_fixture()
      {:ok, _} = Progress.ensure_active_period(user.id)

      {:ok, period} =
        Progress.configure_period(user.id, Progress.active_period(user.id).id, %{
          tracked_metrics: ["weight_kg", "waist_cm"],
          goals: %{"weight_kg" => 72},
          height_m: 1.75,
          sex: "male",
          age: 34
        })

      {:ok, %{closed: closed, opened: opened}} = Progress.reset_period(user.id)

      assert closed.id == period.id
      assert closed.ended_on == Date.utc_today()
      assert opened.id != closed.id
      assert is_nil(opened.ended_on)
      # Carries tracking config + snapshot, resets goals.
      assert opened.tracked_metrics == ["weight_kg", "waist_cm"]
      assert opened.height_m == 1.75
      assert opened.sex == "male"
      assert opened.age == 34
      assert opened.goals == %{}
      assert Progress.active_period(user.id).id == opened.id
    end

    test "reset_period with no active period just opens one" do
      user = user_fixture()
      {:ok, %{closed: nil, opened: opened}} = Progress.reset_period(user.id)
      assert opened.kind == "self"
    end

    test "ensure_journal opens an aligned period for an already-assigned user" do
      client = user_fixture()
      {pro, inv} = nutritionist_with_invite(client)
      {:ok, _} = Professionals.accept_invitation(inv.id, client.id)
      # accept_invitation already opened the aligned period; drop it to simulate
      # a pre-feature client whose journal is bootstrapped on first view.
      Repo.delete_all(Period)

      {:ok, period} = Progress.ensure_journal(client.id)
      assert period.kind == "nutritionist_aligned"
      assert period.professional_id == pro.id
    end

    test "get_period is ownership-scoped" do
      user = user_fixture()
      other = user_fixture()
      {:ok, period} = Progress.ensure_active_period(user.id)

      assert Progress.get_period(user.id, period.id).id == period.id
      assert Progress.get_period(other.id, period.id) == nil
    end
  end

  describe "configure_period / goals" do
    test "normalizes goals (string values parsed, invalid dropped)" do
      user = user_fixture()
      {:ok, period} = Progress.ensure_active_period(user.id)

      {:ok, updated} =
        Progress.configure_period(user.id, period.id, %{
          goals: %{"weight_kg" => "72.5", "waist_cm" => "", "bmi" => 20, "bogus" => 1}
        })

      # bmi isn't selectable, blanks and unknown keys are dropped.
      assert updated.goals == %{"weight_kg" => 72.5}
    end

    test "rejects configuring a nutritionist-aligned period" do
      client = user_fixture()
      {pro, _inv} = nutritionist_with_invite(client)
      {:ok, aligned} = Progress.on_nutritionist_assigned(client.id, pro.id)

      assert {:error, :not_self_period} =
               Progress.set_goals(client.id, aligned.id, %{"weight_kg" => 70})
    end
  end

  describe "entries (diary)" do
    test "upsert_entry_by_date is one-entry-per-date" do
      user = user_fixture()
      {:ok, period} = Progress.ensure_active_period(user.id)
      date = Date.utc_today()

      {:ok, e1} = Progress.upsert_entry_by_date(user.id, period.id, date, %{"weight_kg" => 80})
      {:ok, e2} = Progress.upsert_entry_by_date(user.id, period.id, date, %{"weight_kg" => 79})

      assert e1.id == e2.id
      assert e2.weight_kg == 79.0
      assert length(Progress.list_entries(user.id, period.id)) == 1
    end

    test "derives BMI from the snapshot height, BMR only with sex+age+height" do
      user = user_fixture()
      {:ok, period} = Progress.ensure_active_period(user.id)

      # No snapshot → nothing derived (never fabricated).
      {:ok, bare} = Progress.log_entry(user.id, period.id, %{"weight_kg" => 80})
      assert is_nil(bare.bmi)
      assert is_nil(bare.bmr_kcal)

      # Height only → BMI, still no BMR.
      {:ok, _} = Progress.configure_period(user.id, period.id, %{height_m: 1.75})
      period = Progress.get_period(user.id, period.id)

      {:ok, with_bmi} =
        Progress.upsert_entry_by_date(user.id, period.id, Date.utc_today(), %{"weight_kg" => 80})

      assert with_bmi.bmi == 26.1
      assert is_nil(with_bmi.bmr_kcal)

      # Full snapshot → BMI + BMR.
      {:ok, _} = Progress.configure_period(user.id, period.id, %{sex: "male", age: 34})
      period = Progress.get_period(user.id, period.id)

      {:ok, full} =
        Progress.upsert_entry_by_date(user.id, period.id, Date.utc_today(), %{"weight_kg" => 80})

      assert full.bmi == 26.1
      assert is_integer(full.bmr_kcal) and full.bmr_kcal > 0
    end

    test "rejects logging into an aligned period" do
      client = user_fixture()
      {pro, _inv} = nutritionist_with_invite(client)
      {:ok, aligned} = Progress.on_nutritionist_assigned(client.id, pro.id)

      assert {:error, :not_self_period} =
               Progress.log_entry(client.id, aligned.id, %{"weight_kg" => 80})
    end

    test "validates measurement ranges like consultation notes" do
      user = user_fixture()
      {:ok, period} = Progress.ensure_active_period(user.id)

      assert {:error, changeset} =
               Progress.log_entry(user.id, period.id, %{
                 "weight_kg" => -1,
                 "body_fat_percentage" => 120
               })

      assert %{weight_kg: _, body_fat_percentage: _} = errors_on(changeset)
    end
  end

  describe "measurement_history_for_period/1 — chart point parity" do
    test "self periods emit the exact nutritionist point shape with source :self" do
      user = user_fixture()
      {:ok, _} = Progress.ensure_active_period(user.id)
      {:ok, _} = Progress.configure_period(user.id, Progress.active_period(user.id).id, %{height_m: 1.75})
      period = Progress.active_period(user.id)

      {:ok, _} =
        Progress.upsert_entry_by_date(user.id, period.id, ~D[2026-10-01], %{"weight_kg" => 80})

      {:ok, _} =
        Progress.upsert_entry_by_date(user.id, period.id, ~D[2026-11-01], %{
          "weight_kg" => 78,
          "waist_cm" => 90
        })

      history = Progress.measurement_history_for_period(period)

      assert [first, second] = history
      assert first.date == ~D[2026-10-01]
      assert second.date == ~D[2026-11-01]

      # Exactly the Professionals.measurement_history_for_user/1 point keys.
      expected_keys =
        MapSet.new([:date, :source | Professionals.measurement_metrics()])

      assert MapSet.new(Map.keys(first)) == expected_keys
      assert first.source == :self
      assert second.waist_cm == 90.0
    end

    test "aligned periods show the nutritionist history up to their end, keeping sources" do
      client = user_fixture()
      pro = user_fixture()

      {:ok, record} =
        Professionals.create_client_record(%{
          professional_id: pro.id,
          user_id: client.id,
          full_name: "Test Client"
        })

      # A visit predating the assignment must still chart (old-tab parity).
      {:ok, _} =
        Professionals.create_consultation_note(%{
          professional_client_id: record.id,
          visit_date: Date.add(Date.utc_today(), -30),
          weight_kg: 83.0
        })

      {:ok, _} =
        Professionals.create_consultation_note(%{
          professional_client_id: record.id,
          visit_date: Date.utc_today(),
          weight_kg: 81.0
        })

      {:ok, aligned} = Progress.on_nutritionist_assigned(client.id, pro.id)
      history = Progress.measurement_history_for_period(aligned)

      assert [old, recent] = history
      assert old.date == Date.add(Date.utc_today(), -30)
      assert old.source == :visit
      assert recent.weight_kg == 81.0

      # A *closed* aligned period excludes measurements recorded after its end.
      {:ok, _} = Progress.on_nutritionist_unassigned(client.id)
      closed = Progress.get_period(client.id, aligned.id)

      {:ok, _} =
        Professionals.create_consultation_note(%{
          professional_client_id: record.id,
          visit_date: Date.add(Date.utc_today(), 1),
          weight_kg: 79.0
        })

      assert length(Progress.measurement_history_for_period(closed)) == 2
    end
  end

  describe "progress_context/2" do
    test "falls back to the period snapshot and always carries goals" do
      user = user_fixture()
      {:ok, _} = Progress.ensure_active_period(user.id)

      {:ok, period} =
        Progress.configure_period(user.id, Progress.active_period(user.id).id, %{
          height_m: 1.8,
          sex: "female",
          goals: %{"waist_cm" => 80}
        })

      context = Progress.progress_context(user.id, period)
      assert context[:height_m] == 1.8
      assert context[:sex] == "female"
      assert context[:goals] == %{"waist_cm" => 80.0}
    end
  end

  describe "sharing" do
    test "share_period requires an assigned nutritionist" do
      user = user_fixture()
      {:ok, period} = Progress.ensure_active_period(user.id)

      assert {:error, :no_nutritionist} = Progress.share_period(user.id, period.id)
    end

    test "share → nutritionist read surface → unshare" do
      client = user_fixture()
      {pro, inv} = nutritionist_with_invite(client)
      {:ok, _} = Professionals.accept_invitation(inv.id, client.id)
      # The aligned period is active; share the client's *previous* self period
      # by sharing the active one here for simplicity.
      period = Progress.active_period(client.id)

      {:ok, shared} = Progress.share_period(client.id, period.id)
      assert shared.shared_with_nutritionist

      assert %{period: %{id: id}, history: _, context: _} =
               Progress.shared_history_for_professional(pro.id, client.id)

      assert id == period.id

      # Another professional sees nothing.
      stranger = user_fixture()
      assert Progress.shared_history_for_professional(stranger.id, client.id) == nil

      {:ok, _} = Progress.unshare_period(client.id, period.id)
      assert Progress.shared_history_for_professional(pro.id, client.id) == nil
    end
  end

  describe "nutritionist alignment hooks" do
    test "accept_invitation closes the self period and opens an aligned one" do
      client = user_fixture()
      {:ok, self_period} = Progress.ensure_active_period(client.id)
      {pro, inv} = nutritionist_with_invite(client)

      {:ok, _assignment} = Professionals.accept_invitation(inv.id, client.id)

      active = Progress.active_period(client.id)
      assert active.kind == "nutritionist_aligned"
      assert active.professional_id == pro.id
      assert Progress.get_period(client.id, self_period.id).ended_on == Date.utc_today()
    end

    test "switching nutritionists re-aligns the active period" do
      client = user_fixture()
      {pro1, inv1} = nutritionist_with_invite(client)
      {:ok, _} = Professionals.accept_invitation(inv1.id, client.id)
      first_aligned = Progress.active_period(client.id)
      assert first_aligned.professional_id == pro1.id

      {pro2, inv2} = nutritionist_with_invite(client)
      {:ok, _} = Professionals.accept_invitation(inv2.id, client.id)

      active = Progress.active_period(client.id)
      assert active.kind == "nutritionist_aligned"
      assert active.professional_id == pro2.id
      assert active.id != first_aligned.id
      assert Progress.get_period(client.id, first_aligned.id).ended_on
    end

    test "re-accepting the same nutritionist is a no-op on the period" do
      client = user_fixture()
      {pro, inv} = nutritionist_with_invite(client)
      {:ok, _} = Professionals.accept_invitation(inv.id, client.id)
      aligned = Progress.active_period(client.id)

      {:ok, same} = Progress.on_nutritionist_assigned(client.id, pro.id)
      assert same.id == aligned.id
    end

    test "unassign (client-initiated) reopens a self period" do
      client = user_fixture()
      {_pro, inv} = nutritionist_with_invite(client)
      {:ok, _} = Professionals.accept_invitation(inv.id, client.id)
      aligned = Progress.active_period(client.id)

      {:ok, _} = Professionals.unassign_nutritionist(client.id)

      active = Progress.active_period(client.id)
      assert active.kind == "self"
      assert Progress.get_period(client.id, aligned.id).ended_on
    end

    test "remove_client (professional-initiated) reopens a self period" do
      client = user_fixture()
      {pro, inv} = nutritionist_with_invite(client)
      {:ok, _} = Professionals.accept_invitation(inv.id, client.id)

      {:ok, _} = Professionals.remove_client(pro.id, client.id)

      assert Progress.active_period(client.id).kind == "self"
    end
  end

  describe "photos" do
    setup do
      stub_storage(self())
      :ok
    end

    test "attach, markers, comparison, delete (incl. storage object)" do
      user = user_fixture()
      {:ok, period} = Progress.ensure_active_period(user.id)

      {:ok, e1} =
        Progress.upsert_entry_by_date(user.id, period.id, ~D[2026-10-01], %{"weight_kg" => 80})

      {:ok, e2} =
        Progress.upsert_entry_by_date(user.id, period.id, ~D[2026-11-01], %{"weight_kg" => 78})

      {:ok, p1} =
        Progress.attach_photo(user.id, e1.id, %{
          "url" => "https://stub/progress_photos/a.jpg",
          "storage_key" => "progress_photos/a.jpg"
        })

      {:ok, _p2} =
        Progress.attach_photo(user.id, e2.id, %{
          "url" => "https://stub/progress_photos/b.jpg",
          "storage_key" => "progress_photos/b.jpg"
        })

      markers = Progress.photo_markers(period)
      assert [%{date: ~D[2026-10-01]}, %{date: ~D[2026-11-01]}] = markers

      comparison = Progress.comparison(period)
      assert comparison.before.date == ~D[2026-10-01]
      assert comparison.now.date == ~D[2026-11-01]
      assert comparison.before.entry.weight_kg == 80.0

      # Ownership: another user can't delete the photo.
      other = user_fixture()
      assert {:error, :not_found} = Progress.delete_photo(other.id, p1.id)

      {:ok, _} = Progress.delete_photo(user.id, p1.id)
      assert_received {:storage_delete, "progress_photos/a.jpg"}
      assert Progress.comparison(period) == nil
    end

    test "delete_entry removes its photos' storage objects" do
      user = user_fixture()
      {:ok, period} = Progress.ensure_active_period(user.id)
      {:ok, entry} = Progress.log_entry(user.id, period.id, %{"weight_kg" => 80})

      {:ok, _} =
        Progress.attach_photo(user.id, entry.id, %{
          "url" => "https://stub/progress_photos/c.jpg",
          "storage_key" => "progress_photos/c.jpg"
        })

      {:ok, _} = Progress.delete_entry(user.id, entry.id)
      assert_received {:storage_delete, "progress_photos/c.jpg"}
      assert Progress.list_entries(user.id, period.id) == []
    end
  end
end
