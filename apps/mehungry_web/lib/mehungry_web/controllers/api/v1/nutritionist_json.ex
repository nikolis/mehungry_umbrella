defmodule MehungryWeb.Api.V1.NutritionistJSON do
  @moduledoc """
  Shared serializers for the client-facing "My nutritionist" surface (spec §18) —
  the public directory/profile, the hub, appointments, messages, the onboarding
  questionnaire and the progress chart. Centralized so the four §18 controllers
  (`NutritionistDirectoryController`, `MyNutritionistController`,
  `AppointmentController`, `ClientOnboardingController`) never diverge on a shape
  the mobile client depends on. Plain functions returning maps (like `MealJSON`),
  never Ecto structs.
  """

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Accounts.User
  alias Mehungry.Onboarding.{Question, QuestionOption}
  alias Mehungry.Professionals
  alias Mehungry.Professionals.ProfessionalProfile

  # ── Directory & public profile ──────────────────────────────────────────────

  @doc "A directory row (`GET /nutritionists`)."
  def directory_entry(%ProfessionalProfile{} = p) do
    %{
      professional_id: p.user_id,
      slug: p.slug,
      display_name: p.display_name,
      specialization: p.specialization,
      bio: p.bio,
      photo_url: p.photo_url,
      city: p.city,
      region: p.region,
      handle: p.handle
    }
  end

  @doc "The full public profile (`GET /nutritionists/:slug`)."
  def profile(%ProfessionalProfile{} = p, services, articles, payments_enabled) do
    %{
      professional_id: p.user_id,
      slug: p.slug,
      handle: p.handle,
      display_name: p.display_name,
      specialization: p.specialization,
      bio: p.bio,
      photo_url: p.photo_url,
      education: p.education,
      scientific_contributions: p.scientific_contributions,
      professional_achievements: p.professional_achievements,
      city: p.city,
      region: p.region,
      office_address: p.office_address,
      phone: p.phone,
      contact_email: p.contact_email,
      website_url: p.website_url,
      timezone: Mehungry.Time.tz(p),
      slot_minutes: p.appointment_slot_minutes,
      payments_enabled: payments_enabled,
      services: Enum.map(services, &service/1),
      articles: Enum.map(articles, &article_summary/1)
    }
  end

  @doc "A bookable service (full), intro → `price_eur: null`."
  def service(s) do
    %{
      id: s.id,
      kind: s.kind,
      name: s.name,
      description: s.description,
      price_eur: price_eur(s),
      duration_minutes: s.duration_minutes,
      session_count: s.session_count
    }
  end

  @doc "The trimmed service shape embedded in the slots payload."
  def service_mini(s) do
    %{
      id: s.id,
      kind: s.kind,
      name: s.name,
      price_eur: price_eur(s),
      duration_minutes: s.duration_minutes
    }
  end

  @doc "Open booking slots (`GET /nutritionists/:slug/slots`)."
  def slots(%ProfessionalProfile{} = p, services, slots) do
    %{
      timezone: Mehungry.Time.tz(p),
      slot_minutes: p.appointment_slot_minutes,
      services: Enum.map(services, &service_mini/1),
      slots: Enum.map(slots, &utc/1)
    }
  end

  @doc "An article list row."
  def article_summary(a) do
    %{slug: a.slug, title: a.title, published_at: utc(a.published_at)}
  end

  @doc "A full published article (`GET /nutritionists/:slug/articles/:article_slug`)."
  def article(article) do
    {numbers, ordered} = number_references(article)

    %{
      slug: article.slug,
      title: article.title,
      summary: article.summary,
      cover_image_url: article.cover_image_url,
      published_at: utc(article.published_at),
      paragraphs:
        article.paragraphs
        |> Enum.sort_by(& &1.position)
        |> Enum.map(&article_paragraph(&1, numbers)),
      references:
        Enum.map(ordered, fn ref ->
          %{
            number: Map.fetch!(numbers, ref_key(ref)),
            type: ref.reference_type,
            citation: citation_text(ref),
            url: citation_url(ref)
          }
        end)
    }
  end

  defp article_paragraph(p, numbers) do
    %{
      position: p.position,
      heading: p.heading,
      body: p.body,
      image_url: p.image_url,
      image_caption: p.image_caption,
      reference_numbers: Enum.map(p.references, &Map.fetch!(numbers, ref_key(&1)))
    }
  end

  # Deduped, numbered in first-encounter order across all paragraphs (mirrors
  # `PublicNutritionistLive.Article`).
  defp number_references(article) do
    ordered =
      article.paragraphs
      |> Enum.sort_by(& &1.position)
      |> Enum.flat_map(& &1.references)
      |> Enum.uniq_by(&ref_key/1)

    numbers =
      ordered
      |> Enum.with_index(1)
      |> Map.new(fn {ref, n} -> {ref_key(ref), n} end)

    {numbers, ordered}
  end

  defp ref_key(%{
         reference_type: t,
         study_id: s,
         species_id: sp,
         compound_id: c,
         condition_id: co
       }),
       do: {t, s, sp, c, co}

  defp citation_text(%{reference_type: "study", study: s}) when not is_nil(s),
    do: Enum.reject([s.title, s.pmid && "PMID #{s.pmid}"], &is_nil/1) |> Enum.join(" · ")

  defp citation_text(%{reference_type: "species", species: sp}) when not is_nil(sp),
    do: sp.scientific_name || sp.name

  defp citation_text(%{reference_type: "compound", compound: c}) when not is_nil(c),
    do: "Compound: #{c.name}"

  defp citation_text(%{reference_type: "condition", condition: c}) when not is_nil(c),
    do: "Disease: #{c.name}"

  defp citation_text(_), do: nil

  defp citation_url(%{reference_type: "study", study: %{pmid: pmid}}) when not is_nil(pmid),
    do: "https://pubmed.ncbi.nlm.nih.gov/#{pmid}"

  defp citation_url(_), do: nil

  # ── Hub, invitations, appointments, messages ──────────────────────────────────

  @doc """
  The connected nutritionist preview on the hub. Mirrors the web hub's
  "connected, no public profile yet" state (`MyNutritionistLive.Index`): when the
  nutritionist has no `ProfessionalProfile` row, fall back to the assignment's
  professional `User` so the client is still shown as connected.
  """
  def hub_nutritionist(%ProfessionalProfile{} = p, payments_enabled) do
    %{
      professional_id: p.user_id,
      slug: p.slug,
      handle: p.handle,
      display_name: p.display_name,
      specialization: p.specialization,
      bio: p.bio,
      photo_url: p.photo_url,
      city: p.city,
      timezone: Mehungry.Time.tz(p),
      payments_enabled: payments_enabled
    }
  end

  def hub_nutritionist(%User{} = u, _payments_enabled) do
    %{
      professional_id: u.id,
      slug: nil,
      handle: nil,
      display_name: u.name || u.email,
      specialization: nil,
      bio: nil,
      photo_url: u.profile_pic,
      city: nil,
      timezone: Mehungry.Time.tz(nil),
      payments_enabled: false
    }
  end

  @doc "A minimal professional preview (invitations, appointments)."
  def preview(nil), do: nil

  def preview(%ProfessionalProfile{} = p) do
    %{professional_id: p.user_id, slug: p.slug, display_name: p.display_name, photo_url: p.photo_url}
  end

  def preview(%User{} = u) do
    %{professional_id: u.id, slug: nil, display_name: u.name || u.email, photo_url: u.profile_pic}
  end

  @doc """
  A pending invitation row, with its inviting professional preview. Falls back to
  the invitation's professional `User` when that nutritionist has no profile row
  (same tolerance as the hub preview).
  """
  def invitation(inv, profile) do
    professional = preview(profile) || preview(loaded(inv.professional))
    %{id: inv.id, inserted_at: utc(inv.inserted_at), professional: professional}
  end

  @doc "A client-facing appointment. `profile` is the owning nutritionist's profile."
  def appointment(appt, profile, now) do
    %{
      id: appt.id,
      status: appt.status,
      title: appt.title,
      notes: appt.notes,
      scheduled_at: utc(appt.scheduled_at),
      ends_at: utc(appt.ends_at),
      timezone: Mehungry.Time.tz(profile),
      meeting_url: appt.meeting_url,
      cancellable: cancellable?(appt, now),
      cancellation_refund_cents: refund_preview(appt),
      professional: preview(profile),
      service: service_opt(loaded(appt.service)),
      payment: payment(loaded(appt.payment))
    }
  end

  @doc "A single thread message. `from_me` is relative to `viewer_id`."
  def message(m, viewer_id) do
    %{
      id: m.id,
      body: m.body,
      from_me: m.sender_user_id == viewer_id,
      sender_user_id: m.sender_user_id,
      read_at: utc(m.read_at),
      inserted_at: utc(m.inserted_at)
    }
  end

  # ── Onboarding questionnaire ──────────────────────────────────────────────────

  @doc "One questionnaire question merged with the user's answer (localized)."
  def question(%Question{} = q, answer, locale) do
    base = %{
      id: q.id,
      prompt: Question.prompt(q, locale),
      type: q.question_type,
      required: q.required,
      position: q.position,
      options: Enum.map(q.options, &option(&1, locale)),
      answer: answer_json(answer)
    }

    if q.question_type == "value", do: Map.put(base, :value_kind, q.value_kind), else: base
  end

  defp option(%QuestionOption{} = o, locale), do: %{key: o.key, label: QuestionOption.label(o, locale)}

  defp answer_json(nil), do: nil

  defp answer_json(answer),
    do: %{value_text: answer.value_text, selected_options: answer.selected_options || []}

  # ── Progress (measurements) ───────────────────────────────────────────────────

  # Display label/unit per metric (mirrors `MehungryWeb.MeasurementChart`). The
  # metric *set and order* are NOT hardcoded here — they are driven off
  # `Professionals.measurement_metrics/0` so adding/reordering a metric in the
  # context propagates to both the `metrics` list and every `history` row.
  @metric_meta %{
    weight_kg: {"Weight", "kg"},
    body_fat_percentage: {"Body fat", "%"},
    waist_cm: {"Waist", "cm"},
    muscle_mass_kg: {"Muscle mass", "kg"},
    bmi: {"BMI", nil},
    bmr_kcal: {"BMR", "kcal"}
  }

  @doc "The client's own progress dashboard (`GET /me/progress`)."
  def progress(history, context) do
    %{
      metrics: Enum.map(Professionals.measurement_metrics(), &metric_meta/1),
      context: progress_context(context),
      history: Enum.map(history, &progress_point/1)
    }
  end

  defp metric_meta(key) do
    {label, unit} = Map.get(@metric_meta, key, {humanize(key), nil})
    %{key: to_string(key), label: label, unit: unit}
  end

  defp humanize(key), do: key |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp progress_context(context) when map_size(context) == 0, do: %{}

  defp progress_context(context) do
    %{height_m: context[:height_m], sex: context[:sex], ideal_weight_kg: context[:ideal_weight_kg]}
  end

  defp progress_point(point) do
    base = %{date: point.date && Date.to_iso8601(point.date), source: to_string(point.source)}

    Enum.reduce(Professionals.measurement_metrics(), base, fn key, acc ->
      Map.put(acc, key, Map.get(point, key))
    end)
  end

  # ── Private helpers ───────────────────────────────────────────────────────────

  defp price_eur(%{kind: "intro"}), do: nil
  defp price_eur(%{price_cents: cents}) when is_integer(cents) and cents > 0, do: euros(cents)
  defp price_eur(_), do: nil

  defp euros(cents), do: "€" <> :erlang.float_to_binary(cents / 100, decimals: 2)

  defp cancellable?(appt, now) do
    appt.status in ["requested", "accepted"] and
      NaiveDateTime.compare(appt.scheduled_at, now) == :gt
  end

  # Only appointments carrying a payment have a refund consequence (free /
  # request-only bookings → null).
  defp refund_preview(appt) do
    case loaded(appt.payment) do
      nil -> nil
      _payment -> Professionals.client_cancellation_refund_cents(appt)
    end
  end

  defp service_opt(nil), do: nil
  defp service_opt(service), do: service_mini(service)

  defp payment(nil), do: nil

  defp payment(p) do
    %{
      status: p.status,
      amount_cents: p.amount_cents,
      currency: p.currency,
      refunded_amount_cents: p.refunded_amount_cents
    }
  end

  defp loaded(%Ecto.Association.NotLoaded{}), do: nil
  defp loaded(value), do: value
end
