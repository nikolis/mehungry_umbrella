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

      {:ok, appt2} = Professionals.request_appointment(professional.id, client.id, List.last(Professionals.available_slots(professional.id, today, Date.add(today, 7))))
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
end
