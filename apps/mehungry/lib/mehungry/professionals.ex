defmodule Mehungry.Professionals do
  import Ecto.Query
  alias Mehungry.Repo
  alias Mehungry.Accounts
  alias Mehungry.Accounts.User

  alias Mehungry.Professionals.{
    ProfessionalProfile,
    ProfessionalAvailability,
    TutorInvitation,
    TutorClientAssignment,
    Appointment,
    MealPlanRating,
    Article,
    ArticleParagraph,
    ArticleReference,
    ProfessionalClient,
    ClientIntake,
    ClientCondition,
    ConsultationNote,
    AssignmentMessage
  }

  alias Mehungry.Professionals.DietaryHistory
  alias Mehungry.Health.Condition

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
    |> ensure_unique_slug(nil)
    |> Repo.insert()
  end

  def update_professional_profile(%ProfessionalProfile{} = profile, attrs) do
    profile
    |> ProfessionalProfile.changeset(attrs)
    |> ensure_unique_slug(profile.id)
    |> Repo.update()
  end

  def change_professional_profile(%ProfessionalProfile{} = profile, attrs \\ %{}) do
    ProfessionalProfile.changeset(profile, attrs)
  end

  @doc "Update only the Stripe Connect fields (used by onboarding + webhooks)."
  def update_professional_stripe(%ProfessionalProfile{} = profile, attrs) do
    profile
    |> ProfessionalProfile.stripe_changeset(attrs)
    |> Repo.update()
  end

  @doc "Fetch a profile by its Stripe connected-account id, or nil."
  def get_profile_by_stripe_account(account_id) do
    Repo.get_by(ProfessionalProfile, stripe_connect_account_id: account_id)
  end

  @doc "Webhook helper: flip `stripe_charges_enabled` for a connected account."
  def set_stripe_charges_enabled(account_id, enabled) do
    case get_profile_by_stripe_account(account_id) do
      nil -> {:error, :not_found}
      profile -> update_professional_stripe(profile, %{stripe_charges_enabled: enabled})
    end
  end

  # Disambiguate a freshly-generated slug against existing rows (self excluded).
  defp ensure_unique_slug(changeset, self_id) do
    case Ecto.Changeset.get_change(changeset, :slug) do
      nil -> changeset
      base -> Ecto.Changeset.put_change(changeset, :slug, unique_slug(base, self_id, 0))
    end
  end

  defp unique_slug(base, self_id, n) do
    candidate = if n == 0, do: base, else: "#{base}-#{n}"

    query = from(p in ProfessionalProfile, where: p.slug == ^candidate)
    query = if self_id, do: from(p in query, where: p.id != ^self_id), else: query

    if Repo.exists?(query), do: unique_slug(base, self_id, n + 1), else: candidate
  end

  # ── Public discovery ───────────────────────────────────────────────────────────

  @doc """
  List published (`is_public`) professional profiles for the public directory.
  Optional filters: `:city` (exact, case-insensitive), `:specialization`
  (substring), `:q` (free-text over display name / specialization / city).
  """
  def list_public_professionals(filters \\ %{}) do
    ProfessionalProfile
    |> where([p], p.is_public == true)
    |> filter_by_city(filters[:city] || filters["city"])
    |> filter_by_specialization(filters[:specialization] || filters["specialization"])
    |> filter_by_query(filters[:q] || filters["q"])
    |> order_by([p], asc: p.display_name)
    |> Repo.all()
  end

  defp filter_by_city(query, nil), do: query
  defp filter_by_city(query, ""), do: query

  defp filter_by_city(query, city),
    do: where(query, [p], fragment("lower(?)", p.city) == ^String.downcase(city))

  defp filter_by_specialization(query, nil), do: query
  defp filter_by_specialization(query, ""), do: query

  defp filter_by_specialization(query, spec),
    do: where(query, [p], ilike(p.specialization, ^"%#{spec}%"))

  defp filter_by_query(query, nil), do: query
  defp filter_by_query(query, ""), do: query

  defp filter_by_query(query, q) do
    like = "%#{q}%"

    where(
      query,
      [p],
      ilike(p.display_name, ^like) or ilike(p.specialization, ^like) or ilike(p.city, ^like)
    )
  end

  @doc "Fetch a published profile by slug (with its user preloaded), or nil."
  def get_public_professional_by_slug(slug) do
    ProfessionalProfile
    |> where([p], p.slug == ^slug and p.is_public == true)
    |> preload(:user)
    |> Repo.one()
  end

  @doc """
  Fetch a published profile by its vanity `handle` (case-insensitive), or nil.
  Backs the personal short link `/@handle` → canonical `/nutritionists/:slug`.
  """
  def get_public_professional_by_handle(handle) when is_binary(handle) do
    normalized = handle |> String.trim() |> String.downcase()

    ProfessionalProfile
    |> where([p], p.handle == ^normalized and p.is_public == true)
    |> Repo.one()
  end

  def get_public_professional_by_handle(_), do: nil

  @doc "Distinct cities of published professionals, for directory filters."
  def list_professional_cities do
    ProfessionalProfile
    |> where([p], p.is_public == true and not is_nil(p.city) and p.city != "")
    |> select([p], p.city)
    |> distinct(true)
    |> order_by([p], asc: p.city)
    |> Repo.all()
  end

  # ── Invitations ────────────────────────────────────────────────────────────────

  @doc """
  Send an invitation from a professional to a user identified by email.

  Resolution falls back from an exact email match to the canonical form, so a
  registered user invited via a Gmail-style alias (`johndoe@` vs the stored
  `john.doe@`) still resolves — matching what `onboard_client_by_email/4`
  treats as already-registered, which otherwise dead-ends the invite flow.
  """
  def invite_client(professional_id, client_email, message \\ nil) do
    client =
      Accounts.get_user_by_email(client_email) ||
        Accounts.get_user_by_canonical_email(client_email)

    case client do
      nil -> {:error, :client_not_found}
      client -> invite_client_by_id(professional_id, client.id, message)
    end
  end

  @doc """
  Invite a not-yet-registered person to join Mehungry as this professional's client.

  This is the fallback for `invite_client/3` when the typed email matches no
  existing user. It reuses the managed-client machinery: a login-less `User` is
  created and assigned to the professional (via `create_managed_client/2`), then an
  onboarding email with the `/claim/:token` link is sent to `email`. When the
  recipient claims the account they set their own email + password and land already
  connected as this professional's client.

  `claim_url_fun` is injected by the caller (the web layer) as `fn token -> url end`
  so this core function stays URL-free. The real `email` is used only to send the
  invite — the managed account keeps its synthetic placeholder address.

  Returns `{:ok, user}`, `{:error, :already_registered}` (someone now owns that
  email — caller should invite them normally instead), `{:error, :invalid_email}`,
  `{:error, :email_failed}` (account created but the email could not be sent — the
  professional can resend the claim link from their clients roster), or
  `{:error, changeset}`.
  """
  def onboard_client_by_email(professional_id, email, message, claim_url_fun)
      when is_function(claim_url_fun, 1) do
    trimmed = String.trim(to_string(email))

    cond do
      trimmed == "" ->
        {:error, :invalid_email}

      not is_nil(Accounts.get_user_by_email(trimmed)) or
          not is_nil(Accounts.get_user_by_canonical_email(trimmed)) ->
        {:error, :already_registered}

      true ->
        with {:ok, %{user: user, claim_token: token}} <-
               create_managed_client(professional_id, client_name_from_email(trimmed)),
             {:ok, _email} <-
               Accounts.deliver_client_onboarding_invite(
                 trimmed,
                 professional_display_name(professional_id),
                 claim_url_fun.(token),
                 message
               ) do
          {:ok, user}
        else
          {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
          # Managed account was created but the email bounced/failed to send.
          {:error, _reason} -> {:error, :email_failed}
        end
    end
  end

  # Human-ish display name for a managed client created from only an email — the
  # local part, so the professional recognises the row in their clients roster.
  defp client_name_from_email(email) do
    email |> String.split("@") |> List.first() |> to_string()
  end

  # The name to sign the onboarding email with: the professional's public display
  # name, falling back to their account name.
  defp professional_display_name(professional_id) do
    case get_professional_profile(professional_id) do
      %ProfessionalProfile{display_name: name} when is_binary(name) and name != "" ->
        name

      _ ->
        case Accounts.get_user!(professional_id) do
          %User{name: name} when is_binary(name) and name != "" -> name
          _ -> "Your nutritionist"
        end
    end
  end

  @doc """
  Send an invitation from a professional directly to a registered user by id.

  This is the primary path behind the search-and-pick invite UI, so a
  professional can reach users they couldn't name by email — e.g. Facebook/Google
  logins whose only email is a synthetic `*@facebook.user` placeholder. The
  email-based `invite_client/3` resolves the address and delegates here.
  """
  def invite_client_by_id(professional_id, client_id, message \\ nil)
      when is_integer(client_id) do
    cond do
      client_id == professional_id ->
        {:error, :self_invite}

      is_nil(Repo.get(User, client_id)) ->
        {:error, :client_not_found}

      true ->
        existing =
          Repo.get_by(TutorInvitation, professional_id: professional_id, client_id: client_id)

        cond do
          not is_nil(existing) and existing.status == "pending" ->
            {:error, :already_invited}

          already_client?(professional_id, client_id) ->
            {:error, :already_client}

          not is_nil(existing) ->
            existing
            |> TutorInvitation.changeset(%{status: "pending", message: message})
            |> Repo.update()

          true ->
            %TutorInvitation{}
            |> TutorInvitation.changeset(%{
              professional_id: professional_id,
              client_id: client_id,
              message: message
            })
            |> Repo.insert()
        end
    end
  end

  defp already_client?(professional_id, client_id) do
    Repo.exists?(
      from a in TutorClientAssignment,
        where: a.professional_id == ^professional_id and a.client_id == ^client_id
    )
  end

  @doc """
  Searches registered users a professional can invite, matching on display name,
  profile alias, or exact email. This is the way to find users the email box
  can't reach (OAuth logins without a usable email, since there is no username).

  Deliberately includes users whose only email is a synthetic provider
  placeholder (e.g. `*@facebook.user`) — they are real, invitable logins and the
  whole reason this path exists, since they can't be reached by email. Excludes
  only the professional themselves and managed, unclaimed placeholder accounts
  (`managed_by_professional_id` set — login-less stand-ins that can't accept).
  Each result is a `%{user: user, status: :invitable | :invited | :client}` map
  so the UI can label people already invited or already a client. Requires at
  least 2 chars; returns `[]` otherwise.

  Options: `:limit` (default 10).
  """
  def search_invitable_users(professional_id, query, opts \\ []) when is_binary(query) do
    trimmed = String.trim(query)

    if String.length(trimmed) < 2 do
      []
    else
      limit = Keyword.get(opts, :limit, 10)
      like = "%#{escape_like(trimmed)}%"

      users =
        Repo.all(
          from u in User,
            left_join: p in assoc(u, :user_profile),
            where: u.id != ^professional_id,
            where: is_nil(u.managed_by_professional_id),
            where: ilike(u.name, ^like) or ilike(p.alias, ^like) or u.email == ^trimmed,
            order_by: [asc: u.name],
            limit: ^limit,
            preload: [user_profile: p]
        )

      annotate_invite_status(professional_id, users)
    end
  end

  defp annotate_invite_status(_professional_id, []), do: []

  defp annotate_invite_status(professional_id, users) do
    ids = Enum.map(users, & &1.id)

    invited =
      MapSet.new(
        Repo.all(
          from i in TutorInvitation,
            where:
              i.professional_id == ^professional_id and i.client_id in ^ids and
                i.status == "pending",
            select: i.client_id
        )
      )

    clients =
      MapSet.new(
        Repo.all(
          from a in TutorClientAssignment,
            where: a.professional_id == ^professional_id and a.client_id in ^ids,
            select: a.client_id
        )
      )

    Enum.map(users, fn u ->
      status =
        cond do
          MapSet.member?(clients, u.id) -> :client
          MapSet.member?(invited, u.id) -> :invited
          true -> :invitable
        end

      %{user: u, status: status}
    end)
  end

  defp escape_like(value), do: String.replace(value, ~r/([\\%_])/, "\\\\\\1")

  def get_invitation(id), do: Repo.get(TutorInvitation, id)

  def accept_invitation(invitation_id, client_id) do
    with %TutorInvitation{} = inv <- Repo.get(TutorInvitation, invitation_id),
         true <- inv.client_id == client_id,
         true <- inv.status == "pending",
         {:ok, inv} <- inv |> TutorInvitation.changeset(%{status: "accepted"}) |> Repo.update() do
      # Remove any existing assignment for this client (one nutritionist max)
      Repo.delete_all(from a in TutorClientAssignment, where: a.client_id == ^client_id)

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

  @doc """
  Client-initiated unlink: a client ends their own link to their nutritionist
  (a client has at most one assignment). Returns `{:error, :not_found}` when the
  client has no nutritionist.
  """
  def unassign_nutritionist(client_id) do
    case Repo.get_by(TutorClientAssignment, client_id: client_id) do
      nil -> {:error, :not_found}
      assignment -> Repo.delete(assignment)
    end
  end

  # ── Client ↔ Nutritionist messages ──────────────────────────────────────────────
  #
  # One running conversation per (professional, client) pair. Either party posts;
  # a message is unread for its recipient (the party who is not the sender) while
  # `read_at` is nil. Live updates ride the shared `Mehungry.PubSub` on a
  # per-user topic (mirrors the posts/agent conventions).

  @doc "Subscribe a LiveView to the viewer's message stream (both their threads as client and as professional)."
  def subscribe_to_messages(user_id) do
    Phoenix.PubSub.subscribe(Mehungry.PubSub, message_topic(user_id))
  end

  defp message_topic(user_id), do: "assignment_messages:#{user_id}"

  @doc "All messages in one thread, oldest first."
  def list_messages(professional_id, client_id) do
    Repo.all(
      from m in AssignmentMessage,
        where: m.professional_id == ^professional_id and m.client_id == ^client_id,
        order_by: [asc: m.inserted_at, asc: m.id]
    )
  end

  @doc "Post a message and broadcast it to both parties' topics."
  def send_message(professional_id, client_id, sender_user_id, body) do
    attrs = %{
      professional_id: professional_id,
      client_id: client_id,
      sender_user_id: sender_user_id,
      body: body
    }

    case %AssignmentMessage{} |> AssignmentMessage.changeset(attrs) |> Repo.insert() do
      {:ok, message} ->
        Phoenix.PubSub.broadcast(
          Mehungry.PubSub,
          message_topic(professional_id),
          {:assignment_message, message}
        )

        Phoenix.PubSub.broadcast(
          Mehungry.PubSub,
          message_topic(client_id),
          {:assignment_message, message}
        )

        {:ok, message}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc "Mark every message in the thread that the reader received (did not send) as read. Returns the count updated."
  def mark_thread_read(professional_id, client_id, reader_user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      Repo.update_all(
        from(m in AssignmentMessage,
          where: m.professional_id == ^professional_id and m.client_id == ^client_id,
          where: m.sender_user_id != ^reader_user_id and is_nil(m.read_at)
        ),
        set: [read_at: now]
      )

    count
  end

  @doc "Total unread messages addressed to this user across all their threads (as client or as professional)."
  def count_unread_messages_for(user_id) do
    Repo.one(
      from m in AssignmentMessage,
        where: m.sender_user_id != ^user_id and is_nil(m.read_at),
        where: m.client_id == ^user_id or m.professional_id == ^user_id,
        select: count(m.id)
    )
  end

  @doc "Per-client unread counts for a professional's roster — `%{client_id => count}`."
  def unread_counts_by_client(professional_id) do
    Repo.all(
      from m in AssignmentMessage,
        where: m.professional_id == ^professional_id,
        where: m.sender_user_id != ^professional_id and is_nil(m.read_at),
        group_by: m.client_id,
        select: {m.client_id, count(m.id)}
    )
    |> Map.new()
  end

  @doc """
  Creates a login-less "managed" client account for a professional from just an
  alias, assigns it to them, and returns a claim token.

  The account is a real, pre-confirmed `User` (so it has a calendar and can hold
  meal plans) but has no password and cannot be logged into until the client
  claims it via the returned token. Returns `{:ok, %{user: user, claim_token: token}}`.
  """
  def create_managed_client(professional_id, alias_name) do
    result =
      Repo.transaction(fn ->
        with {:ok, user} <-
               Accounts.create_managed_client(%{
                 name: alias_name,
                 managed_by_professional_id: professional_id
               }),
             {:ok, _assignment} <-
               %TutorClientAssignment{}
               |> TutorClientAssignment.changeset(%{
                 professional_id: professional_id,
                 client_id: user.id
               })
               |> Repo.insert() do
          user
        else
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, user} ->
        {:ok, %{user: user, claim_token: Accounts.build_managed_client_claim_token(user)}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Regenerates (and returns) a fresh claim token for an existing managed client
  owned by `professional_id`. Returns `{:error, :not_found}` if the user is not
  an unclaimed managed client assigned to this professional.
  """
  def regenerate_claim_token(professional_id, client_id) do
    with %TutorClientAssignment{} <- get_assignment(professional_id, client_id),
         user <- Accounts.get_user!(client_id),
         true <- Accounts.managed_unclaimed?(user) do
      {:ok, Accounts.build_managed_client_claim_token(user)}
    else
      _ -> {:error, :not_found}
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

  @doc """
  Appointments between a specific professional and client, scoped so a
  nutritionist only ever sees the appointments they hold with that client (not
  any the client had with a previous nutritionist).
  """
  def list_appointments_for_professional_client(professional_id, client_id) do
    Repo.all(
      from a in Appointment,
        where: a.professional_id == ^professional_id and a.client_id == ^client_id,
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

  @doc "Pending (status `requested`) appointment requests for a professional, soonest first."
  def list_pending_requests(professional_id) do
    Repo.all(
      from a in Appointment,
        where: a.professional_id == ^professional_id and a.status == "requested",
        order_by: [asc: a.scheduled_at],
        preload: [client: :user_profile]
    )
  end

  def get_appointment!(id), do: Repo.get!(Appointment, id)

  @doc """
  Fetch an appointment by id, scoped to its owning professional. Returns `nil`
  when the appointment does not exist or belongs to a different professional —
  so callers can reject cross-tenant mutations instead of acting on another
  nutritionist's rows.
  """
  def get_appointment_for_professional(professional_id, id) do
    Repo.get_by(Appointment, id: id, professional_id: professional_id)
  end

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

  # ── Availability (recurring weekly) ─────────────────────────────────────────────

  def list_availabilities(professional_id) do
    Repo.all(
      from a in ProfessionalAvailability,
        where: a.professional_id == ^professional_id,
        order_by: [asc: a.day_of_week, asc: a.start_time]
    )
  end

  @doc """
  Replace a professional's entire weekly availability grid with `rows`
  (a list of maps with `day_of_week`, `start_time`, `end_time`). Returns
  `{:ok, count}` or `{:error, changeset}` on the first invalid row.
  """
  def replace_availabilities(professional_id, rows) do
    changesets =
      Enum.map(rows, fn row ->
        ProfessionalAvailability.changeset(
          %ProfessionalAvailability{},
          Map.put(row, :professional_id, professional_id)
        )
      end)

    case Enum.find(changesets, &(not &1.valid?)) do
      nil ->
        Repo.transaction(fn ->
          Repo.delete_all(
            from a in ProfessionalAvailability, where: a.professional_id == ^professional_id
          )

          Enum.each(changesets, &Repo.insert!/1)
          length(changesets)
        end)

      invalid ->
        {:error, invalid}
    end
  end

  @doc """
  Bookable appointment slots for a professional between `from_date` and
  `to_date` (inclusive). Slices each weekly availability window into
  `appointment_slot_minutes` slots, drops slots in the past and slots already
  taken by a `requested`/`accepted` appointment. Returns a sorted list of
  `NaiveDateTime`s (second precision).
  """
  def available_slots(professional_id, from_date, to_date) do
    profile = get_professional_profile(professional_id)
    slot_minutes = (profile && profile.appointment_slot_minutes) || 60

    availabilities_by_dow =
      professional_id
      |> list_availabilities()
      |> Enum.group_by(& &1.day_of_week)

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    booked = booked_slots(professional_id, from_date, to_date)

    Date.range(from_date, to_date)
    |> Enum.flat_map(fn date ->
      dow = Date.day_of_week(date, :sunday) - 1

      availabilities_by_dow
      |> Map.get(dow, [])
      |> Enum.flat_map(&window_slots(date, &1, slot_minutes))
    end)
    |> Enum.filter(fn slot ->
      NaiveDateTime.compare(slot, now) == :gt and not MapSet.member?(booked, slot)
    end)
    |> Enum.sort(NaiveDateTime)
  end

  defp booked_slots(professional_id, from_date, to_date) do
    start_dt = NaiveDateTime.new!(from_date, ~T[00:00:00])
    end_dt = NaiveDateTime.new!(to_date, ~T[23:59:59])

    Repo.all(
      from a in Appointment,
        where:
          a.professional_id == ^professional_id and
            a.status in ["requested", "accepted"] and
            a.scheduled_at >= ^start_dt and a.scheduled_at <= ^end_dt,
        select: a.scheduled_at
    )
    |> Enum.map(&NaiveDateTime.truncate(&1, :second))
    |> MapSet.new()
  end

  # Slice a single availability window on `date` into slot-start datetimes.
  defp window_slots(date, %ProfessionalAvailability{start_time: st, end_time: et}, slot_minutes) do
    start_dt = NaiveDateTime.new!(date, st) |> NaiveDateTime.truncate(:second)
    end_dt = NaiveDateTime.new!(date, et) |> NaiveDateTime.truncate(:second)

    Stream.iterate(start_dt, &NaiveDateTime.add(&1, slot_minutes * 60, :second))
    |> Stream.take_while(fn slot_start ->
      NaiveDateTime.compare(NaiveDateTime.add(slot_start, slot_minutes * 60, :second), end_dt) !=
        :gt
    end)
    |> Enum.to_list()
  end

  # ── Booking (public request → nutritionist accept) ──────────────────────────────

  @doc """
  A logged-in visitor requests an appointment at `scheduled_at`. Validates the
  slot is actually open (in `available_slots/3`), then inserts a `requested`
  appointment. `opts` may carry `:title` and `:notes`.
  """
  def request_appointment(professional_id, client_id, %NaiveDateTime{} = scheduled_at, opts \\ []) do
    scheduled_at = NaiveDateTime.truncate(scheduled_at, :second)
    profile = get_professional_profile(professional_id)
    slot_minutes = (profile && profile.appointment_slot_minutes) || 60
    ends_at = NaiveDateTime.add(scheduled_at, slot_minutes * 60, :second)

    if slot_open?(professional_id, scheduled_at) do
      %{
        professional_id: professional_id,
        client_id: client_id,
        scheduled_at: scheduled_at,
        ends_at: ends_at,
        title: opts[:title] || "Consultation",
        notes: opts[:notes],
        status: "requested"
      }
      |> create_appointment()
      |> case do
        # The partial unique index is the final arbiter against a concurrent
        # request that also passed `slot_open?` — surface it as slot_unavailable.
        {:error, %Ecto.Changeset{errors: errors} = changeset} ->
          if Keyword.has_key?(errors, :scheduled_at),
            do: {:error, :slot_unavailable},
            else: {:error, changeset}

        ok ->
          ok
      end
    else
      {:error, :slot_unavailable}
    end
  end

  defp slot_open?(professional_id, scheduled_at) do
    date = NaiveDateTime.to_date(scheduled_at)

    professional_id
    |> available_slots(date, date)
    |> Enum.any?(&(NaiveDateTime.compare(&1, scheduled_at) == :eq))
  end

  @doc """
  Nutritionist accepts a requested appointment (optionally attaching a
  `:meeting_url`). Returns `{:ok, appointment}` with professional+client
  preloaded so callers can notify.
  """
  def accept_appointment(%Appointment{} = appointment, opts \\ []) do
    attrs = %{status: "accepted"}

    attrs =
      if opts[:meeting_url], do: Map.put(attrs, :meeting_url, opts[:meeting_url]), else: attrs

    appointment
    |> Appointment.status_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, Repo.preload(updated, [:professional, :client])}
      error -> error
    end
  end

  def decline_appointment(%Appointment{} = appointment) do
    appointment
    |> Appointment.status_changeset(%{status: "declined"})
    |> Repo.update()
  end

  def cancel_appointment(%Appointment{} = appointment) do
    appointment
    |> Appointment.status_changeset(%{status: "cancelled"})
    |> Repo.update()
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

  # ── Articles ───────────────────────────────────────────────────────────────────

  @article_full_preload [
    paragraphs: [references: [:study, :species, :compound, :condition]]
  ]

  @doc "All articles authored by a profile (newest first), for the author's list view."
  def list_articles_for_profile(profile_id) do
    Repo.all(
      from a in Article,
        where: a.professional_profile_id == ^profile_id,
        order_by: [desc: a.updated_at]
    )
  end

  @doc "Published articles for a profile (newest published first), for the public profile."
  def list_published_articles_for_profile(profile_id) do
    Repo.all(
      from a in Article,
        where: a.professional_profile_id == ^profile_id and a.status == "published",
        order_by: [desc: a.published_at]
    )
  end

  @doc "Fetch an article by id with paragraphs + references (+ entities) preloaded."
  def get_article!(id) do
    Article
    |> Repo.get!(id)
    |> Repo.preload(@article_full_preload)
  end

  def get_article(id) do
    case Repo.get(Article, id) do
      nil -> nil
      article -> Repo.preload(article, @article_full_preload)
    end
  end

  @doc """
  Fetch a **published** article by its slug, fully preloaded (paragraphs +
  references + entities + author profile/user), or `nil`. Drafts never resolve.
  """
  def get_published_article_by_slug(slug) do
    Article
    |> where([a], a.slug == ^slug and a.status == "published")
    |> preload(^([professional_profile: :user] ++ @article_full_preload))
    |> Repo.one()
  end

  def create_article(attrs) do
    %Article{}
    |> Article.changeset(attrs)
    |> ensure_unique_article_slug(nil)
    |> Repo.insert()
  end

  def update_article(%Article{} = article, attrs) do
    article
    |> Article.changeset(attrs)
    |> maybe_reslug(article)
    |> ensure_unique_article_slug(article.id)
    |> Repo.update()
  end

  # While an article is still a draft its slug tracks the title (so the placeholder
  # "untitled-article" slug is replaced once a real title is set). Once published,
  # the slug is frozen so the public URL stays stable.
  defp maybe_reslug(changeset, %Article{status: "draft"}) do
    case Ecto.Changeset.get_change(changeset, :title) do
      nil -> changeset
      title -> Ecto.Changeset.put_change(changeset, :slug, ProfessionalProfile.slugify(title))
    end
  end

  defp maybe_reslug(changeset, _article), do: changeset

  def delete_article(%Article{} = article), do: Repo.delete(article)

  def change_article(%Article{} = article, attrs \\ %{}), do: Article.changeset(article, attrs)

  @doc "Publish an article (sets status + published_at, keeping an existing published_at stable)."
  def publish_article(%Article{} = article) do
    published_at = article.published_at || DateTime.truncate(DateTime.utc_now(), :second)

    article
    |> Article.changeset(%{status: "published", published_at: published_at})
    |> Repo.update()
  end

  @doc "Return an article to draft (hides it from the public profile; keeps published_at)."
  def unpublish_article(%Article{} = article) do
    article
    |> Article.changeset(%{status: "draft"})
    |> Repo.update()
  end

  # Disambiguate a freshly-generated article slug against existing articles.
  defp ensure_unique_article_slug(changeset, self_id) do
    case Ecto.Changeset.get_change(changeset, :slug) do
      nil -> changeset
      base -> Ecto.Changeset.put_change(changeset, :slug, unique_article_slug(base, self_id, 0))
    end
  end

  defp unique_article_slug(base, self_id, n) do
    candidate = if n == 0, do: base, else: "#{base}-#{n}"

    query = from(a in Article, where: a.slug == ^candidate)
    query = if self_id, do: from(a in query, where: a.id != ^self_id), else: query

    if Repo.exists?(query), do: unique_article_slug(base, self_id, n + 1), else: candidate
  end

  # ── Article paragraphs ──────────────────────────────────────────────────────────

  @doc "Create a paragraph, appended after the article's current last paragraph."
  def create_paragraph(article_id, attrs \\ %{}) do
    next_position =
      Repo.one(
        from p in ArticleParagraph,
          where: p.article_id == ^article_id,
          select: coalesce(max(p.position), -1)
      ) + 1

    %ArticleParagraph{}
    |> ArticleParagraph.changeset(
      attrs
      |> Map.put("article_id", article_id)
      |> Map.put_new("position", next_position)
    )
    |> Repo.insert()
  end

  def get_paragraph!(id) do
    ArticleParagraph
    |> Repo.get!(id)
    |> Repo.preload(references: [:study, :species, :compound, :condition])
  end

  def update_paragraph(%ArticleParagraph{} = paragraph, attrs) do
    paragraph
    |> ArticleParagraph.changeset(attrs)
    |> Repo.update()
  end

  def delete_paragraph(%ArticleParagraph{} = paragraph), do: Repo.delete(paragraph)

  @doc "Set `position` on each paragraph to its index in `ordered_ids`."
  def reorder_paragraphs(article_id, ordered_ids) do
    Repo.transaction(fn ->
      ordered_ids
      |> Enum.with_index()
      |> Enum.each(fn {id, index} ->
        Repo.update_all(
          from(p in ArticleParagraph, where: p.id == ^id and p.article_id == ^article_id),
          set: [position: index]
        )
      end)
    end)
  end

  # ── Article references ──────────────────────────────────────────────────────────

  @doc "Attach a reference to a paragraph. `attrs` carries reference_type + the typed FK."
  def add_reference(paragraph, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.put("article_id", paragraph.article_id)
      |> Map.put("paragraph_id", paragraph.id)

    %ArticleReference{}
    |> ArticleReference.changeset(attrs)
    |> Repo.insert()
  end

  def delete_reference(%ArticleReference{} = reference), do: Repo.delete(reference)

  def get_reference!(id), do: Repo.get!(ArticleReference, id)

  def list_references_for_paragraph(paragraph_id) do
    Repo.all(
      from r in ArticleReference,
        where: r.paragraph_id == ^paragraph_id,
        preload: [:study, :species, :compound, :condition]
    )
  end

  # ── Client records (ProfessionalClient) ─────────────────────────────────────────

  @doc "Lists a professional's client records, most recently created first."
  def list_client_records(professional_id) do
    Repo.all(
      from c in ProfessionalClient,
        where: c.professional_id == ^professional_id,
        order_by: [desc: c.inserted_at]
    )
  end

  @doc "Fetches one client record, scoped to the owning professional. Raises if not found."
  def get_client_record!(professional_id, id) do
    Repo.get_by!(ProfessionalClient, id: id, professional_id: professional_id)
  end

  @doc """
  The professional's client record for a given platform user, or nil. Returns the
  most recently created one if several exist (e.g. repeated CSV imports).
  """
  def get_client_record_by_user(professional_id, user_id) do
    Repo.one(
      from c in ProfessionalClient,
        where: c.professional_id == ^professional_id and c.user_id == ^user_id,
        order_by: [desc: c.inserted_at],
        limit: 1
    )
  end

  @doc """
  Maps every platform user the professional has a client record for to that
  record — `%{user_id => %ProfessionalClient{}}`. Most recently created wins on
  duplicates (e.g. repeated CSV imports), matching `get_client_record_by_user/2`.
  Batched so a client roster can show per-client file status without N+1 queries.
  """
  def records_by_user_id(professional_id) do
    from(c in ProfessionalClient,
      where: c.professional_id == ^professional_id,
      order_by: [desc: c.inserted_at, desc: c.id]
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn record, acc -> Map.put_new(acc, record.user_id, record) end)
  end

  def create_client_record(attrs) do
    %ProfessionalClient{}
    |> ProfessionalClient.changeset(attrs)
    |> Repo.insert()
  end

  def update_client_record(%ProfessionalClient{} = client, attrs) do
    client
    |> ProfessionalClient.changeset(attrs)
    |> Repo.update()
  end

  def delete_client_record(%ProfessionalClient{} = client), do: Repo.delete(client)

  def change_client_record(%ProfessionalClient{} = client, attrs \\ %{}) do
    ProfessionalClient.changeset(client, attrs)
  end

  # ── Client conditions (structured client↔condition link) ────────────────────────

  @doc """
  The existing `Health.Condition`s linked to a client record, ordered by name.
  """
  def list_client_conditions(professional_client_id) do
    Repo.all(
      from c in Condition,
        join: cc in ClientCondition,
        on: cc.condition_id == c.id,
        where: cc.professional_client_id == ^professional_client_id,
        order_by: [asc: c.name]
    )
  end

  @doc """
  Links an existing condition to a client record. Idempotent — linking the same
  condition twice is a no-op (the unique pair constraint is ignored). Only an
  existing `Health.Condition` can be linked; this never creates a condition.
  """
  def add_client_condition(professional_client_id, condition_id) do
    %ClientCondition{}
    |> ClientCondition.changeset(%{
      professional_client_id: professional_client_id,
      condition_id: condition_id
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:professional_client_id, :condition_id]
    )
  end

  @doc "Unlinks a condition from a client record. No-op if it wasn't linked."
  def remove_client_condition(professional_client_id, condition_id) do
    {count, _} =
      Repo.delete_all(
        from cc in ClientCondition,
          where:
            cc.professional_client_id == ^professional_client_id and
              cc.condition_id == ^condition_id
      )

    {:ok, count}
  end

  # ── Client intakes ──────────────────────────────────────────────────────────────

  @doc "The most recent intake for a client, or nil."
  def get_latest_intake(professional_client_id) do
    Repo.one(
      from i in ClientIntake,
        where: i.professional_client_id == ^professional_client_id,
        order_by: [desc_nulls_last: i.assessed_on, desc: i.inserted_at],
        limit: 1
    )
  end

  def list_intakes(professional_client_id) do
    Repo.all(
      from i in ClientIntake,
        where: i.professional_client_id == ^professional_client_id,
        order_by: [desc_nulls_last: i.assessed_on, desc: i.inserted_at]
    )
  end

  def create_intake(attrs) do
    %ClientIntake{}
    |> ClientIntake.changeset(attrs)
    |> Repo.insert()
  end

  def update_intake(%ClientIntake{} = intake, attrs) do
    intake
    |> ClientIntake.changeset(attrs)
    |> Repo.update()
  end

  def change_intake(%ClientIntake{} = intake, attrs \\ %{}) do
    ClientIntake.changeset(intake, attrs)
  end

  # ── Consultation notes ──────────────────────────────────────────────────────────

  @doc "Lists a client's consultation notes, oldest visit first (chronological timeline)."
  def list_consultation_notes(professional_client_id) do
    Repo.all(
      from n in ConsultationNote,
        where: n.professional_client_id == ^professional_client_id,
        order_by: [asc_nulls_last: n.visit_date, asc: n.visit_number, asc: n.inserted_at],
        preload: [:appointment]
    )
  end

  @doc """
  A client's dated weight points, merged from both sources — each `ClientIntake`
  (`assessed_on`) and each `ConsultationNote` (`visit_date`) that carries a
  `weight_kg`. Rows missing a weight or a date are dropped. Returns
  `[%{date: ~D[...], weight_kg: float, source: :intake | :visit}, ...]` sorted
  ascending by date, suitable for plotting a weight trend.
  """
  def weight_history(professional_client_id) do
    intakes =
      professional_client_id
      |> list_intakes()
      |> Enum.filter(&(&1.weight_kg && &1.assessed_on))
      |> Enum.map(&%{date: &1.assessed_on, weight_kg: &1.weight_kg, source: :intake})

    visits =
      professional_client_id
      |> list_consultation_notes()
      |> Enum.filter(&(&1.weight_kg && &1.visit_date))
      |> Enum.map(&%{date: &1.visit_date, weight_kg: &1.weight_kg, source: :visit})

    Enum.sort_by(intakes ++ visits, & &1.date, Date)
  end

  def create_consultation_note(attrs) do
    %ConsultationNote{}
    |> ConsultationNote.changeset(attrs)
    |> Repo.insert()
  end

  def update_consultation_note(%ConsultationNote{} = note, attrs) do
    note
    |> ConsultationNote.changeset(attrs)
    |> Repo.update()
  end

  def delete_consultation_note(%ConsultationNote{} = note), do: Repo.delete(note)

  def change_consultation_note(%ConsultationNote{} = note, attrs \\ %{}) do
    ConsultationNote.changeset(note, attrs)
  end

  @doc """
  Imports a dietary-history CSV export (Google Sheets format) into a new client
  record with its intake and consultation notes, all owned by `professional_id`.

  `opts` must include a `:user_id` — a record is never headless (see
  `DietaryHistory.Importer.import_csv/3`). Delegates to `DietaryHistory.Importer`.
  """
  def import_dietary_history(professional_id, csv_content, opts \\ []) do
    DietaryHistory.Importer.import_csv(professional_id, csv_content, opts)
  end
end
