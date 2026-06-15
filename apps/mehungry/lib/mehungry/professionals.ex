defmodule Mehungry.Professionals do
  import Ecto.Query
  alias Mehungry.Repo
  alias Mehungry.Accounts
  alias Mehungry.Professionals.{
    ProfessionalProfile,
    TutorInvitation,
    TutorClientAssignment,
    Appointment,
    MealPlanRating
  }

  # ── Professional Profile ───────────────────────────────────────────────────────

  def get_professional_profile(user_id) do
    Repo.get_by(ProfessionalProfile, user_id: user_id)
  end

  def get_professional_profile!(user_id) do
    Repo.get_by!(ProfessionalProfile, user_id: user_id)
  end

  def create_professional_profile(attrs) do
    %ProfessionalProfile{}
    |> ProfessionalProfile.changeset(attrs)
    |> Repo.insert()
  end

  def update_professional_profile(%ProfessionalProfile{} = profile, attrs) do
    profile
    |> ProfessionalProfile.changeset(attrs)
    |> Repo.update()
  end

  def change_professional_profile(%ProfessionalProfile{} = profile, attrs \\ %{}) do
    ProfessionalProfile.changeset(profile, attrs)
  end

  # ── Invitations ────────────────────────────────────────────────────────────────

  @doc "Send an invitation from a professional to a user identified by email."
  def invite_client(professional_id, client_email, message \\ nil) do
    case Accounts.get_user_by_email(client_email) do
      nil ->
        {:error, :client_not_found}

      client ->
        existing = Repo.get_by(TutorInvitation, professional_id: professional_id, client_id: client.id)

        cond do
          not is_nil(existing) and existing.status == "pending" ->
            {:error, :already_invited}

          not is_nil(existing) and existing.status == "accepted" ->
            {:error, :already_client}

          not is_nil(existing) ->
            existing
            |> TutorInvitation.changeset(%{status: "pending", message: message})
            |> Repo.update()

          true ->
            %TutorInvitation{}
            |> TutorInvitation.changeset(%{
              professional_id: professional_id,
              client_id: client.id,
              message: message
            })
            |> Repo.insert()
        end
    end
  end

  def get_invitation(id), do: Repo.get(TutorInvitation, id)

  def accept_invitation(invitation_id, client_id) do
    with %TutorInvitation{} = inv <- Repo.get(TutorInvitation, invitation_id),
         true <- inv.client_id == client_id,
         true <- inv.status == "pending",
         {:ok, inv} <- inv |> TutorInvitation.changeset(%{status: "accepted"}) |> Repo.update() do
      # Remove any existing assignment for this client (one nutritionist max)
      Repo.delete_all(
        from a in TutorClientAssignment, where: a.client_id == ^client_id
      )

      case %TutorClientAssignment{}
           |> TutorClientAssignment.changeset(%{
             professional_id: inv.professional_id,
             client_id: client_id
           })
           |> Repo.insert() do
        {:ok, assignment} -> {:ok, assignment}
        {:error, cs} -> {:error, cs}
      end
    else
      nil -> {:error, :not_found}
      false -> {:error, :unauthorized}
      {:error, cs} -> {:error, cs}
    end
  end

  def decline_invitation(invitation_id, client_id) do
    with %TutorInvitation{} = inv <- Repo.get(TutorInvitation, invitation_id),
         true <- inv.client_id == client_id,
         true <- inv.status == "pending" do
      inv |> TutorInvitation.changeset(%{status: "declined"}) |> Repo.update()
    else
      nil -> {:error, :not_found}
      false -> {:error, :unauthorized}
    end
  end

  def revoke_invitation(invitation_id, professional_id) do
    with %TutorInvitation{} = inv <- Repo.get(TutorInvitation, invitation_id),
         true <- inv.professional_id == professional_id,
         true <- inv.status == "pending" do
      Repo.delete(inv)
    else
      nil -> {:error, :not_found}
      false -> {:error, :unauthorized}
    end
  end

  def list_pending_invitations_for_client(client_id) do
    Repo.all(
      from i in TutorInvitation,
        where: i.client_id == ^client_id and i.status == "pending",
        preload: [professional: :user_profile]
    )
  end

  def list_sent_invitations(professional_id) do
    Repo.all(
      from i in TutorInvitation,
        where: i.professional_id == ^professional_id,
        order_by: [desc: i.inserted_at],
        preload: [client: :user_profile]
    )
  end

  def count_pending_invitations_for_client(client_id) do
    Repo.one(
      from i in TutorInvitation,
        where: i.client_id == ^client_id and i.status == "pending",
        select: count(i.id)
    )
  end

  # ── Client Assignments ─────────────────────────────────────────────────────────

  def list_clients(professional_id) do
    Repo.all(
      from a in TutorClientAssignment,
        where: a.professional_id == ^professional_id,
        order_by: [asc: a.inserted_at],
        preload: [client: :user_profile]
    )
  end

  def count_clients(professional_id) do
    Repo.one(
      from a in TutorClientAssignment,
        where: a.professional_id == ^professional_id,
        select: count(a.id)
    )
  end

  def get_assignment_for_client(client_id) do
    Repo.get_by(TutorClientAssignment, client_id: client_id)
    |> Repo.preload(:professional)
  end

  def get_assignment(professional_id, client_id) do
    Repo.get_by(TutorClientAssignment,
      professional_id: professional_id,
      client_id: client_id
    )
  end

  def remove_client(professional_id, client_id) do
    case get_assignment(professional_id, client_id) do
      nil -> {:error, :not_found}
      assignment -> Repo.delete(assignment)
    end
  end

  # ── Appointments ───────────────────────────────────────────────────────────────

  def list_appointments_for_professional(professional_id, start_dt, end_dt) do
    Repo.all(
      from a in Appointment,
        where:
          a.professional_id == ^professional_id and
            a.scheduled_at >= ^start_dt and
            a.scheduled_at <= ^end_dt,
        order_by: [asc: a.scheduled_at],
        preload: [client: :user_profile]
    )
  end

  def list_appointments_for_client(client_id) do
    Repo.all(
      from a in Appointment,
        where: a.client_id == ^client_id,
        order_by: [desc: a.scheduled_at],
        preload: [professional: :user_profile]
    )
  end

  def list_upcoming_appointments(professional_id, limit \\ 5) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.all(
      from a in Appointment,
        where: a.professional_id == ^professional_id and a.scheduled_at >= ^now,
        order_by: [asc: a.scheduled_at],
        limit: ^limit,
        preload: [client: :user_profile]
    )
  end

  def get_appointment!(id), do: Repo.get!(Appointment, id)

  def create_appointment(attrs) do
    %Appointment{}
    |> Appointment.changeset(attrs)
    |> Repo.insert()
  end

  def update_appointment(%Appointment{} = appointment, attrs) do
    appointment
    |> Appointment.changeset(attrs)
    |> Repo.update()
  end

  def delete_appointment(%Appointment{} = appointment) do
    Repo.delete(appointment)
  end

  def change_appointment(%Appointment{} = appointment, attrs \\ %{}) do
    Appointment.changeset(appointment, attrs)
  end

  # ── Meal Plan Ratings ──────────────────────────────────────────────────────────

  def upsert_meal_plan_rating(attrs) do
    %MealPlanRating{}
    |> MealPlanRating.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:score, :comment, :updated_at]},
      conflict_target: [:user_id, :rated_for_date, :rating_type],
      conflict_target_name: :meal_plan_ratings_user_date_type_unique
    )
  end

  def get_rating_for_date(user_id, date, rating_type) do
    Repo.get_by(MealPlanRating, user_id: user_id, rated_for_date: date, rating_type: rating_type)
  end

  def get_rating_for_daily(user_id, daily_meal_plan_id) do
    Repo.get_by(MealPlanRating, user_id: user_id, daily_meal_plan_id: daily_meal_plan_id)
  end

  def get_rating_for_meal_plan(user_id, meal_plan_id) do
    Repo.get_by(MealPlanRating, user_id: user_id, meal_plan_id: meal_plan_id)
  end

  def list_ratings_for_client(client_id) do
    Repo.all(
      from r in MealPlanRating,
        where: r.user_id == ^client_id,
        order_by: [desc: r.inserted_at],
        preload: [:daily_meal_plan, :meal_plan]
    )
  end

  def change_meal_plan_rating(%MealPlanRating{} = rating, attrs \\ %{}) do
    MealPlanRating.changeset(rating, attrs)
  end
end
