defmodule Mehungry.OnboardingTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.Onboarding
  alias Mehungry.Professionals.DietaryHistory.Fields

  describe "create_question/1" do
    test "value question auto-slugs source_key and auto-assigns position" do
      {:ok, q1} =
        Onboarding.create_question(%{
          "scope" => "user",
          "prompt_en" => "What is your goal?",
          "question_type" => "value",
          "value_kind" => "text"
        })

      assert q1.source_key == "what_is_your_goal"
      assert q1.position == 0

      {:ok, q2} =
        Onboarding.create_question(%{"scope" => "user", "prompt_en" => "Second", "question_type" => "value"})

      assert q2.position == 1
    end

    test "choice question slugs option keys and requires at least one option" do
      {:ok, q} =
        Onboarding.create_question(%{
          "scope" => "user",
          "prompt_en" => "How often do you cook?",
          "question_type" => "single_choice",
          "options" => %{
            "0" => %{"label_en" => "Daily", "label_el" => "Καθημερινά"},
            "1" => %{"label_en" => "Weekly"}
          }
        })

      assert Enum.map(q.options, & &1.key) == ["daily", "weekly"]

      assert {:error, changeset} =
               Onboarding.create_question(%{
                 "scope" => "user",
                 "prompt_en" => "No options",
                 "question_type" => "single_choice"
               })

      assert %{options: [_]} = errors_on(changeset)
    end
  end

  describe "list + reorder" do
    setup do
      {:ok, a} = Onboarding.create_question(%{"scope" => "user", "prompt_en" => "A", "question_type" => "value"})
      {:ok, b} = Onboarding.create_question(%{"scope" => "user", "prompt_en" => "B", "question_type" => "value"})

      {:ok, c} =
        Onboarding.create_question(%{
          "scope" => "user",
          "prompt_en" => "C",
          "question_type" => "value",
          "active" => false
        })

      %{a: a, b: b, c: c}
    end

    test "list_active_questions excludes inactive, keeps order", %{a: a, b: b} do
      assert Enum.map(Onboarding.list_active_questions("user"), & &1.id) == [a.id, b.id]
    end

    test "move_question swaps neighbours", %{a: a} do
      assert :ok = Onboarding.move_question(a, :down)
      assert Onboarding.list_questions("user") |> Enum.map(& &1.prompt_en) |> Enum.take(2) == ["B", "A"]

      # Moving the first item up is a no-op.
      [first | _] = Onboarding.list_questions("user")
      assert :noop = Onboarding.move_question(first, :up)
    end
  end

  describe "ensure_client_questions/1 (snapshot on first use)" do
    setup do
      {:ok, d1} =
        Onboarding.create_question(%{
          "scope" => "client_default",
          "prompt_en" => "Reason for visit",
          "question_type" => "value"
        })

      {:ok, _d2} =
        Onboarding.create_question(%{
          "scope" => "client_default",
          "prompt_en" => "Allergies",
          "question_type" => "value"
        })

      professional = Mehungry.AccountsFixtures.user_fixture()
      %{default_first: d1, professional_id: professional.id}
    end

    test "copies the active default into the nutritionist's own set", %{professional_id: pid} do
      snapshot = Onboarding.ensure_client_questions(pid)

      assert length(snapshot) == 2
      assert Enum.all?(snapshot, &(&1.scope == "client" and &1.professional_id == pid))
      assert Enum.map(snapshot, & &1.prompt_en) == ["Reason for visit", "Allergies"]
    end

    test "is idempotent and unaffected by later default edits", %{
      professional_id: pid,
      default_first: d1
    } do
      first = Onboarding.ensure_client_questions(pid)

      # Admin later edits/adds to the template…
      Onboarding.update_question(d1, %{"prompt_en" => "CHANGED"})

      {:ok, _} =
        Onboarding.create_question(%{
          "scope" => "client_default",
          "prompt_en" => "Added later",
          "question_type" => "value"
        })

      second = Onboarding.ensure_client_questions(pid)

      assert Enum.map(first, & &1.id) == Enum.map(second, & &1.id)
      assert "CHANGED" not in Enum.map(second, & &1.prompt_en)
      assert length(second) == 2
    end
  end

  describe "answers" do
    setup do
      {:ok, text_q} =
        Onboarding.create_question(%{"scope" => "user", "prompt_en" => "Goal", "question_type" => "value"})

      {:ok, choice_q} =
        Onboarding.create_question(%{
          "scope" => "user",
          "prompt_en" => "Cook often?",
          "question_type" => "single_choice",
          "options" => %{"0" => %{"label_en" => "Daily"}, "1" => %{"label_en" => "Weekly"}}
        })

      %{text_q: text_q, choice_q: choice_q}
    end

    test "upsert creates, then replaces", %{text_q: text_q, choice_q: choice_q} do
      params = %{
        to_string(text_q.id) => %{"value_text" => "lose weight"},
        to_string(choice_q.id) => %{"selected_options" => ["daily"]}
      }

      Onboarding.upsert_answers("user", 7, params, [text_q, choice_q])

      answers = Onboarding.get_answers("user", 7)
      assert answers[text_q.id].value_text == "lose weight"
      assert answers[choice_q.id].selected_options == ["daily"]
      assert answers[text_q.id].prompt_snapshot == "Goal"

      # Re-submit replaces (no duplicate rows).
      Onboarding.upsert_answers("user", 7, %{to_string(text_q.id) => %{"value_text" => "maintain"}}, [text_q])
      answers = Onboarding.get_answers("user", 7)
      assert answers[text_q.id].value_text == "maintain"
      assert map_size(answers) == 2
    end

    test "answers_for_user returns display pairs ordered by position", %{
      text_q: text_q,
      choice_q: choice_q
    } do
      Onboarding.upsert_answers(
        "user",
        9,
        %{
          to_string(text_q.id) => %{"value_text" => "x"},
          to_string(choice_q.id) => %{"selected_options" => ["weekly"]}
        },
        [text_q, choice_q]
      )

      pairs = Onboarding.answers_for_user(9)
      assert Enum.map(pairs, fn {q, _a} -> q.prompt_en end) == ["Goal", "Cook often?"]
    end
  end

  describe "seed_defaults/0" do
    test "seeds the client_default template from Fields, idempotently" do
      assert :ok = Onboarding.seed_defaults()
      count = length(Onboarding.list_questions("client_default"))
      assert count == length(Fields.detail_labels())

      assert :ok = Onboarding.seed_defaults()
      assert length(Onboarding.list_questions("client_default")) == count
    end
  end
end
