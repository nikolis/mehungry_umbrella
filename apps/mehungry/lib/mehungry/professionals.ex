defmodule Mehungry.Professionals do
  import Ecto.Query
  alias Mehungry.Repo
  alias Mehungry.Accounts

  alias Mehungry.Professionals.{
    ProfessionalProfile,
    ProfessionalAvailability,
    TutorInvitation,
    TutorClientAssignment,
    Appointment,
    MealPlanRating,
    Article,
    ArticleParagraph,
    ArticleReference
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

  @doc "Send an invitation from a professional to a user identified by email."
  def invite_client(professional_id, client_email, message \\ nil) do
    case Accounts.get_user_by_email(client_email) do
      nil ->
        {:error, :client_not_found}

      client ->
        existing =
          Repo.get_by(TutorInvitation, professional_id: professional_id, client_id: client.id)

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
      create_appointment(%{
        professional_id: professional_id,
        client_id: client_id,
        scheduled_at: scheduled_at,
        ends_at: ends_at,
        title: opts[:title] || "Consultation",
        notes: opts[:notes],
        status: "requested"
      })
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
end
