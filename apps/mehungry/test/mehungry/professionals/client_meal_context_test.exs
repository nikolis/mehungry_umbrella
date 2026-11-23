defmodule Mehungry.Professionals.ClientMealContextTest do
  @moduledoc """
  The nutritionist-over-user precedence rule, resolved in one place and shared by
  both nutritionist-side AI draft paths (the agentic `get_client_record` tool and
  the calendar quick-draft `build_client_preferences/2`).

  Where the client's own profile and the nutritionist's file hold the same
  concept, the nutritionist's value must win.
  """
  use Mehungry.DataCase, async: true

  import Ecto.Query
  import Mehungry.AccountsFixtures

  alias Mehungry.{Professionals, Repo}
  alias Mehungry.Professionals.ClientMealContext

  describe "resolve/2 precedence (nutritionist over client)" do
    test "clinician intake TDEE wins over the client's own profile calorie target" do
      %{professional: professional, client: client, record: record} = setup_pair()

      {:ok, _intake} =
        Professionals.create_intake(%{
          "professional_client_id" => record.id,
          "tdee_kcal" => 1700
        })

      put_profile(client.id, %{daily_calorie_target: 2600})

      ctx = ClientMealContext.resolve(professional.id, client.id)

      assert ctx.calorie_target == 1700
    end

    test "the nutritionist's prescribed target wins over TDEE and the profile target" do
      %{professional: professional, client: client, record: record} = setup_pair()

      {:ok, _intake} =
        Professionals.create_intake(%{
          "professional_client_id" => record.id,
          "tdee_kcal" => 2100,
          "target_kcal" => 1600
        })

      put_profile(client.id, %{daily_calorie_target: 2600})

      assert ClientMealContext.resolve(professional.id, client.id).calorie_target == 1600
      assert ClientMealContext.calorie_target(professional.id, client.id) == 1600
    end

    test "the goal type shifts the band off TDEE; a typed target replaces it" do
      %{professional: professional, client: client, record: record} = setup_pair()

      {:ok, intake} =
        Professionals.create_intake(%{
          "professional_client_id" => record.id,
          "tdee_kcal" => 2000,
          "goal_type" => "lose"
        })

      ctx = ClientMealContext.resolve(professional.id, client.id)

      assert ctx.goal_type == "lose"
      assert ctx.calorie_band == %{min: 1600, max: 1800, aim: 1700, basis: :goal_lose}
      # The single number every surface steers at is the band's aim.
      assert ctx.calorie_target == 1700
      assert ClientMealContext.calorie_target(professional.id, client.id) == 1700

      {:ok, _} = Professionals.update_intake(intake, %{"target_kcal" => 1500})

      assert ClientMealContext.calorie_band(professional.id, client.id) ==
               %{min: 1350, max: 1650, aim: 1500, basis: :prescribed}
    end

    test "a prescribed target overrules the client's own while assigned, never overwriting it" do
      %{professional: professional, client: client, record: record} = setup_pair()
      put_profile(client.id, %{daily_calorie_target: 2600})

      Repo.insert!(%Professionals.TutorClientAssignment{
        professional_id: professional.id,
        client_id: client.id
      })

      # TDEE alone is an estimate, not a prescription — the client's own stands.
      {:ok, intake} =
        Professionals.create_intake(%{
          "professional_client_id" => record.id,
          "tdee_kcal" => 2100
        })

      assert ClientMealContext.effective_calorie_target(client.id, 2600) ==
               %{kcal: 2600, source: :self}

      {:ok, _} = Professionals.update_intake(intake, %{"target_kcal" => 1600})

      assert ClientMealContext.effective_calorie_target(client.id, 2600) ==
               %{kcal: 1600, source: :nutritionist}

      # Ending the coordination restores the client's own, untouched, target.
      {:ok, _} = Professionals.remove_client(professional.id, client.id)

      assert ClientMealContext.effective_calorie_target(client.id, 2600) ==
               %{kcal: 2600, source: :self}

      assert ClientMealContext.effective_calorie_target(client.id, nil) ==
               %{kcal: nil, source: nil}
    end

    test "foods to avoid union the client's profile list with the nutritionist's intake terms" do
      %{professional: professional, client: client, record: record} = setup_pair()

      {:ok, _intake} =
        Professionals.create_intake(%{
          "professional_client_id" => record.id,
          "details" => %{
            "allergies" => "shellfish, peanuts",
            "food_intolerances" => "lactose"
          }
        })

      put_profile(client.id, %{avoid_foods: ["shrimp"]})

      ctx = ClientMealContext.resolve(professional.id, client.id)

      assert "shrimp" in ctx.avoid
      assert "shellfish" in ctx.avoid
      assert "peanuts" in ctx.avoid
      assert "lactose" in ctx.avoid
    end

    test "falls back to the client's profile calorie target only when there is no intake TDEE" do
      %{professional: professional, client: client} = setup_pair()

      put_profile(client.id, %{daily_calorie_target: 2200})

      ctx = ClientMealContext.resolve(professional.id, client.id)

      assert ctx.calorie_target == 2200
    end

    test "is safe when the client has no record or profile fields set" do
      professional = user_fixture()
      client = user_fixture()

      ctx = ClientMealContext.resolve(professional.id, client.id)

      refute ctx.has_record
      assert ctx.diet == "omnivore"
      assert ctx.calorie_target == nil
      assert ctx.avoid == []
      assert ctx.conditions == []
    end
  end

  defp setup_pair do
    professional = user_fixture()
    client = user_fixture()

    {:ok, record} =
      Professionals.create_client_record(%{
        professional_id: professional.id,
        user_id: client.id,
        full_name: "Test Client"
      })

    %{professional: professional, client: client, record: record}
  end

  # user_fixture already creates a profile — update it in place.
  defp put_profile(user_id, attrs) do
    from(p in Mehungry.Accounts.UserProfile, where: p.user_id == ^user_id)
    |> Repo.update_all(set: Map.to_list(attrs))
  end
end
