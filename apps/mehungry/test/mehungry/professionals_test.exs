defmodule Mehungry.ProfessionalsTest do
  use Mehungry.DataCase, async: true

  import Mehungry.AccountsFixtures

  alias Mehungry.Professionals

  describe "professional profiles" do
    test "generates a slug from the display name" do
      user = user_fixture()

      {:ok, profile} =
        Professionals.create_professional_profile(%{
          user_id: user.id,
          specialization: "Dietitian",
          display_name: "Maria Papadaki"
        })

      assert profile.slug == "maria-papadaki"
    end

    test "disambiguates duplicate slugs" do
      u1 = user_fixture()
      u2 = user_fixture()

      {:ok, p1} =
        Professionals.create_professional_profile(%{
          user_id: u1.id,
          specialization: "Dietitian",
          display_name: "Maria Papadaki"
        })

      {:ok, p2} =
        Professionals.create_professional_profile(%{
          user_id: u2.id,
          specialization: "Dietitian",
          display_name: "Maria Papadaki"
        })

      assert p1.slug == "maria-papadaki"
      assert p2.slug == "maria-papadaki-1"
    end

    test "consultation fee is entered in euros and stored as cents" do
      user = user_fixture()

      {:ok, profile} =
        Professionals.create_professional_profile(%{
          user_id: user.id,
          specialization: "Dietitian",
          consultation_fee_eur: "49.99"
        })

      assert profile.consultation_fee_cents == 4999

      # Re-editing surfaces the stored cents back as euros in the changeset.
      changeset = Professionals.change_professional_profile(profile)
      assert Decimal.equal?(Ecto.Changeset.get_field(changeset, :consultation_fee_eur), "49.99")

      # Whole-euro input and clearing both round-trip correctly.
      {:ok, profile} =
        Professionals.update_professional_profile(profile, %{consultation_fee_eur: "50"})

      assert profile.consultation_fee_cents == 5000

      {:ok, profile} =
        Professionals.update_professional_profile(profile, %{consultation_fee_eur: ""})

      assert profile.consultation_fee_cents == nil
    end

    test "rejects a negative consultation fee" do
      user = user_fixture()

      {:error, changeset} =
        Professionals.create_professional_profile(%{
          user_id: user.id,
          specialization: "Dietitian",
          consultation_fee_eur: "-5"
        })

      assert %{consultation_fee_eur: _} = errors_on(changeset)
    end

    test "cannot publish without display name, city and bio" do
      user = user_fixture()

      {:error, changeset} =
        Professionals.create_professional_profile(%{
          user_id: user.id,
          specialization: "Dietitian",
          is_public: true
        })

      refute changeset.valid?
      assert %{city: _} = errors_on(changeset)
    end

    test "list_public_professionals filters by is_public and city" do
      pub = user_fixture()
      priv = user_fixture()

      {:ok, _} =
        Professionals.create_professional_profile(%{
          user_id: pub.id,
          specialization: "Dietitian",
          display_name: "Public One",
          city: "Rethymno",
          bio: "Hello",
          is_public: true
        })

      {:ok, _} =
        Professionals.create_professional_profile(%{
          user_id: priv.id,
          specialization: "Dietitian",
          display_name: "Private One",
          city: "Rethymno",
          bio: "Hidden",
          is_public: false
        })

      assert [%{display_name: "Public One"}] =
               Professionals.list_public_professionals(%{city: "rethymno"})

      assert [] = Professionals.list_public_professionals(%{city: "Athens"})
    end
  end

  describe "availability & booking" do
    setup do
      professional = user_fixture()
      client = user_fixture()

      # Availability every day 09:00–11:00 → 60-min slots at 09:00 and 10:00.
      rows =
        for dow <- 0..6 do
          %{day_of_week: dow, start_time: ~T[09:00:00], end_time: ~T[11:00:00]}
        end

      {:ok, _} = Professionals.replace_availabilities(professional.id, rows)

      %{professional: professional, client: client}
    end

    test "available_slots returns future slots", %{professional: professional} do
      today = Date.utc_today()
      slots = Professionals.available_slots(professional.id, today, Date.add(today, 7))

      assert slots != []
      assert Enum.all?(slots, &(NaiveDateTime.compare(&1, NaiveDateTime.utc_now()) == :gt))
    end

    test "requesting a slot books it and removes it from availability", %{
      professional: professional,
      client: client
    } do
      today = Date.utc_today()
      [slot | _] = Professionals.available_slots(professional.id, today, Date.add(today, 7))

      assert {:ok, appt} =
               Professionals.request_appointment(professional.id, client.id, slot, title: "C")

      assert appt.status == "requested"

      refute slot in Professionals.available_slots(professional.id, today, Date.add(today, 7))

      # A second request for the same slot is rejected.
      assert {:error, :slot_unavailable} =
               Professionals.request_appointment(professional.id, client.id, slot)
    end

    test "the DB rejects two active appointments in the same slot (race backstop)", %{
      professional: professional,
      client: client
    } do
      at = NaiveDateTime.new!(Date.add(Date.utc_today(), 2), ~T[09:00:00])

      base = %{
        professional_id: professional.id,
        client_id: client.id,
        scheduled_at: at,
        ends_at: NaiveDateTime.add(at, 3600),
        title: "C"
      }

      assert {:ok, first} = Professionals.create_appointment(Map.put(base, :status, "requested"))

      # Even when the slot_open? check is bypassed (simulating a concurrent
      # racer), the partial unique index blocks a second active appointment.
      assert {:error, changeset} =
               Professionals.create_appointment(Map.put(base, :status, "accepted"))

      assert %{scheduled_at: _} = errors_on(changeset)

      # Freeing the slot (decline/cancel) lets it be rebooked.
      {:ok, _} = Professionals.decline_appointment(first)

      assert {:ok, _} = Professionals.create_appointment(Map.put(base, :status, "requested"))
    end

    test "rejects a slot outside availability", %{professional: professional, client: client} do
      # 03:00 is never inside the 09:00–11:00 window.
      at = NaiveDateTime.new!(Date.add(Date.utc_today(), 3), ~T[03:00:00])

      assert {:error, :slot_unavailable} =
               Professionals.request_appointment(professional.id, client.id, at)
    end

    test "accept and decline transitions", %{professional: professional, client: client} do
      today = Date.utc_today()
      [slot | _] = Professionals.available_slots(professional.id, today, Date.add(today, 7))
      {:ok, appt} = Professionals.request_appointment(professional.id, client.id, slot)

      assert {:ok, accepted} =
               Professionals.accept_appointment(appt, meeting_url: "https://meet.example/x")

      assert accepted.status == "accepted"
      assert accepted.meeting_url == "https://meet.example/x"

      {:ok, appt2} =
        Professionals.request_appointment(
          professional.id,
          client.id,
          List.last(Professionals.available_slots(professional.id, today, Date.add(today, 7)))
        )

      assert {:ok, declined} = Professionals.decline_appointment(appt2)
      assert declined.status == "declined"
    end
  end

  describe "articles" do
    setup do
      user = user_fixture()

      {:ok, profile} =
        Professionals.create_professional_profile(%{
          user_id: user.id,
          specialization: "Dietitian",
          display_name: "Maria Papadaki"
        })

      %{profile: profile}
    end

    test "create_article generates a unique slug from the title", %{profile: profile} do
      {:ok, a1} =
        Professionals.create_article(%{
          "professional_profile_id" => profile.id,
          "title" => "Oxalates and Kidney Stones"
        })

      {:ok, a2} =
        Professionals.create_article(%{
          "professional_profile_id" => profile.id,
          "title" => "Oxalates and Kidney Stones"
        })

      assert a1.slug == "oxalates-and-kidney-stones"
      assert a2.slug == "oxalates-and-kidney-stones-1"
      assert a1.status == "draft"
    end

    test "get_published_article_by_slug excludes drafts", %{profile: profile} do
      {:ok, article} =
        Professionals.create_article(%{
          "professional_profile_id" => profile.id,
          "title" => "Draft Article"
        })

      refute Professionals.get_published_article_by_slug(article.slug)

      {:ok, published} = Professionals.publish_article(article)
      assert published.status == "published"
      assert published.published_at

      fetched = Professionals.get_published_article_by_slug(article.slug)
      assert fetched.id == article.id
      assert fetched.professional_profile.slug == profile.slug
    end

    test "paragraphs append in order and reorder", %{profile: profile} do
      {:ok, article} =
        Professionals.create_article(%{
          "professional_profile_id" => profile.id,
          "title" => "Body"
        })

      {:ok, p1} = Professionals.create_paragraph(article.id, %{"body" => "one"})
      {:ok, p2} = Professionals.create_paragraph(article.id, %{"body" => "two"})

      assert p1.position == 0
      assert p2.position == 1

      Professionals.reorder_paragraphs(article.id, [p2.id, p1.id])

      ordered = Professionals.get_article!(article.id).paragraphs |> Enum.map(& &1.id)
      assert ordered == [p2.id, p1.id]
    end

    test "add_reference validates the FK matching reference_type", %{profile: profile} do
      {:ok, article} =
        Professionals.create_article(%{
          "professional_profile_id" => profile.id,
          "title" => "Refs"
        })

      {:ok, paragraph} = Professionals.create_paragraph(article.id)

      condition = Mehungry.Repo.insert!(%Mehungry.Health.Condition{name: "Gout"})

      {:ok, ref} =
        Professionals.add_reference(paragraph, %{
          "reference_type" => "condition",
          "condition_id" => condition.id
        })

      assert ref.reference_type == "condition"
      assert ref.condition_id == condition.id
      assert ref.article_id == article.id

      # Missing the typed FK for the declared type is rejected.
      assert {:error, changeset} =
               Professionals.add_reference(paragraph, %{"reference_type" => "study"})

      assert %{study_id: _} = errors_on(changeset)
    end
  end

  describe "managed clients" do
    alias Mehungry.Accounts

    test "creates a login-less, assigned, unclaimed client from an alias" do
      pro = user_fixture()

      {:ok, %{user: client, claim_token: token}} =
        Professionals.create_managed_client(pro.id, "Maria K.")

      assert client.name == "Maria K."
      assert client.confirmed_at
      assert is_nil(client.hashed_password)
      assert client.managed_by_professional_id == pro.id
      assert Accounts.managed_unclaimed?(client)
      assert is_binary(token)

      # Appears in the professional's client list.
      assert [assignment] = Professionals.list_clients(pro.id)
      assert assignment.client_id == client.id
    end

    test "a valid claim token resolves to the managed user; junk does not" do
      pro = user_fixture()

      {:ok, %{user: client, claim_token: token}} =
        Professionals.create_managed_client(pro.id, "Maria K.")

      assert %{id: id} = Accounts.get_managed_user_by_claim_token(token)
      assert id == client.id
      assert is_nil(Accounts.get_managed_user_by_claim_token("not-a-real-token"))
    end

    test "claiming sets credentials, clears the managed flag, keeps the row and assignment" do
      pro = user_fixture()

      {:ok, %{user: client, claim_token: token}} =
        Professionals.create_managed_client(pro.id, "Maria K.")

      email = unique_user_email()

      {:ok, claimed} =
        Accounts.claim_managed_account(token, %{
          "email" => email,
          "password" => "super-secret-passphrase"
        })

      assert claimed.id == client.id
      assert claimed.email == email
      assert is_nil(claimed.managed_by_professional_id)
      refute Accounts.managed_unclaimed?(claimed)

      assert Accounts.get_user_by_email_and_password(email, "super-secret-passphrase").id ==
               client.id

      # Assignment survives the claim.
      assert [assignment] = Professionals.list_clients(pro.id)
      assert assignment.client_id == client.id

      # Token is single-use.
      assert :error =
               Accounts.claim_managed_account(token, %{
                 "email" => unique_user_email(),
                 "password" => "another-passphrase-1"
               })
    end

    test "claiming via OAuth sets the provider identity, no password, keeps the row" do
      pro = user_fixture()

      {:ok, %{user: client, claim_token: token}} =
        Professionals.create_managed_client(pro.id, "Maria K.")

      email = unique_user_email()

      {:ok, claimed} =
        Accounts.claim_managed_account_with_oauth(token, %{
          email: email,
          name: "Maria Karidi",
          profile_pic: "https://example.com/pic.jpg"
        })

      assert claimed.id == client.id
      assert claimed.email == email
      assert claimed.name == "Maria Karidi"
      assert claimed.confirmed_at
      assert is_nil(claimed.hashed_password)
      assert is_nil(claimed.managed_by_professional_id)
      refute Accounts.managed_unclaimed?(claimed)

      assert [assignment] = Professionals.list_clients(pro.id)
      assert assignment.client_id == client.id

      # Token is single-use.
      assert :error =
               Accounts.claim_managed_account_with_oauth(token, %{email: unique_user_email()})
    end

    test "OAuth claim reports :email_taken when the provider email is in use" do
      pro = user_fixture()
      existing = user_fixture()
      {:ok, %{claim_token: token}} = Professionals.create_managed_client(pro.id, "Maria K.")

      assert {:error, :email_taken} =
               Accounts.claim_managed_account_with_oauth(token, %{email: existing.email})
    end

    test "regenerating a claim token invalidates the previous one" do
      pro = user_fixture()

      {:ok, %{user: client, claim_token: first}} =
        Professionals.create_managed_client(pro.id, "Maria K.")

      {:ok, second} = Professionals.regenerate_claim_token(pro.id, client.id)

      assert is_nil(Accounts.get_managed_user_by_claim_token(first))
      assert %{id: id} = Accounts.get_managed_user_by_claim_token(second)
      assert id == client.id
    end
  end

  describe "client intake energy auto-calc" do
    setup do
      professional = user_fixture()
      client = user_fixture()

      {:ok, record} =
        Professionals.create_client_record(%{
          professional_id: professional.id,
          user_id: client.id,
          full_name: "Maria Papadaki"
        })

      %{record: record}
    end

    test "fills blank BMI/BMR/TDEE from anthropometrics on create", %{record: record} do
      {:ok, intake} =
        Professionals.create_intake(%{
          "professional_client_id" => record.id,
          "height_m" => "1.70",
          "weight_kg" => "72",
          "sex" => "female",
          "age" => "34",
          "activity_level" => "moderate"
        })

      assert intake.bmi == 24.9
      assert intake.bmr_kcal == 1452
      assert intake.tdee_kcal == round(1452 * 1.55)
    end

    test "does not overwrite supplied energy values (clobber guard)", %{record: record} do
      {:ok, intake} =
        Professionals.create_intake(%{
          "professional_client_id" => record.id,
          "height_m" => "1.70",
          "weight_kg" => "72",
          "sex" => "female",
          "age" => "34",
          "activity_level" => "moderate",
          # a measured RMR the nutritionist typed — must survive
          "bmr_kcal" => "1600"
        })

      assert intake.bmr_kcal == 1600
      # the blank ones still auto-fill
      assert intake.bmi == 24.9
      assert intake.tdee_kcal == round(1452 * 1.55)
    end

    test "fills only BMI when sex/age absent", %{record: record} do
      {:ok, intake} =
        Professionals.create_intake(%{
          "professional_client_id" => record.id,
          "height_m" => "1.70",
          "weight_kg" => "72"
        })

      assert intake.bmi == 24.9
      assert intake.bmr_kcal == nil
      assert intake.tdee_kcal == nil
    end

    test "rejects an unknown sex / activity level", %{record: record} do
      assert {:error, changeset} =
               Professionals.create_intake(%{
                 "professional_client_id" => record.id,
                 "sex" => "other"
               })

      assert %{sex: _} = errors_on(changeset)
    end
  end

  describe "weight_history/1" do
    setup do
      professional = user_fixture()
      client = user_fixture()

      {:ok, record} =
        Professionals.create_client_record(%{
          professional_id: professional.id,
          user_id: client.id,
          full_name: "Maria Papadaki"
        })

      %{record: record}
    end

    test "merges intake + visit weights, sorted ascending by date, dropping nils", %{
      record: record
    } do
      {:ok, _} =
        Professionals.create_intake(%{
          "professional_client_id" => record.id,
          "assessed_on" => "2026-01-10",
          "weight_kg" => "72.0"
        })

      {:ok, _} =
        Professionals.create_intake(%{
          "professional_client_id" => record.id,
          "assessed_on" => "2026-03-01",
          "weight_kg" => "70.5"
        })

      {:ok, _} =
        Professionals.create_consultation_note(%{
          "professional_client_id" => record.id,
          "visit_date" => "2026-02-05",
          "weight_kg" => "71.2"
        })

      {:ok, _} =
        Professionals.create_consultation_note(%{
          "professional_client_id" => record.id,
          "visit_date" => "2026-04-01",
          "weight_kg" => "69.8"
        })

      # dropped: no weight, and no date
      {:ok, _} =
        Professionals.create_consultation_note(%{
          "professional_client_id" => record.id,
          "visit_date" => "2026-05-01"
        })

      {:ok, _} =
        Professionals.create_intake(%{
          "professional_client_id" => record.id,
          "weight_kg" => "68.0"
        })

      history = Professionals.weight_history(record.id)

      assert Enum.map(history, & &1.date) == [
               ~D[2026-01-10],
               ~D[2026-02-05],
               ~D[2026-03-01],
               ~D[2026-04-01]
             ]

      assert Enum.map(history, & &1.weight_kg) == [72.0, 71.2, 70.5, 69.8]
      assert Enum.map(history, & &1.source) == [:intake, :visit, :intake, :visit]
    end

    test "returns [] when no dated weights exist", %{record: record} do
      assert Professionals.weight_history(record.id) == []
    end
  end

  describe "records_by_user_id/1" do
    test "maps each user to their record, scoped to the professional" do
      professional = user_fixture()
      other_professional = user_fixture()
      client_a = user_fixture()
      client_b = user_fixture()

      {:ok, rec_a} =
        Professionals.create_client_record(%{
          professional_id: professional.id,
          user_id: client_a.id,
          full_name: "A"
        })

      {:ok, rec_b} =
        Professionals.create_client_record(%{
          professional_id: professional.id,
          user_id: client_b.id,
          full_name: "B"
        })

      # Another professional's record for the same user must not leak in.
      {:ok, _other} =
        Professionals.create_client_record(%{
          professional_id: other_professional.id,
          user_id: client_a.id,
          full_name: "A elsewhere"
        })

      map = Professionals.records_by_user_id(professional.id)

      assert Map.keys(map) |> Enum.sort() == Enum.sort([client_a.id, client_b.id])
      assert map[client_a.id].id == rec_a.id
      assert map[client_b.id].id == rec_b.id
    end

    test "most recently created record wins on duplicate imports for a user" do
      professional = user_fixture()
      client = user_fixture()

      {:ok, _old} =
        Professionals.create_client_record(%{
          professional_id: professional.id,
          user_id: client.id,
          full_name: "Old"
        })

      {:ok, newer} =
        Professionals.create_client_record(%{
          professional_id: professional.id,
          user_id: client.id,
          full_name: "Newer"
        })

      map = Professionals.records_by_user_id(professional.id)

      assert map[client.id].id == newer.id
      assert map[client.id].full_name == "Newer"
    end

    test "returns an empty map for a professional with no records" do
      professional = user_fixture()
      assert Professionals.records_by_user_id(professional.id) == %{}
    end
  end

  describe "client ↔ nutritionist messages" do
    setup do
      %{professional: user_fixture(), client: user_fixture()}
    end

    test "send_message creates a message and broadcasts to both parties", %{
      professional: p,
      client: c
    } do
      Professionals.subscribe_to_messages(p.id)
      Professionals.subscribe_to_messages(c.id)

      assert {:ok, msg} = Professionals.send_message(p.id, c.id, p.id, "Hi there")
      assert msg.body == "Hi there"
      assert msg.sender_user_id == p.id
      assert is_nil(msg.read_at)

      # Delivered to both the professional's and the client's topic.
      assert_receive {:assignment_message, ^msg}
      assert_receive {:assignment_message, ^msg}
    end

    test "send_message rejects a blank body", %{professional: p, client: c} do
      assert {:error, changeset} = Professionals.send_message(p.id, c.id, p.id, "   ")
      refute changeset.valid?
    end

    test "list_messages returns the thread oldest first", %{professional: p, client: c} do
      {:ok, _} = Professionals.send_message(p.id, c.id, p.id, "first")
      {:ok, _} = Professionals.send_message(p.id, c.id, c.id, "second")

      assert Professionals.list_messages(p.id, c.id) |> Enum.map(& &1.body) == ["first", "second"]
    end

    test "mark_thread_read marks only the reader's received messages", %{professional: p, client: c} do
      {:ok, from_client} = Professionals.send_message(p.id, c.id, c.id, "client msg")
      {:ok, from_pro} = Professionals.send_message(p.id, c.id, p.id, "pro msg")

      assert Professionals.mark_thread_read(p.id, c.id, p.id) == 1

      by_id = Professionals.list_messages(p.id, c.id) |> Map.new(&{&1.id, &1})
      refute is_nil(by_id[from_client.id].read_at)
      assert is_nil(by_id[from_pro.id].read_at)
    end

    test "count_unread_messages_for counts messages addressed to the user", %{
      professional: p,
      client: c
    } do
      {:ok, _} = Professionals.send_message(p.id, c.id, c.id, "to pro 1")
      {:ok, _} = Professionals.send_message(p.id, c.id, c.id, "to pro 2")
      {:ok, _} = Professionals.send_message(p.id, c.id, p.id, "to client 1")

      assert Professionals.count_unread_messages_for(p.id) == 2
      assert Professionals.count_unread_messages_for(c.id) == 1

      Professionals.mark_thread_read(p.id, c.id, p.id)
      assert Professionals.count_unread_messages_for(p.id) == 0
      assert Professionals.count_unread_messages_for(c.id) == 1
    end

    test "unread_counts_by_client groups unread by client, excluding the pro's own", %{
      professional: p,
      client: c
    } do
      other = user_fixture()
      {:ok, _} = Professionals.send_message(p.id, c.id, c.id, "a")
      {:ok, _} = Professionals.send_message(p.id, c.id, c.id, "b")
      {:ok, _} = Professionals.send_message(p.id, other.id, other.id, "x")
      {:ok, _} = Professionals.send_message(p.id, other.id, p.id, "pro reply")

      counts = Professionals.unread_counts_by_client(p.id)
      assert counts[c.id] == 2
      assert counts[other.id] == 1
    end
  end
end
