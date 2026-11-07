defmodule Mehungry.Progress do
  @moduledoc """
  User-owned self-tracking **progress journal** — goals, dated diary entries
  (body measurements + notes), and body photos, organised into first-class
  **periods** (`Progress.Period`). This is the self-service counterpart to the
  nutritionist-recorded measurement history in `Mehungry.Professionals`
  (`ClientIntake`/`ConsultationNote`): it exists for users with **no**
  nutritionist at all, and is always scoped by `user_id`.

  ## Periods

  A user has at most one **active** period (DB partial unique index). "Reset /
  start over" closes the active period and opens a fresh `"self"` one — the
  closed period stays in the history list. When the user is assigned a
  nutritionist, `on_nutritionist_assigned/2` closes the active period and opens
  a `"nutritionist_aligned"` one: self-logging pauses and that period's chart
  is fed by the nutritionist's measurements instead
  (`measurement_history_for_period/1`). Unassignment reverses it.

  ## Chart parity

  `measurement_history_for_period/1` returns the **exact** point shape
  `Professionals.measurement_history_for_user/1` produces
  (`%{date:, source:, weight_kg:, ...}`) so `MehungryWeb.MeasurementChart`
  renders either source unchanged; self-logged points carry `source: :self`.

  Depends one-way on `Professionals` (assignment lookup + aligned history);
  the only reverse edge is the two alignment hooks `Professionals` calls.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Storage
  alias Mehungry.Professionals
  alias Mehungry.Professionals.Anthropometrics
  alias Mehungry.Progress.{Entry, Period, Photo}

  # ── Periods ────────────────────────────────────────────────────────────────────

  @doc "The user's active period (`ended_on IS NULL`), or `nil`."
  def active_period(user_id) do
    Repo.one(
      from p in Period,
        where: p.user_id == ^user_id and is_nil(p.ended_on)
    )
  end

  @doc """
  The user's active period, creating a fresh `"self"` period (started today)
  when none exists. Safe under races: a concurrent create loses on the partial
  unique index and the winner is re-fetched.
  """
  def ensure_active_period(user_id, attrs \\ %{}) do
    case active_period(user_id) do
      %Period{} = period ->
        {:ok, period}

      nil ->
        attrs =
          attrs
          |> Map.new(fn {k, v} -> {to_string(k), v} end)
          |> Map.merge(%{"user_id" => user_id, "kind" => "self"})
          |> Map.put_new("started_on", Date.utc_today())

        case %Period{} |> Period.changeset(attrs) |> Repo.insert() do
          {:ok, period} ->
            {:ok, period}

          {:error, %Ecto.Changeset{errors: errors} = changeset} ->
            # Lost the one-active-period race — the winner is the active period.
            if Keyword.has_key?(errors, :user_id),
              do: {:ok, active_period(user_id)},
              else: {:error, changeset}
        end
    end
  end

  @doc """
  Bootstrap the user's journal: return the active period, creating the right
  first period when none exists — **nutritionist-aligned** when the user is
  already assigned a nutritionist (pre-existing clients seeing the journal for
  the first time must not be asked to self-log), else a fresh `"self"` period.
  The entry point both the profile tab and the API use.
  """
  def ensure_journal(user_id) do
    case active_period(user_id) do
      %Period{} = period ->
        {:ok, period}

      nil ->
        case Professionals.get_assignment_for_client(user_id) do
          %{professional_id: professional_id} ->
            on_nutritionist_assigned(user_id, professional_id)

          _ ->
            ensure_active_period(user_id)
        end
    end
  end

  @doc "All of the user's periods, most recently started first."
  def list_periods(user_id) do
    Repo.all(
      from p in Period,
        where: p.user_id == ^user_id,
        order_by: [desc: p.started_on, desc: p.id]
    )
  end

  @doc "Fetch a period by id **and** owner. Returns `nil` for other users' periods."
  def get_period(user_id, id), do: Repo.get_by(Period, id: id, user_id: user_id)

  def get_period!(user_id, id), do: Repo.get_by!(Period, id: id, user_id: user_id)

  @doc "Update a period's editable attributes (title, notes, snapshot, goals, metrics)."
  def update_period(%Period{} = period, attrs) do
    period |> Period.changeset(attrs) |> Repo.update()
  end

  @doc """
  Configure a **self** period in one call: goals (normalized — string values
  parsed, blanks dropped), tracked metrics, title/notes, and the anthropometric
  snapshot. Ignores unknown keys; rejects aligned periods
  (`{:error, :not_self_period}`).
  """
  def configure_period(user_id, period_id, attrs) do
    with {:ok, period} <- fetch_self_period(user_id, period_id) do
      attrs =
        attrs
        |> Map.new(fn {k, v} -> {to_string(k), v} end)
        |> Map.take(~w(title notes tracked_metrics goals height_m sex age))
        |> case do
          %{"goals" => goals} = a when is_map(goals) ->
            Map.put(a, "goals", normalize_goals(goals))

          a ->
            a
        end

      update_period(period, attrs)
    end
  end

  @doc """
  Set per-metric goals on a **self** period, e.g. `%{"weight_kg" => 72.0}`.
  String values (form params) are parsed; blank/invalid entries are dropped.
  """
  def set_goals(user_id, period_id, goals) when is_map(goals),
    do: configure_period(user_id, period_id, %{goals: goals})

  @doc "Set which metrics a **self** period tracks (subset of `Period.selectable_metrics/0`)."
  def set_tracked_metrics(user_id, period_id, metric_keys) when is_list(metric_keys),
    do: configure_period(user_id, period_id, %{tracked_metrics: metric_keys})

  @doc """
  "Start over from 0": close the active period today and open a fresh `"self"`
  period, carrying over `tracked_metrics` and the anthropometric snapshot but
  resetting goals. The closed period (with all entries/photos) stays in history.
  """
  def reset_period(user_id, attrs \\ %{}) do
    Repo.transaction(fn ->
      case active_period(user_id) do
        nil ->
          case ensure_active_period(user_id, attrs) do
            {:ok, opened} -> %{closed: nil, opened: opened}
            {:error, changeset} -> Repo.rollback(changeset)
          end

        %Period{} = active ->
          with {:ok, closed} <- close_period(active),
               {:ok, opened} <-
                 %Period{}
                 |> Period.changeset(
                   Map.merge(
                     %{
                       "user_id" => user_id,
                       "kind" => "self",
                       "started_on" => Date.utc_today(),
                       "tracked_metrics" => closed.tracked_metrics,
                       "height_m" => closed.height_m,
                       "sex" => closed.sex,
                       "age" => closed.age
                     },
                     Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
                   )
                 )
                 |> Repo.insert() do
            %{closed: closed, opened: opened}
          else
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
  end

  # ── Sharing with the assigned nutritionist ─────────────────────────────────────

  @doc """
  Opt the period in to being visible to the user's **assigned** nutritionist.
  `{:error, :no_nutritionist}` when the user has no assignment.
  """
  def share_period(user_id, period_id) do
    with %Period{} = period <- get_period(user_id, period_id) || {:error, :not_found},
         %{professional_id: _} <- Professionals.get_assignment_for_client(user_id) ||
           {:error, :no_nutritionist} do
      update_period(period, %{shared_with_nutritionist: true})
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Revoke the nutritionist's visibility into the period."
  def unshare_period(user_id, period_id) do
    case get_period(user_id, period_id) do
      nil -> {:error, :not_found}
      period -> update_period(period, %{shared_with_nutritionist: false})
    end
  end

  @doc """
  The read surface for the nutritionist: the client's most recent period they
  chose to share, plus its chart inputs — or `nil`. Verifies the caller **is**
  the client's assigned nutritionist (never trusts the id pair).
  """
  def shared_history_for_professional(professional_id, client_user_id) do
    with %{professional_id: ^professional_id} <-
           Professionals.get_assignment_for_client(client_user_id),
         %Period{} = period <-
           Repo.one(
             from p in Period,
               where: p.user_id == ^client_user_id and p.shared_with_nutritionist == true,
               order_by: [desc: p.started_on, desc: p.id],
               limit: 1
           ) do
      %{
        period: period,
        history: measurement_history_for_period(period),
        context: progress_context(client_user_id, period)
      }
    else
      _ -> nil
    end
  end

  # ── Entries (diary) ────────────────────────────────────────────────────────────

  @doc """
  Log (or re-log) the diary entry for `date` in a **self** period — one entry
  per date, so a second log of the same day updates it. `bmi`/`bmr_kcal` are
  derived from the period's anthropometric snapshot where computable, never
  typed by the user. Rejects logging into nutritionist-aligned periods
  (`{:error, :not_self_period}`).
  """
  def upsert_entry_by_date(user_id, period_id, %Date{} = date, attrs) do
    with {:ok, period} <- fetch_self_period(user_id, period_id) do
      attrs =
        attrs
        |> Map.new(fn {k, v} -> {to_string(k), v} end)
        |> Map.drop(["bmi", "bmr_kcal"])
        |> Map.merge(%{
          "progress_period_id" => period.id,
          "user_id" => user_id,
          "entry_date" => date
        })

      base =
        Repo.get_by(Entry, progress_period_id: period.id, entry_date: date) || %Entry{}

      base
      |> Entry.changeset(attrs)
      |> derive_energy(period)
      |> Repo.insert_or_update()
    end
  end

  @doc "Log an entry from a params map carrying `entry_date` (defaults to today)."
  def log_entry(user_id, period_id, attrs) do
    date =
      case Map.get(attrs, "entry_date") || Map.get(attrs, :entry_date) do
        %Date{} = d -> d
        d when is_binary(d) and d != "" -> Date.from_iso8601!(d)
        _ -> Date.utc_today()
      end

    upsert_entry_by_date(user_id, period_id, date, attrs)
  end

  @doc "The period's diary entries, oldest first, photos preloaded."
  def list_entries(user_id, period_id) do
    Repo.all(
      from e in Entry,
        where: e.user_id == ^user_id and e.progress_period_id == ^period_id,
        order_by: [asc: e.entry_date],
        preload: [:photos]
    )
  end

  @doc "Fetch an entry by id **and** owner."
  def get_entry(user_id, id) do
    Repo.one(
      from e in Entry,
        where: e.id == ^id and e.user_id == ^user_id,
        preload: [:photos]
    )
  end

  @doc "Delete an entry **and** its photos' storage objects."
  def delete_entry(user_id, id) do
    case get_entry(user_id, id) do
      nil ->
        {:error, :not_found}

      entry ->
        Enum.each(entry.photos, &delete_photo_object/1)
        Repo.delete(entry)
    end
  end

  # ── Photos ─────────────────────────────────────────────────────────────────────

  @doc """
  Attach an uploaded photo (already in `Mehungry.Storage`) to one of the user's
  entries. `attrs` carries `url` (+ optional `storage_key`/`caption`).
  """
  def attach_photo(user_id, entry_id, attrs) do
    case get_entry(user_id, entry_id) do
      nil ->
        {:error, :not_found}

      entry ->
        attrs =
          attrs
          |> Map.new(fn {k, v} -> {to_string(k), v} end)
          |> Map.merge(%{
            "progress_entry_id" => entry.id,
            "user_id" => user_id,
            "position" => length(entry.photos)
          })

        %Photo{} |> Photo.changeset(attrs) |> Repo.insert()
    end
  end

  @doc "All photos in a period, ordered by their entry's date."
  def list_photos(user_id, period_id) do
    Repo.all(
      from ph in Photo,
        join: e in Entry,
        on: ph.progress_entry_id == e.id,
        where: ph.user_id == ^user_id and e.progress_period_id == ^period_id,
        order_by: [asc: e.entry_date, asc: ph.position],
        preload: [entry: e]
    )
  end

  @doc "Delete a photo row **and** its storage object."
  def delete_photo(user_id, photo_id) do
    case Repo.get_by(Photo, id: photo_id, user_id: user_id) do
      nil ->
        {:error, :not_found}

      photo ->
        with {:ok, photo} <- Repo.delete(photo) do
          delete_photo_object(photo)
          {:ok, photo}
        end
    end
  end

  # ── Chart inputs (shape parity with Professionals.measurement_history_*) ──────

  @doc """
  The period's measurement history in the exact `MeasurementChart` point shape.

    * `"self"` periods: the user's own entries, `source: :self`.
    * `"nutritionist_aligned"` periods: the nutritionist-recorded history
      (`Professionals.measurement_history_for_user/1`) up to the period's end
      — sources stay `:intake`/`:visit`, nothing recomputed. Deliberately **no
      lower date bound**: a nutritionist often holds measurements predating the
      assignment (or the journal's rollout), and the aligned chart must match
      what the old flat "My progress" view showed.
  """
  def measurement_history_for_period(%Period{kind: "self"} = period) do
    Repo.all(
      from e in Entry,
        where: e.progress_period_id == ^period.id,
        order_by: [asc: e.entry_date]
    )
    |> Enum.filter(&entry_has_metric?/1)
    |> Enum.map(fn e ->
      %{
        date: e.entry_date,
        source: :self,
        weight_kg: e.weight_kg,
        body_fat_percentage: e.body_fat_percentage,
        waist_cm: e.waist_cm,
        muscle_mass_kg: e.muscle_mass_kg,
        bmi: e.bmi,
        bmr_kcal: e.bmr_kcal
      }
    end)
  end

  def measurement_history_for_period(%Period{kind: "nutritionist_aligned"} = period) do
    period.user_id
    |> Professionals.measurement_history_for_user()
    |> Enum.filter(fn point ->
      is_nil(period.ended_on) or Date.compare(point.date, period.ended_on) != :gt
    end)
  end

  @doc """
  The chart's reference `context` for a period: the nutritionist-intake context
  where one exists (`%{height_m:, sex:, ideal_weight_kg:}`), back-filled from
  the period's own anthropometric snapshot, plus the period's `goals` (read by
  `MeasurementChart.goal/2` to draw per-metric goal lines).
  """
  def progress_context(user_id, %Period{} = period) do
    user_id
    |> Professionals.measurement_context_for_user()
    |> then(fn ctx ->
      ctx
      |> Map.update(:height_m, period.height_m, &(&1 || period.height_m))
      |> Map.update(:sex, period.sex, &(&1 || period.sex))
    end)
    |> Map.put(:goals, period.goals || %{})
  end

  @doc "Photo pins for the trend chart: `[%{date:, url:, entry_id:, caption:}]`, oldest first."
  def photo_markers(%Period{} = period) do
    Repo.all(
      from ph in Photo,
        join: e in Entry,
        on: ph.progress_entry_id == e.id,
        where: e.progress_period_id == ^period.id,
        order_by: [asc: e.entry_date, asc: ph.position],
        select: %{date: e.entry_date, url: ph.url, entry_id: e.id, caption: ph.caption}
    )
    |> Enum.uniq_by(& &1.entry_id)
  end

  @doc """
  The before→now photo comparison: the earliest and latest photo-carrying
  entries of the period (with their measurements for delta display), or `nil`
  until two distinct dates have photos.
  """
  def comparison(%Period{} = period) do
    entries =
      Repo.all(
        from e in Entry,
          join: ph in Photo,
          on: ph.progress_entry_id == e.id,
          where: e.progress_period_id == ^period.id,
          preload: [:photos]
      )
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.entry_date, Date)

    # Entry dates are unique per period, so 2+ photo'd entries ⇒ distinct dates.
    case entries do
      [first | [_ | _] = rest] ->
        %{before: comparison_side(first), now: comparison_side(List.last(rest))}

      _ ->
        nil
    end
  end

  defp comparison_side(entry) do
    %{
      date: entry.entry_date,
      url: List.first(Enum.sort_by(entry.photos, & &1.position)).url,
      entry: entry
    }
  end

  # ── Nutritionist-alignment hooks (called by Mehungry.Professionals) ───────────

  @doc """
  Called when `user_id` is assigned to a nutritionist: closes whatever period
  is active (any kind) and opens a `"nutritionist_aligned"` period. No-op when
  the active period is already aligned to the same professional (re-accepting
  the same nutritionist).
  """
  def on_nutritionist_assigned(user_id, professional_id) do
    case active_period(user_id) do
      %Period{kind: "nutritionist_aligned", professional_id: ^professional_id} = period ->
        {:ok, period}

      active ->
        Repo.transaction(fn ->
          if active, do: close_period!(active)

          %Period{}
          |> Period.changeset(%{
            "user_id" => user_id,
            "kind" => "nutritionist_aligned",
            "professional_id" => professional_id,
            "started_on" => Date.utc_today(),
            "tracked_metrics" => (active && active.tracked_metrics) || ["weight_kg"],
            "height_m" => active && active.height_m,
            "sex" => active && active.sex,
            "age" => active && active.age
          })
          |> Repo.insert()
          |> case do
            {:ok, period} -> period
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)
    end
  end

  @doc """
  Called when `user_id`'s nutritionist assignment ends: closes the active
  aligned period and reopens a fresh `"self"` period so self-tracking resumes.
  A `"self"` active period (or none) is left untouched.
  """
  def on_nutritionist_unassigned(user_id) do
    case active_period(user_id) do
      %Period{kind: "nutritionist_aligned"} = period ->
        Repo.transaction(fn ->
          closed = close_period!(period)

          %Period{}
          |> Period.changeset(%{
            "user_id" => user_id,
            "kind" => "self",
            "started_on" => Date.utc_today(),
            "tracked_metrics" => closed.tracked_metrics,
            "height_m" => closed.height_m,
            "sex" => closed.sex,
            "age" => closed.age
          })
          |> Repo.insert()
          |> case do
            {:ok, opened} -> opened
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)

      _ ->
        :ok
    end
  end

  # ── Internals ──────────────────────────────────────────────────────────────────

  defp fetch_self_period(user_id, period_id) do
    case get_period(user_id, period_id) do
      nil -> {:error, :not_found}
      %Period{kind: "self"} = period -> {:ok, period}
      %Period{} -> {:error, :not_self_period}
    end
  end

  defp close_period(%Period{} = period) do
    period |> Period.changeset(%{ended_on: Date.utc_today()}) |> Repo.update()
  end

  defp close_period!(%Period{} = period) do
    case close_period(period) do
      {:ok, closed} -> closed
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  # Derive BMI/BMR on the changeset from its weight + the period's snapshot,
  # storing only what's computable (mirrors ClientIntake.maybe_fill_energy/1 —
  # never fabricate: BMR needs sex+age+height, BMI just height).
  defp derive_energy(changeset, %Period{} = period) do
    weight = Ecto.Changeset.get_field(changeset, :weight_kg)

    changeset
    |> Ecto.Changeset.put_change(:bmi, Anthropometrics.bmi(period.height_m, weight))
    |> Ecto.Changeset.put_change(
      :bmr_kcal,
      Anthropometrics.bmr_kcal(period.sex, period.age, period.height_m, weight)
    )
  end

  defp entry_has_metric?(entry) do
    Enum.any?(
      [:weight_kg, :body_fat_percentage, :waist_cm, :muscle_mass_kg, :bmi, :bmr_kcal],
      &Map.get(entry, &1)
    )
  end

  defp delete_photo_object(%Photo{} = photo) do
    cond do
      photo.storage_key -> Storage.delete(photo.storage_key)
      photo.url -> Storage.delete_by_url(photo.url)
      true -> :ok
    end
  end

  # Form params arrive as string values; keep only positive numbers over the
  # selectable metrics.
  defp normalize_goals(goals) do
    goals
    |> Enum.flat_map(fn {k, v} ->
      key = to_string(k)

      with true <- key in Period.selectable_metrics(),
           value when is_number(value) and value > 0 <- parse_number(v) do
        [{key, value * 1.0}]
      else
        _ -> []
      end
    end)
    |> Map.new()
  end

  defp parse_number(v) when is_number(v), do: v

  defp parse_number(v) when is_binary(v) do
    case Float.parse(String.trim(v)) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_number(_), do: nil
end
