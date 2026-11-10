defmodule Mehungry.Professionals do
  import Ecto.Query
  alias Mehungry.Repo
  alias Mehungry.Accounts
  alias Mehungry.Accounts.User

  alias Mehungry.Professionals.{
    ProfessionalProfile,
    ProfessionalAvailability,
    ProfessionalService,
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
    AssignmentMessage,
    AppointmentPayment,
    GoogleAccount,
    CalendarBusy,
    Anthropometrics,
    ClinicalConsent
  }

  alias Mehungry.Professionals.DietaryHistory
  alias Mehungry.Health.Condition
  alias Mehungry.Billing.StripeHandler
  alias Mehungry.ObanWorkers.AppointmentCalendarSyncWorker
  alias Mehungry.Progress

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

  @doc """
  Webhook helper (Accounts v2): re-fetch the connected account's live capability
  status and persist whether it can be charged onto. Used by the thin
  `v2.core.account[...]` events, which carry only the account id — so we read the
  authoritative status from Stripe rather than an inline payload.
  """
  def sync_stripe_account_status(account_id) when is_binary(account_id) do
    with profile when not is_nil(profile) <- get_profile_by_stripe_account(account_id),
         {:ok, %{charges_enabled: enabled}} <- payment_client().get_connect_account(account_id) do
      update_professional_stripe(profile, %{stripe_charges_enabled: enabled})
    else
      nil -> {:error, :not_found}
      error -> error
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
         true <- inv.status == "pending" do
      # Transactional so the assignment, the invitation state, and the client's
      # nutritionist-aligned progress period can never get out of sync. Note a
      # nutritionist *switch* lands here too (the old assignment is replaced
      # directly, without remove_client/unassign) — the Progress hook closes
      # whatever period was active, so the switch is covered by this one call.
      Repo.transaction(fn ->
        with {:ok, inv} <-
               inv |> TutorInvitation.changeset(%{status: "accepted"}) |> Repo.update(),
             # Remove any existing assignment for this client (one nutritionist max)
             _ <-
               Repo.delete_all(from a in TutorClientAssignment, where: a.client_id == ^client_id),
             {:ok, assignment} <-
               %TutorClientAssignment{}
               |> TutorClientAssignment.changeset(%{
                 professional_id: inv.professional_id,
                 client_id: client_id
               })
               |> Repo.insert(),
             {:ok, _period} <-
               Progress.on_nutritionist_assigned(client_id, inv.professional_id) do
          assignment
        else
          {:error, cs} -> Repo.rollback(cs)
        end
      end)
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
      nil ->
        {:error, :not_found}

      assignment ->
        with {:ok, deleted} <- Repo.delete(assignment) do
          # Close the client's nutritionist-aligned progress period and resume
          # self-tracking (no-op when they never had one).
          Progress.on_nutritionist_unassigned(client_id)
          {:ok, deleted}
        end
    end
  end

  @doc """
  Client-initiated unlink: a client ends their own link to their nutritionist
  (a client has at most one assignment). Returns `{:error, :not_found}` when the
  client has no nutritionist.
  """
  def unassign_nutritionist(client_id) do
    case Repo.get_by(TutorClientAssignment, client_id: client_id) do
      nil ->
        {:error, :not_found}

      assignment ->
        with {:ok, deleted} <- Repo.delete(assignment) do
          # Close the aligned progress period, reopen self-tracking (see
          # Progress.on_nutritionist_unassigned/1; no-op without one).
          Progress.on_nutritionist_unassigned(client_id)
          {:ok, deleted}
        end
    end
  end

  # ── Clinical-data consent (GDPR Art. 9) ──────────────────────────────────────────
  #
  # Explicit consent to process a client's special-category health data (onboarding
  # answers + "My progress" measurements). Recorded per user; append-only with a
  # `withdrawn_at` tombstone so the grant/withdrawal history is auditable.

  # The consent copy/version the server currently requires. Bump it to force a
  # re-consent when the consent wording materially changes; the mobile client
  # mirrors it as `CLINICAL_CONSENT_VERSION`.
  @clinical_consent_version "2026-11"

  @doc "The consent version the server currently requires."
  def clinical_consent_version, do: @clinical_consent_version

  @doc """
  The user's **active** clinical-data consent at the current version, or `nil`
  when none is on record / it was withdrawn / it is stale (an older version).
  """
  def current_clinical_consent(user_id) do
    Repo.one(
      from c in ClinicalConsent,
        where:
          c.user_id == ^user_id and c.version == ^@clinical_consent_version and
            is_nil(c.withdrawn_at),
        order_by: [desc: c.inserted_at],
        limit: 1
    )
  end

  @doc "True when the user has an active consent at the current version."
  def clinical_consent_granted?(user_id), do: not is_nil(current_clinical_consent(user_id))

  @doc """
  Record explicit consent at `version`. Idempotent — returns the existing active
  consent when one is already on record rather than inserting a duplicate.
  Returns `{:error, :consent_version_mismatch}` when `version` is not the current
  server version (a stale client that should be prompted to update).
  """
  def grant_clinical_consent(user_id, version)

  def grant_clinical_consent(user_id, @clinical_consent_version = version) do
    case current_clinical_consent(user_id) do
      nil ->
        %ClinicalConsent{}
        |> ClinicalConsent.changeset(%{user_id: user_id, version: version})
        |> Repo.insert()

      consent ->
        {:ok, consent}
    end
  end

  def grant_clinical_consent(_user_id, _version), do: {:error, :consent_version_mismatch}

  @doc """
  Withdraw the user's consent (Art. 7(3) — as easy as giving it) by stamping
  `withdrawn_at` on every still-active row. Idempotent: `{:ok, count}` even when
  nothing was active. Does not delete measurements the nutritionist already
  recorded — it only re-gates the client's in-app clinical surface.
  """
  def withdraw_clinical_consent(user_id) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    {count, _} =
      Repo.update_all(
        from(c in ClinicalConsent, where: c.user_id == ^user_id and is_nil(c.withdrawn_at)),
        set: [withdrawn_at: now, updated_at: now]
      )

    {:ok, count}
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

  @doc "Unread messages in one thread that `reader_user_id` received (did not send)."
  def count_unread_in_thread(professional_id, client_id, reader_user_id) do
    Repo.one(
      from m in AssignmentMessage,
        where: m.professional_id == ^professional_id and m.client_id == ^client_id,
        where: m.sender_user_id != ^reader_user_id and is_nil(m.read_at),
        select: count(m.id)
    )
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

  Deliberately does **not** fire `Progress.on_nutritionist_assigned/2`: a
  login-less managed account has never self-tracked, so opening a
  nutritionist-aligned progress period would only create a phantom journal.
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

  # ── Professional Services (session + package pricing, free intro) ────────────────

  @doc "All services for a nutritionist, intro first, then by `position`."
  def list_services(professional_id) do
    ProfessionalService
    |> where([s], s.professional_id == ^professional_id)
    |> Repo.all()
    |> sort_services()
  end

  @doc "Active services only (intro first, then by position) — for the public profile/booking."
  def list_active_services(professional_id) do
    ProfessionalService
    |> where([s], s.professional_id == ^professional_id and s.active == true)
    |> Repo.all()
    |> sort_services()
  end

  def get_service!(id), do: Repo.get!(ProfessionalService, id)

  @doc "Fetch a service scoped to its owning nutritionist (nil on cross-tenant access)."
  def get_service_for_professional(professional_id, id) do
    Repo.get_by(ProfessionalService, id: id, professional_id: professional_id)
  end

  def create_service(attrs) do
    %ProfessionalService{}
    |> ProfessionalService.changeset(attrs)
    |> Repo.insert()
  end

  def update_service(%ProfessionalService{} = service, attrs) do
    service
    |> ProfessionalService.changeset(attrs)
    |> Repo.update()
  end

  @doc "Soft-hide a service (keeps historical appointments valid); the intro can't be hidden."
  def archive_service(%ProfessionalService{kind: "intro"} = service), do: {:ok, service}

  def archive_service(%ProfessionalService{} = service) do
    update_service(service, %{active: false})
  end

  @doc "Permanently delete a service; the mandatory intro can't be deleted."
  def delete_service(%ProfessionalService{kind: "intro"}), do: {:error, :intro_undeletable}
  def delete_service(%ProfessionalService{} = service), do: Repo.delete(service)

  def change_service(%ProfessionalService{} = service, attrs \\ %{}) do
    ProfessionalService.changeset(service, attrs)
  end

  @doc """
  Return the nutritionist's free intro service, lazily seeding the locked row if
  it doesn't exist yet. Idempotent — safe to call on every Payments-page load.
  The partial unique index guarantees at most one intro per professional.
  """
  def ensure_intro_service(professional_id) do
    case Repo.get_by(ProfessionalService, professional_id: professional_id, kind: "intro") do
      %ProfessionalService{} = intro ->
        {:ok, intro}

      nil ->
        create_service(%{
          professional_id: professional_id,
          kind: "intro",
          name: "Free 15-minute intro",
          description: "A short no-cost call to see if we're a good fit.",
          position: 0
        })
    end
  end

  # Intro always first, then by stored position (stable, DB-agnostic ordering).
  defp sort_services(services) do
    Enum.sort_by(services, fn s -> {s.kind != "intro", s.position} end)
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
        preload: [:payment, :service, professional: :user_profile]
    )
  end

  @doc """
  Fetch an appointment scoped to its owning client (nil cross-tenant), with its
  payment and service preloaded (for the client-facing serializers).
  """
  def get_appointment_for_client(client_id, id) do
    case Repo.get_by(Appointment, id: id, client_id: client_id) do
      nil -> nil
      appointment -> Repo.preload(appointment, [:payment, :service])
    end
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

  def get_appointment(id), do: Repo.get(Appointment, id)

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
    |> case do
      {:ok, updated} ->
        # Re-push an already-synced event so a reschedule/edit reaches Google.
        if updated.google_event_id, do: AppointmentCalendarSyncWorker.enqueue(:upsert, updated.id)
        {:ok, updated}

      error ->
        error
    end
  end

  def delete_appointment(%Appointment{} = appointment) do
    if appointment.google_event_id,
      do: AppointmentCalendarSyncWorker.enqueue(:delete, appointment.id)

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
  **UTC** `NaiveDateTime`s (second precision) — the availability windows are the
  professional's local wall-clock, converted to the canonical stored UTC.
  """
  def available_slots(professional_id, from_date, to_date) do
    profile = get_professional_profile(professional_id)
    slot_minutes = (profile && profile.appointment_slot_minutes) || 60
    tz = Mehungry.Time.tz(profile)

    availabilities_by_dow =
      professional_id
      |> list_availabilities()
      |> Enum.group_by(& &1.day_of_week)

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    booked = booked_intervals(professional_id, from_date, to_date, slot_minutes)
    busy = busy_intervals(professional_id, from_date, to_date)

    Date.range(from_date, to_date)
    |> Enum.flat_map(fn date ->
      dow = Date.day_of_week(date, :sunday) - 1

      availabilities_by_dow
      |> Map.get(dow, [])
      |> Enum.flat_map(&window_slots(date, &1, slot_minutes, tz))
    end)
    |> Enum.filter(fn slot ->
      NaiveDateTime.compare(slot, now) == :gt and
        not slot_overlaps?(slot, slot_minutes, booked) and
        not slot_overlaps?(slot, slot_minutes, busy)
    end)
    |> Enum.sort(NaiveDateTime)
  end

  # Cached Google busy intervals ({start_naive, end_naive}, UTC) within the
  # window, so a slot that overlaps the nutritionist's personal calendar is never
  # offered. Window padded ±1 day because UTC slots for a local date can fall on
  # the adjacent UTC date near midnight.
  defp busy_intervals(professional_id, from_date, to_date) do
    start_naive = NaiveDateTime.new!(Date.add(from_date, -1), ~T[00:00:00])
    end_naive = NaiveDateTime.new!(Date.add(to_date, 1), ~T[23:59:59])

    professional_id
    |> list_calendar_busy(start_naive, end_naive)
    |> Enum.map(fn b ->
      {DateTime.to_naive(b.starts_at), DateTime.to_naive(b.ends_at)}
    end)
  end

  # True when the candidate slot [slot_start, slot_start + slot_minutes) overlaps
  # any {start, end} interval in the list. Used for both existing appointments and
  # Google busy times so a slot is blocked whenever it *overlaps* a commitment —
  # not only when it shares its exact start (the old exact-equality check let an
  # off-grid or differently-sized appointment leave overlapping slots bookable).
  defp slot_overlaps?(slot_start, slot_minutes, intervals) do
    slot_end = NaiveDateTime.add(slot_start, slot_minutes * 60, :second)

    Enum.any?(intervals, fn {int_start, int_end} ->
      NaiveDateTime.compare(slot_start, int_end) == :lt and
        NaiveDateTime.compare(slot_end, int_start) == :gt
    end)
  end

  # Active appointments as {start, end} intervals. Padded ±1 day: stored
  # scheduled_at is UTC, so a slot for a local date near midnight can land on the
  # adjacent UTC date. A missing ends_at is coalesced to one slot after the start.
  defp booked_intervals(professional_id, from_date, to_date, slot_minutes) do
    start_dt = NaiveDateTime.new!(Date.add(from_date, -1), ~T[00:00:00])
    end_dt = NaiveDateTime.new!(Date.add(to_date, 1), ~T[23:59:59])

    Repo.all(
      from a in Appointment,
        where:
          a.professional_id == ^professional_id and
            a.status in ["requested", "accepted"] and
            a.scheduled_at >= ^start_dt and a.scheduled_at <= ^end_dt,
        select: {a.scheduled_at, a.ends_at}
    )
    |> Enum.map(fn {starts_at, ends_at} ->
      starts_at = NaiveDateTime.truncate(starts_at, :second)

      ends_at =
        if ends_at,
          do: NaiveDateTime.truncate(ends_at, :second),
          else: NaiveDateTime.add(starts_at, slot_minutes * 60, :second)

      {starts_at, ends_at}
    end)
  end

  # Slice a single availability window on `date` into slot-start datetimes. The
  # window's start/end are the professional's local wall-clock, so iterate in
  # local time and convert each kept start to the canonical UTC the rest of the
  # engine (booked set, busy intervals, storage) works in.
  defp window_slots(
         date,
         %ProfessionalAvailability{start_time: st, end_time: et},
         slot_minutes,
         tz
       ) do
    start_dt = NaiveDateTime.new!(date, st) |> NaiveDateTime.truncate(:second)
    end_dt = NaiveDateTime.new!(date, et) |> NaiveDateTime.truncate(:second)

    Stream.iterate(start_dt, &NaiveDateTime.add(&1, slot_minutes * 60, :second))
    |> Stream.take_while(fn slot_start ->
      NaiveDateTime.compare(NaiveDateTime.add(slot_start, slot_minutes * 60, :second), end_dt) !=
        :gt
    end)
    |> Enum.map(&Mehungry.Time.to_utc(&1, tz))
  end

  # ── Google Calendar integration ─────────────────────────────────────────────────

  @doc "The connected Google Calendar account for a nutritionist, or nil."
  def get_google_account(professional_id) do
    Repo.get_by(GoogleAccount, professional_id: professional_id)
  end

  @doc "All connected Google Calendar accounts (for the busy-import sweep)."
  def list_google_accounts do
    Repo.all(GoogleAccount)
  end

  @doc "Whether a nutritionist has connected their Google Calendar."
  def google_calendar_connected?(professional_id) do
    not is_nil(get_google_account(professional_id))
  end

  @doc """
  Upsert a nutritionist's Google Calendar connection from an OAuth token
  response map (`"access_token"`, `"refresh_token"`, `"expires_in"`, `"scope"`).
  Preserves an existing `refresh_token` if Google omits one on reconsent.
  """
  def connect_google_calendar(professional_id, token_response) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    existing = get_google_account(professional_id)

    attrs =
      token_response
      |> GoogleAccount.token_attrs(now)
      |> Map.put("professional_id", professional_id)
      |> Map.put("connected_at", (existing && existing.connected_at) || now)

    (existing || %GoogleAccount{})
    |> GoogleAccount.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc "Persist updated token/sync columns on a Google account."
  def update_google_account(%GoogleAccount{} = account, attrs) do
    account
    |> GoogleAccount.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Disconnect a nutritionist's Google Calendar — removes the stored tokens and
  their cached busy intervals. Accepted appointments fall back to the manual
  `meeting_url`.
  """
  def disconnect_google_calendar(professional_id) do
    Repo.transaction(fn ->
      Repo.delete_all(from b in CalendarBusy, where: b.professional_id == ^professional_id)
      Repo.delete_all(from g in GoogleAccount, where: g.professional_id == ^professional_id)
      :ok
    end)
  end

  @doc """
  Replace a professional's entire cached busy-interval set with `intervals`
  (a list of `%{starts_at, ends_at}` with UTC `DateTime`s). Returns
  `{:ok, count}`.
  """
  def replace_calendar_busy(professional_id, intervals) do
    rows =
      Enum.map(intervals, fn %{starts_at: s, ends_at: e} ->
        CalendarBusy.changeset(%CalendarBusy{}, %{
          professional_id: professional_id,
          starts_at: s,
          ends_at: e
        })
      end)

    Repo.transaction(fn ->
      Repo.delete_all(from b in CalendarBusy, where: b.professional_id == ^professional_id)
      Enum.each(rows, &Repo.insert!/1)
      length(rows)
    end)
  end

  @doc """
  Cached Google busy intervals for a professional overlapping a datetime window
  (`NaiveDateTime`s, interpreted as UTC). Used by the slot engine and day view.
  """
  def list_calendar_busy(professional_id, from_naive, to_naive) do
    start_dt = to_utc(from_naive)
    end_dt = to_utc(to_naive)

    Repo.all(
      from b in CalendarBusy,
        where:
          b.professional_id == ^professional_id and
            b.starts_at < ^end_dt and b.ends_at > ^start_dt,
        order_by: [asc: b.starts_at]
    )
  end

  defp to_utc(%NaiveDateTime{} = naive), do: DateTime.from_naive!(naive, "Etc/UTC")
  defp to_utc(%DateTime{} = dt), do: dt

  @doc "Attach the pushed Google event id (and optionally meeting_url) to an appointment."
  def put_appointment_google_event(%Appointment{} = appointment, event_id, meeting_url \\ nil) do
    attrs = %{google_event_id: event_id}
    attrs = if meeting_url, do: Map.put(attrs, :meeting_url, meeting_url), else: attrs

    appointment
    |> Appointment.changeset(attrs)
    |> Repo.update()
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
    service = load_bookable_service(professional_id, opts[:professional_service_id])

    if slot_open?(professional_id, scheduled_at) do
      %{
        professional_id: professional_id,
        client_id: client_id,
        professional_service_id: service && service.id,
        scheduled_at: scheduled_at,
        ends_at: ends_at,
        title: opts[:title] || (service && service.name) || "Consultation",
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

        {:ok, appointment} ->
          maybe_start_payment(appointment, profile, service, client_id, opts)
      end
    else
      {:error, :slot_unavailable}
    end
  end

  # Only accept a service that belongs to this professional; nil otherwise.
  defp load_bookable_service(_professional_id, nil), do: nil

  defp load_bookable_service(professional_id, service_id),
    do: get_service_for_professional(professional_id, service_id)

  # When the profile is payable, the chosen service is paid (price > 0), the
  # flag is on, and the caller wired success/cancel URLs: create the payment
  # record + a manual-capture Checkout Session and hand back the redirect URL so
  # the caller can send the client to Stripe. A free intro / £0 service, a
  # non-payable profile, or the flag being off → request-only (`{:ok, appt}`).
  #
  # SHADOWED: while `:consultation_payments_enabled` is false the whole charge
  # flow is skipped and every booking is request-only.
  defp maybe_start_payment(appointment, profile, service, client_id, opts) do
    success_url = opts[:success_url]
    cancel_url = opts[:cancel_url]

    if consultation_payments_enabled?() and ProfessionalProfile.payable?(profile) and
         chargeable_service?(service) and is_binary(success_url) and is_binary(cancel_url) do
      amount = service.price_cents
      currency = service.currency || "eur"
      fee = platform_fee_cents(amount)
      vat = fee_vat_cents(fee, profile)
      client = client_id && Repo.get(User, client_id)

      {:ok, _payment} =
        create_appointment_payment(%{
          appointment_id: appointment.id,
          professional_id: profile.user_id,
          client_id: client_id,
          professional_service_id: service.id,
          amount_cents: amount,
          currency: currency,
          platform_fee_cents: fee,
          fee_vat_cents: vat,
          status: "pending"
        })

      checkout_opts = [
        appointment_id: appointment.id,
        destination_account: profile.stripe_connect_account_id,
        customer_email: client && client.email,
        amount_cents: amount,
        currency: currency,
        application_fee_cents: fee,
        product_name: appointment.title,
        success_url: success_url,
        cancel_url: cancel_url
      ]

      case payment_client().create_consultation_checkout(checkout_opts) do
        {:ok, %{url: url, session_id: session_id}} ->
          update_appointment_payment(get_payment_for_appointment(appointment.id), %{
            stripe_checkout_session_id: session_id
          })

          {:ok, appointment, url}

        {:error, reason} ->
          {:error, {:payment_setup_failed, reason}}
      end
    else
      {:ok, appointment}
    end
  end

  defp chargeable_service?(%ProfessionalService{kind: "intro"}), do: false

  defp chargeable_service?(%ProfessionalService{price_cents: cents})
       when is_integer(cents) and cents > 0,
       do: true

  defp chargeable_service?(_), do: false

  defp slot_open?(professional_id, scheduled_at) do
    # scheduled_at is UTC; the local availability date that produced it can be the
    # UTC date ±1 (offset near midnight), so widen the regenerated range.
    date = NaiveDateTime.to_date(scheduled_at)

    professional_id
    |> available_slots(Date.add(date, -1), Date.add(date, 1))
    |> Enum.any?(&(NaiveDateTime.compare(&1, scheduled_at) == :eq))
  end

  @doc """
  Nutritionist accepts a requested appointment (optionally attaching a
  `:meeting_url`). If the booking was paid, the authorized card hold is
  **captured** first — acceptance only proceeds if capture succeeds, so an
  expired/failed hold can't be accepted. Returns `{:ok, appointment}` with
  professional+client preloaded so callers can notify.
  """
  def accept_appointment(%Appointment{} = appointment, opts \\ []) do
    case get_payment_for_appointment(appointment.id) do
      nil ->
        do_accept(appointment, opts)

      %AppointmentPayment{status: "paid"} ->
        # Already captured (e.g. a retry after a transient error) — just accept.
        do_accept(appointment, opts)

      %AppointmentPayment{status: "authorized"} = payment ->
        case payment_client().capture_payment_intent(payment.stripe_payment_intent_id) do
          {:ok, %{charge_id: charge_id}} ->
            mark_payment_paid(payment, charge_id)
            do_accept(appointment, opts)

          {:error, reason} ->
            {:error, {:capture_failed, reason}}
        end

      %AppointmentPayment{} ->
        {:error, :payment_not_authorized}
    end
  end

  defp do_accept(%Appointment{} = appointment, opts) do
    attrs = %{status: "accepted"}

    attrs =
      if opts[:meeting_url], do: Map.put(attrs, :meeting_url, opts[:meeting_url]), else: attrs

    appointment
    |> Appointment.status_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        # Push to the nutritionist's Google Calendar (best-effort, off-cycle).
        AppointmentCalendarSyncWorker.enqueue(:upsert, updated.id)
        {:ok, Repo.preload(updated, [:professional, :client])}

      error ->
        error
    end
  end

  @doc """
  Nutritionist declines a request. Any authorized card hold is released (the
  client is never charged).
  """
  def decline_appointment(%Appointment{} = appointment) do
    release_hold_if_authorized(appointment)

    appointment
    |> Appointment.status_changeset(%{status: "declined"})
    |> Repo.update()
    |> tap_calendar_delete()
  end

  # Remove the pushed Google event when an appointment is declined/cancelled.
  defp tap_calendar_delete({:ok, appointment} = result) do
    if appointment.google_event_id,
      do: AppointmentCalendarSyncWorker.enqueue(:delete, appointment.id)

    result
  end

  defp tap_calendar_delete(result), do: result

  @doc """
  Cancel an appointment. Money handling depends on state and timing (owner
  refund policy 2026-11-02):

    * an uncaptured hold (before acceptance) is released — no charge;
    * a captured payment (after acceptance) is refunded on a tiered schedule:
      **≥ `:consultation_free_cancel_hours`** (24h) before the slot → full
      refund (fee reversed); **≥ `:consultation_partial_refund_hours`** (4h)
      but inside the free window → 50% refund (we keep our commission on the
      retained half); **inside 4h** → no refund (full capture retained).
  """
  def cancel_appointment(%Appointment{} = appointment) do
    case get_payment_for_appointment(appointment.id) do
      %AppointmentPayment{status: "authorized"} ->
        release_hold_if_authorized(appointment)

      %AppointmentPayment{status: "paid"} = payment ->
        apply_cancellation_refund(appointment, payment)

      _ ->
        :ok
    end

    appointment
    |> Appointment.status_changeset(%{status: "cancelled"})
    |> Repo.update()
    |> tap_calendar_delete()
  end

  @doc """
  Nutritionist marks an **accepted** appointment as a no-show. The payment was
  captured on acceptance and is **retained in full** (no refund).
  """
  def mark_no_show(%Appointment{} = appointment) do
    appointment
    |> Appointment.status_changeset(%{status: "no_show"})
    |> Repo.update()
  end

  @doc """
  **Nutritionist-initiated** cancellation. Unlike a client cancellation (tiered),
  the client is **always fully refunded** — they are never penalised for the
  nutritionist calling it off. An uncaptured hold is released; a captured payment
  is fully refunded (fee reversed).
  """
  def cancel_appointment_by_professional(%Appointment{} = appointment) do
    case get_payment_for_appointment(appointment.id) do
      %AppointmentPayment{status: "authorized"} -> release_hold_if_authorized(appointment)
      %AppointmentPayment{status: "paid"} = payment -> refund_payment_full(payment)
      _ -> :ok
    end

    appointment
    |> Appointment.status_changeset(%{status: "cancelled"})
    |> Repo.update()
    |> tap_calendar_delete()
  end

  @doc """
  What a **client** cancellation would refund right now (in cents), per the tiered
  policy — for showing the consequence before they confirm. An uncaptured hold is
  fully released; a captured payment follows ≥24h→full / 4–24h→half / <4h→none.
  """
  def client_cancellation_refund_cents(%Appointment{} = appointment) do
    case get_payment_for_appointment(appointment.id) do
      %AppointmentPayment{status: "authorized", amount_cents: amount} ->
        amount

      %AppointmentPayment{status: "paid", amount_cents: amount} ->
        cond do
          hours_until(appointment) >= free_cancel_hours() -> amount
          hours_until(appointment) >= partial_refund_hours() -> div(amount, 2)
          true -> 0
        end

      _ ->
        0
    end
  end

  # ── Consultation Payments ───────────────────────────────────────────────────

  @doc "Our platform commission (in cents) for a booking amount — the flat 5%."
  def platform_fee_cents(amount_cents) when is_integer(amount_cents) do
    round(amount_cents * platform_fee_bps() / 10_000)
  end

  @doc """
  The VAT slice *contained within* our VAT-inclusive platform fee (owner
  decision 2026-11-02, build-plan §4.4). Domestic (Greek) default:
  `fee - round(fee / 1.24)`. Jurisdiction is not yet modelled, so this is
  best-effort — other-EU reverse-charge accounts should be 0; refine when the
  nutritionist's country is captured on the profile.
  """
  def fee_vat_cents(fee_cents, _profile \\ nil) when is_integer(fee_cents) do
    rate_bps = platform_fee_vat_bps()
    net = round(fee_cents * 10_000 / (10_000 + rate_bps))
    fee_cents - net
  end

  def create_appointment_payment(attrs) do
    %AppointmentPayment{}
    |> AppointmentPayment.changeset(attrs)
    |> Repo.insert()
  end

  def update_appointment_payment(%AppointmentPayment{} = payment, attrs) do
    payment
    |> AppointmentPayment.changeset(attrs)
    |> Repo.update()
  end

  def get_payment_for_appointment(appointment_id) do
    Repo.get_by(AppointmentPayment, appointment_id: appointment_id)
  end

  def get_payment_by_session(session_id) do
    Repo.get_by(AppointmentPayment, stripe_checkout_session_id: session_id)
  end

  def get_payment_by_intent(payment_intent_id) do
    Repo.get_by(AppointmentPayment, stripe_payment_intent_id: payment_intent_id)
  end

  @doc "Webhook: Checkout completed — the card is authorized (held)."
  def mark_payment_authorized(session_id, payment_intent_id) do
    case get_payment_by_session(session_id) do
      nil ->
        {:error, :not_found}

      payment ->
        update_appointment_payment(payment, %{
          status: "authorized",
          stripe_payment_intent_id: payment_intent_id,
          authorized_at: now()
        })
    end
  end

  @doc "Webhook: the client abandoned Checkout — drop the pending payment."
  def expire_payment_session(session_id) do
    case get_payment_by_session(session_id) do
      nil -> {:error, :not_found}
      payment -> update_appointment_payment(payment, %{status: "canceled", canceled_at: now()})
    end
  end

  def mark_payment_canceled_by_intent(payment_intent_id) do
    case get_payment_by_intent(payment_intent_id) do
      nil -> {:error, :not_found}
      payment -> mark_payment_canceled(payment)
    end
  end

  def mark_payment_failed(payment_intent_id, reason) do
    case get_payment_by_intent(payment_intent_id) do
      nil ->
        {:error, :not_found}

      payment ->
        update_appointment_payment(payment, %{status: "failed", failure_reason: reason})
    end
  end

  @doc "Webhook: a refund landed — record full or partial."
  def mark_payment_refunded(payment_intent_id, refunded_amount, total_amount) do
    case get_payment_by_intent(payment_intent_id) do
      nil ->
        {:error, :not_found}

      payment ->
        status = if refunded_amount >= total_amount, do: "refunded", else: "partially_refunded"

        update_appointment_payment(payment, %{
          status: status,
          refunded_amount_cents: refunded_amount,
          refunded_at: now()
        })
    end
  end

  @doc "Webhook: a dispute/chargeback was opened — flag the ledger row (we are liable)."
  def record_payment_dispute(%{"charge" => charge_id}) when is_binary(charge_id) do
    case Repo.get_by(AppointmentPayment, stripe_charge_id: charge_id) do
      nil -> {:error, :not_found}
      payment -> update_appointment_payment(payment, %{status: "disputed", disputed_at: now()})
    end
  end

  def record_payment_dispute(_), do: {:error, :not_found}

  @doc """
  Webhook: the nutritionist disconnected their Stripe account — clear the stored
  account id and mark them no longer chargeable.
  """
  def clear_stripe_connection(account_id) when is_binary(account_id) do
    case get_profile_by_stripe_account(account_id) do
      nil ->
        {:error, :not_found}

      profile ->
        update_professional_stripe(profile, %{
          stripe_connect_account_id: nil,
          stripe_charges_enabled: false
        })
    end
  end

  def mark_payment_paid(%AppointmentPayment{} = payment, charge_id) do
    update_appointment_payment(payment, %{
      status: "paid",
      stripe_charge_id: charge_id,
      captured_at: now()
    })
  end

  def mark_payment_canceled(%AppointmentPayment{} = payment) do
    update_appointment_payment(payment, %{status: "canceled", canceled_at: now()})
  end

  def mark_payment_refunded_full(%AppointmentPayment{} = payment) do
    update_appointment_payment(payment, %{
      status: "refunded",
      refunded_amount_cents: payment.amount_cents,
      refunded_at: now()
    })
  end

  defp mark_payment_partially_refunded(%AppointmentPayment{} = payment, amount) do
    update_appointment_payment(payment, %{
      status: "partially_refunded",
      refunded_amount_cents: amount,
      refunded_at: now()
    })
  end

  # Tiered client-cancellation refund on a captured booking (see cancel_appointment).
  defp apply_cancellation_refund(%Appointment{} = appointment, %AppointmentPayment{} = payment) do
    cond do
      hours_until(appointment) >= free_cancel_hours() -> refund_payment_full(payment)
      hours_until(appointment) >= partial_refund_hours() -> refund_payment_partial(payment)
      true -> :ok
    end
  end

  defp release_hold_if_authorized(%Appointment{} = appointment) do
    case get_payment_for_appointment(appointment.id) do
      %AppointmentPayment{status: "authorized", stripe_payment_intent_id: pi} = payment
      when is_binary(pi) ->
        payment_client().cancel_payment_intent(pi)
        mark_payment_canceled(payment)

      _ ->
        :ok
    end
  end

  defp refund_payment_full(%AppointmentPayment{stripe_payment_intent_id: pi} = payment)
       when is_binary(pi) do
    case payment_client().refund_payment(pi) do
      {:ok, _} -> mark_payment_refunded_full(payment)
      {:error, _reason} -> :ok
    end
  end

  defp refund_payment_full(_), do: :ok

  # Refund half the gross; Stripe reverses the transfer proportionally, and we
  # keep our 5% commission on the retained half (refund_application_fee stays
  # false for partials in StripeHandler.refund_payment/2).
  defp refund_payment_partial(%AppointmentPayment{stripe_payment_intent_id: pi} = payment)
       when is_binary(pi) do
    amount = div(payment.amount_cents, 2)

    case payment_client().refund_payment(pi, amount_cents: amount) do
      {:ok, _} -> mark_payment_partially_refunded(payment, amount)
      {:error, _reason} -> :ok
    end
  end

  defp refund_payment_partial(_), do: :ok

  # ── Analytics (Earnings & pipeline) ─────────────────────────────────────────────
  #
  # All aggregation happens in SQL (GROUP BY / sum) — we never load payment rows
  # into the LiveView. Net earned is always the single shared formula
  # `amount_cents - platform_fee_cents - refunded_amount_cents` over rows the
  # nutritionist actually keeps money on (`paid` + `partially_refunded`), matching
  # `AppointmentPayment.net_cents/1`. A `date_range` is `:all` or a
  # `{start_ndt, end_ndt}` NaiveDateTime tuple, applied on `captured_at`
  # (coalescing to `inserted_at` for safety). See
  # docs/features/professionals/analytics.md.

  @earning_statuses ~w(paid partially_refunded)

  @doc "Sum of captured earnings for a nutritionist, net of our fee + refunds, in cents."
  def professional_net_earnings_cents(professional_user_id),
    do: net_earnings_cents(professional_user_id, :all)

  @doc "Net captured earnings (cents) within an optional date range."
  def net_earnings_cents(professional_user_id, date_range \\ :all) do
    from(p in AppointmentPayment,
      where: p.professional_id == ^professional_user_id and p.status in @earning_statuses,
      select: coalesce(sum(p.amount_cents - p.platform_fee_cents - p.refunded_amount_cents), 0)
    )
    |> payment_range(date_range)
    |> Repo.one()
  end

  @doc "Gross value of authorized-but-uncaptured holds (money in flight), in cents."
  def in_flight_cents(professional_user_id) do
    from(p in AppointmentPayment,
      where: p.professional_id == ^professional_user_id and p.status == "authorized",
      select: coalesce(sum(p.amount_cents), 0)
    )
    |> Repo.one()
  end

  @doc "Count of pending (status `requested`) appointment requests awaiting accept/decline."
  def count_pending_requests(professional_user_id) do
    from(a in Appointment,
      where: a.professional_id == ^professional_user_id and a.status == "requested",
      select: count(a.id)
    )
    |> Repo.one()
  end

  @doc """
  Net captured earnings (cents) grouped by period (`:week`, `:month`, `:day`) for
  the revenue-over-time chart. Returns `[%{period: NaiveDateTime, net_cents: int}]`
  ordered ascending.
  """
  def revenue_per_period(professional_user_id, date_range \\ :all, granularity \\ :week) do
    trunc = to_string(granularity)

    from(p in AppointmentPayment,
      where: p.professional_id == ^professional_user_id and p.status in @earning_statuses,
      group_by: selected_as(:period),
      order_by: selected_as(:period),
      select: %{
        period:
          selected_as(
            fragment("date_trunc(?, coalesce(?, ?))", ^trunc, p.captured_at, p.inserted_at),
            :period
          ),
        net_cents:
          coalesce(sum(p.amount_cents - p.platform_fee_cents - p.refunded_amount_cents), 0)
      }
    )
    |> payment_range(date_range)
    |> Repo.all()
  end

  @doc """
  Count of `accepted` appointments grouped by ISO week over the last `weeks`
  weeks. Returns `[%{period: NaiveDateTime, count: int}]` ordered ascending.
  """
  def appointments_per_week(professional_user_id, weeks \\ 8) do
    since = NaiveDateTime.add(now(), -weeks * 7 * 24 * 3600, :second)

    from(a in Appointment,
      where:
        a.professional_id == ^professional_user_id and a.status == "accepted" and
          a.scheduled_at >= ^since,
      group_by: fragment("date_trunc('week', ?)", a.scheduled_at),
      order_by: fragment("date_trunc('week', ?)", a.scheduled_at),
      select: %{period: fragment("date_trunc('week', ?)", a.scheduled_at), count: count(a.id)}
    )
    |> Repo.all()
  end

  @doc """
  Net captured earnings (cents) grouped by the service sold. Returns
  `[%{service_id, name, kind, net_cents}]` ordered by net descending. Top-N
  folding into "Other" is a display concern handled in the LiveView.
  """
  def revenue_by_service(professional_user_id, date_range \\ :all) do
    from(p in AppointmentPayment,
      left_join: s in ProfessionalService,
      on: s.id == p.professional_service_id,
      where: p.professional_id == ^professional_user_id and p.status in @earning_statuses,
      group_by: [s.id, s.name, s.kind],
      order_by: [
        desc: coalesce(sum(p.amount_cents - p.platform_fee_cents - p.refunded_amount_cents), 0)
      ],
      select: %{
        service_id: s.id,
        name: s.name,
        kind: s.kind,
        net_cents:
          coalesce(sum(p.amount_cents - p.platform_fee_cents - p.refunded_amount_cents), 0)
      }
    )
    |> payment_range(date_range)
    |> Repo.all()
  end

  @doc """
  Money breakdown by outcome within a range — the leakage view. Returns a single
  map `%{captured_cents, no_show_cents, refunded_cents, released_cents}`:

    * `captured_cents`   — net kept on completed (accepted) consultations
    * `no_show_cents`    — net retained despite the client not showing
    * `refunded_cents`   — total refunded back to clients (full + partial)
    * `released_cents`   — gross of authorized holds that were released (€0 earned)
  """
  def revenue_by_outcome(professional_user_id, date_range \\ :all) do
    from(p in AppointmentPayment,
      left_join: a in Appointment,
      on: a.id == p.appointment_id,
      where: p.professional_id == ^professional_user_id,
      select: %{
        captured_cents:
          coalesce(
            sum(
              fragment(
                "CASE WHEN ? IN ('paid','partially_refunded') AND (? = 'accepted' OR ? IS NULL) THEN ? - ? - ? ELSE 0 END",
                p.status,
                a.status,
                a.status,
                p.amount_cents,
                p.platform_fee_cents,
                p.refunded_amount_cents
              )
            ),
            0
          ),
        no_show_cents:
          coalesce(
            sum(
              fragment(
                "CASE WHEN ? IN ('paid','partially_refunded') AND ? = 'no_show' THEN ? - ? - ? ELSE 0 END",
                p.status,
                a.status,
                p.amount_cents,
                p.platform_fee_cents,
                p.refunded_amount_cents
              )
            ),
            0
          ),
        refunded_cents:
          coalesce(
            sum(
              fragment(
                "CASE WHEN ? IN ('refunded','partially_refunded') THEN ? ELSE 0 END",
                p.status,
                p.refunded_amount_cents
              )
            ),
            0
          ),
        released_cents:
          coalesce(
            sum(
              fragment(
                "CASE WHEN ? = 'canceled' AND ? IS NOT NULL THEN ? ELSE 0 END",
                p.status,
                p.authorized_at,
                p.amount_cents
              )
            ),
            0
          )
      }
    )
    |> payment_range(date_range)
    |> Repo.one()
  end

  @doc """
  Net captured earnings (cents) split into first-time vs repeat clients. A
  payment is "new" when it is the client's **lifetime-first** captured payment
  with this nutritionist, else "returning" — classified by capture order, then
  summed only over payments inside `date_range`. Returns
  `%{new_cents, returning_cents}`.
  """
  def revenue_new_vs_returning(professional_user_id, date_range \\ :all) do
    ranked =
      from(p in AppointmentPayment,
        where: p.professional_id == ^professional_user_id and p.status in @earning_statuses,
        select: %{
          net: p.amount_cents - p.platform_fee_cents - p.refunded_amount_cents,
          ts: coalesce(p.captured_at, p.inserted_at),
          rn:
            over(row_number(),
              partition_by: p.client_id,
              order_by: coalesce(p.captured_at, p.inserted_at)
            )
        }
      )

    from(r in subquery(ranked),
      select: %{
        new_cents: coalesce(sum(fragment("CASE WHEN ? = 1 THEN ? ELSE 0 END", r.rn, r.net)), 0),
        returning_cents:
          coalesce(sum(fragment("CASE WHEN ? > 1 THEN ? ELSE 0 END", r.rn, r.net)), 0)
      }
    )
    |> subquery_range(date_range)
    |> Repo.one()
  end

  # Apply a `{start, end}` range on a payment query's capture timestamp (`:all` = no filter).
  defp payment_range(query, :all), do: query

  defp payment_range(query, {start_ndt, end_ndt}) do
    where(
      query,
      [p],
      coalesce(p.captured_at, p.inserted_at) >= ^start_ndt and
        coalesce(p.captured_at, p.inserted_at) <= ^end_ndt
    )
  end

  # Same, but on the pre-ranked subquery's materialized `ts` column.
  defp subquery_range(query, :all), do: query

  defp subquery_range(query, {start_ndt, end_ndt}) do
    where(query, [r], r.ts >= ^start_ndt and r.ts <= ^end_ndt)
  end

  @doc """
  Open a one-time login link to the nutritionist's Stripe Express payouts
  dashboard. Returns `{:ok, url}` or `{:error, reason}`.
  """
  def payouts_dashboard_url(%ProfessionalProfile{stripe_connect_account_id: account_id})
      when is_binary(account_id) do
    payment_client().create_login_link(account_id)
  end

  def payouts_dashboard_url(_), do: {:error, :not_connected}

  @doc """
  Appointments still `requested` whose authorized hold is about to expire
  (Stripe voids uncaptured holds after ~7 days) — used by the expiry worker to
  auto-decline and release them before Stripe does it silently.
  """
  def expiring_authorized_appointments(older_than_hours \\ 144) do
    cutoff = NaiveDateTime.add(now(), -older_than_hours * 3600, :second)

    from(a in Appointment,
      join: p in AppointmentPayment,
      on: p.appointment_id == a.id,
      where: a.status == "requested" and p.status == "authorized" and p.authorized_at < ^cutoff,
      preload: [:professional, :client]
    )
    |> Repo.all()
  end

  @doc """
  Whether the built-out Stripe consultation-charging flow is live. SHADOWED off
  by default (`:consultation_payments_enabled`): while false, booking is
  request-only and service prices are display-only (money wired directly between
  client and nutritionist outside M3Hungry).
  """
  def consultation_payments_enabled?,
    do: Application.get_env(:mehungry, :consultation_payments_enabled, false)

  defp platform_fee_bps, do: Application.get_env(:mehungry, :platform_fee_bps, 500)
  defp platform_fee_vat_bps, do: Application.get_env(:mehungry, :platform_fee_vat_bps, 2400)

  @doc "Hours-before-appointment threshold for a full client-cancellation refund (config)."
  def free_cancel_hours, do: Application.get_env(:mehungry, :consultation_free_cancel_hours, 24)

  @doc "Hours-before-appointment threshold below which only a 50% refund applies (config)."
  def partial_refund_hours,
    do: Application.get_env(:mehungry, :consultation_partial_refund_hours, 4)

  defp hours_until(%Appointment{scheduled_at: scheduled_at}),
    do: NaiveDateTime.diff(scheduled_at, NaiveDateTime.utc_now(), :second) / 3600

  # Indirection so tests can stub the money-moving Stripe calls.
  defp payment_client, do: Application.get_env(:mehungry, :stripe_payment_client, StripeHandler)

  defp now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

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

  @doc """
  Returns the professional's client record for `user` (a `%Accounts.User{}`),
  lazily creating a minimal one (name/email seeded from the user) if none exists.
  The single lazy-create used wherever a clinical file must exist before writing
  to it (client detail, appointment measurement logging).
  """
  def ensure_client_record(professional_id, %Mehungry.Accounts.User{} = user) do
    case get_client_record_by_user(professional_id, user.id) do
      nil ->
        create_client_record(%{
          professional_id: professional_id,
          user_id: user.id,
          full_name: user.name || user.email,
          email: user.email
        })

      record ->
        {:ok, record}
    end
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

  @measurement_metrics [
    :weight_kg,
    :body_fat_percentage,
    :waist_cm,
    :muscle_mass_kg,
    :bmi,
    :bmr_kcal
  ]

  @doc """
  The body metrics tracked longitudinally per client. Order is the preferred
  display order for the progress-chart metric selector.
  """
  def measurement_metrics, do: @measurement_metrics

  @doc """
  A client's dated body-measurement points, merged from both sources — each
  `ClientIntake` (`assessed_on`) and each `ConsultationNote` (`visit_date`).
  Each point carries every metric present at that date
  (`#{inspect(@measurement_metrics)}`); metrics a source doesn't track are `nil`
  (intakes only carry `weight_kg`/`bmi`/`bmr_kcal`). Points missing a date or
  carrying no metric at all are dropped. Returns
  `[%{date: ~D[...], source: :intake | :visit, <metric> => number | nil}, ...]`
  sorted ascending by date, suitable for plotting a progress trend.
  """
  def measurement_history(professional_client_id) do
    intakes =
      professional_client_id
      |> list_intakes()
      |> Enum.map(fn i ->
        %{
          date: i.assessed_on,
          source: :intake,
          weight_kg: i.weight_kg,
          body_fat_percentage: nil,
          waist_cm: nil,
          muscle_mass_kg: nil,
          bmi: i.bmi,
          bmr_kcal: i.bmr_kcal
        }
      end)

    visits =
      professional_client_id
      |> list_consultation_notes()
      |> Enum.map(fn n ->
        %{
          date: n.visit_date,
          source: :visit,
          weight_kg: n.weight_kg,
          body_fat_percentage: n.body_fat_percentage,
          waist_cm: n.waist_cm,
          muscle_mass_kg: n.muscle_mass_kg,
          bmi: n.bmi,
          bmr_kcal: n.bmr_kcal
        }
      end)

    (intakes ++ visits)
    |> Enum.filter(&(&1.date && Enum.any?(@measurement_metrics, fn m -> &1[m] end)))
    |> Enum.sort_by(& &1.date, Date)
  end

  @doc """
  A client's dated weight points — the `weight_kg`-only slice of
  `measurement_history/1`, kept for callers that plot weight alone. Returns
  `[%{date: ~D[...], weight_kg: float, source: :intake | :visit}, ...]`.
  """
  def weight_history(professional_client_id) do
    professional_client_id
    |> measurement_history()
    |> Enum.filter(& &1.weight_kg)
    |> Enum.map(&Map.take(&1, [:date, :weight_kg, :source]))
  end

  @doc """
  A user's own body-measurement history across **every** nutritionist who keeps a
  file on them — the client-facing progress feed. Aggregates
  `measurement_history/1` over all `ProfessionalClient` records for `user_id`
  (no professional scope), sorted by date. Pass only the viewer's own id.
  """
  def measurement_history_for_user(user_id) do
    ProfessionalClient
    |> where([c], c.user_id == ^user_id)
    |> Repo.all()
    |> Enum.flat_map(&measurement_history(&1.id))
    |> Enum.sort_by(& &1.date, Date)
  end

  @doc """
  Static reference values the progress chart draws goal lines / healthy bands
  from, pulled from the client's latest `ClientIntake`: `height_m` (→ healthy
  weight range via BMI 18.5–24.9), `sex` (→ body-fat healthy band) and
  `ideal_weight_kg` (→ weight goal line). No intake → empty map (the chart simply
  omits the bands/goal). See `MehungryWeb.MeasurementChart`.
  """
  def measurement_context(professional_client_id) do
    case get_latest_intake(professional_client_id) do
      nil -> %{}
      intake -> intake_context(intake)
    end
  end

  @doc """
  The user-facing counterpart to `measurement_context/1`: the reference values
  from the viewer's most-recently-assessed intake across every nutritionist who
  keeps a file on them. Pass only the viewer's own id.
  """
  def measurement_context_for_user(user_id) do
    ProfessionalClient
    |> where([c], c.user_id == ^user_id)
    |> Repo.all()
    |> Enum.map(&get_latest_intake(&1.id))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&(&1.assessed_on || ~D[0001-01-01]), {:desc, Date})
    |> case do
      [intake | _] -> intake_context(intake)
      [] -> %{}
    end
  end

  defp intake_context(intake) do
    %{height_m: intake.height_m, sex: intake.sex, ideal_weight_kg: intake.ideal_weight_kg}
  end

  @doc """
  The consultation note already logged for a given appointment, if any.

  Used by the "Log measurement" flow so a second log for the same meeting
  pre-fills and updates the existing note instead of inserting a duplicate.
  Returns `nil` when no note has been logged for the appointment yet.
  """
  def get_consultation_note_by_appointment(nil), do: nil

  def get_consultation_note_by_appointment(appointment_id) do
    Repo.one(
      from n in ConsultationNote,
        where: n.appointment_id == ^appointment_id,
        order_by: [desc: n.inserted_at],
        limit: 1
    )
  end

  def create_consultation_note(attrs) do
    %ConsultationNote{}
    |> ConsultationNote.changeset(fill_measurement_energy(attrs))
    |> validate_note_appointment()
    |> Repo.insert()
  end

  # A note may only link an appointment that is actually this record's meeting:
  # same professional, booked with the record's platform user. The FK alone
  # would accept any professional's appointment id arriving from the visit
  # form — and `list_consultation_notes/1` preloads `:appointment`, so an
  # unchecked id would render another professional's appointment on the page.
  defp validate_note_appointment(changeset) do
    with id when not is_nil(id) <- Ecto.Changeset.get_change(changeset, :appointment_id),
         pcid when not is_nil(pcid) <-
           Ecto.Changeset.get_field(changeset, :professional_client_id) do
      record = Repo.get(ProfessionalClient, pcid)
      appointment = Repo.get(Appointment, id)

      if record && appointment && appointment.professional_id == record.professional_id &&
           appointment.client_id == record.user_id do
        changeset
      else
        Ecto.Changeset.add_error(changeset, :appointment_id, "is not this client's appointment")
      end
    else
      _ -> changeset
    end
  end

  @doc """
  Logs the measurement note for an appointment as a single source of truth.

  There must be at most one consultation note per meeting. When none exists a
  note is created; when one or more exist (duplicates can linger from before
  the single-note rule) the most recent is **updated** and every other note for
  that appointment is **deleted** in the same transaction, so after an update
  exactly one note remains. Falls back to a plain create when `appointment_id`
  is missing. Returns `{:ok, note}` / `{:error, changeset}`.
  """
  def upsert_consultation_note_for_appointment(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    case attrs["appointment_id"] do
      blank when blank in [nil, ""] ->
        create_consultation_note(attrs)

      appointment_id ->
        notes =
          Repo.all(
            from n in ConsultationNote,
              where: n.appointment_id == ^appointment_id,
              order_by: [desc: n.inserted_at, desc: n.id]
          )

        case notes do
          [] ->
            create_consultation_note(attrs)

          [latest | stale] ->
            Repo.transaction(fn ->
              Enum.each(stale, &Repo.delete!/1)

              case update_consultation_note(latest, attrs) do
                {:ok, note} -> note
                {:error, changeset} -> Repo.rollback(changeset)
              end
            end)
        end
    end
  end

  def update_consultation_note(%ConsultationNote{} = note, attrs) do
    note
    |> ConsultationNote.changeset(fill_measurement_energy(attrs))
    |> validate_note_appointment()
    |> Repo.update()
  end

  # Fills `bmi` / `bmr_kcal` that the caller left blank, derived from the client's
  # latest intake (height_m / sex / age) + the note's measured weight. Mirrors
  # `ClientIntake.maybe_fill_energy/1`'s never-overwrite rule, but lives here
  # because the inputs span two rows (the note has weight; the intake has the
  # rest). No intake → nothing to derive → measured values saved as-is.
  defp fill_measurement_energy(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    with pcid when not is_nil(pcid) <- attrs["professional_client_id"],
         %ClientIntake{} = intake <- get_latest_intake(pcid) do
      derived =
        Anthropometrics.compute(%{
          height_m: intake.height_m,
          weight_kg: attrs["weight_kg"],
          sex: intake.sex,
          age: intake.age
        })

      attrs
      |> put_blank("bmi", derived[:bmi])
      |> put_blank("bmr_kcal", derived[:bmr_kcal])
    else
      _ -> attrs
    end
  end

  defp put_blank(attrs, _key, nil), do: attrs

  defp put_blank(attrs, key, value) do
    case attrs[key] do
      blank when blank in [nil, ""] -> Map.put(attrs, key, value)
      _present -> attrs
    end
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
