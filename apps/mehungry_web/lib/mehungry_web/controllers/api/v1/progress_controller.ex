defmodule MehungryWeb.Api.V1.ProgressController do
  @moduledoc """
  The self-tracking progress journal (spec §19, `/api/v1/me/progress/*`):
  periods (goals, tracked metrics, reset, nutritionist sharing), dated diary
  entries, and progress photos. Mirrors the `/profile?tab=progress` journal —
  every read/write delegates to `Mehungry.Progress` (the LiveView's exact
  domain functions; nothing is recomputed here). 🔒 — valid bearer token
  required.

  Distinct from §18's `GET /me/progress` (`MyNutritionistController`), the
  flat nutritionist-recorded measurement history, which is unchanged.

  All lookups are ownership-scoped on `conn.assigns.current_user.id` — a
  forged id can only produce 404, never another user's journal.
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Progress
  alias MehungryWeb.Api.V1.ProgressJSON, as: JSON

  action_fallback MehungryWeb.Api.V1.FallbackController

  @doc "List the user's periods, most recent first. Bootstraps the journal on first call."
  def index(conn, _params) do
    uid = uid(conn)
    {:ok, active} = Progress.ensure_journal(uid)

    json(
      conn,
      data(%{
        active_period_id: active.id,
        periods: Enum.map(Progress.list_periods(uid), &JSON.period/1)
      })
    )
  end

  @doc "A period's full dashboard payload: metrics, context, history, comparison, photo pins."
  def show(conn, %{"id" => id}) do
    uid = uid(conn)

    case Progress.get_period(uid, id) do
      nil ->
        {:error, :not_found}

      period ->
        json(
          conn,
          data(
            JSON.period_detail(
              period,
              Progress.measurement_history_for_period(period),
              Progress.progress_context(uid, period),
              Progress.comparison(period),
              Progress.photo_markers(period)
            )
          )
        )
    end
  end

  @doc """
  Ensure the journal exists and return the active period (idempotent). When
  `period` attrs are sent and the active period is self-tracked, they are
  applied as configuration (goals / tracked_metrics / title / snapshot).
  """
  def create(conn, params) do
    uid = uid(conn)

    with {:ok, active} <- Progress.ensure_journal(uid),
         {:ok, active} <- maybe_configure(uid, active, params["period"]) do
      json(conn, data(JSON.period(active)))
    end
  end

  @doc "Configure a self period: goals, tracked_metrics, title/notes, height/sex/age."
  def update(conn, %{"id" => id} = params) do
    with {:ok, period} <-
           Progress.configure_period(uid(conn), id, params["period"] || Map.delete(params, "id")) do
      json(conn, data(JSON.period(period)))
    end
  end

  @doc "Start over from 0: close the active period, open a fresh self period."
  def reset(conn, _params) do
    with {:ok, %{closed: closed, opened: opened}} <- Progress.reset_period(uid(conn)) do
      json(
        conn,
        data(%{closed: closed && JSON.period(closed), opened: JSON.period(opened)})
      )
    end
  end

  @doc "Make the period visible to the user's assigned nutritionist."
  def share(conn, %{"id" => id}) do
    with {:ok, period} <- Progress.share_period(uid(conn), id) do
      json(conn, data(JSON.period(period)))
    end
  end

  @doc "Revoke the nutritionist's visibility into the period."
  def unshare(conn, %{"id" => id}) do
    with {:ok, period} <- Progress.unshare_period(uid(conn), id) do
      json(conn, data(JSON.period(period)))
    end
  end

  @doc "The period's diary entries (photos embedded), oldest first."
  def entries(conn, %{"id" => id}) do
    uid = uid(conn)

    case Progress.get_period(uid, id) do
      nil ->
        {:error, :not_found}

      period ->
        json(conn, data(Enum.map(Progress.list_entries(uid, period.id), &JSON.entry/1)))
    end
  end

  @doc """
  Log (or re-log) a diary entry — one per date per period, so sending the same
  `entry_date` again updates it. `bmi`/`bmr_kcal` are derived server-side.
  """
  def upsert_entry(conn, %{"period_id" => period_id} = params) do
    entry_params = params["entry"] || Map.drop(params, ["period_id"])

    with {:ok, entry} <- Progress.log_entry(uid(conn), period_id, entry_params) do
      json(conn, data(JSON.entry(%{entry | photos: []})))
    end
  end

  def upsert_entry(_conn, _params), do: {:error, :bad_request}

  @doc "Delete a diary entry (its photos — rows and storage objects — go with it)."
  def delete_entry(conn, %{"id" => id}) do
    with {:ok, _} <- Progress.delete_entry(uid(conn), id) do
      send_resp(conn, :no_content, "")
    end
  end

  @doc """
  Attach an uploaded photo to an entry. `upload_id` is the **private-bucket**
  object key returned by the §11 presign flow (`kind: "progress_photo"`); only
  the key is stored — every read serves a fresh short-lived signed URL
  (`Progress.photo_url/1`). The client never supplies a raw URL.
  """
  def attach_photo(conn, %{"entry_id" => entry_id, "upload_id" => upload_id})
      when is_binary(upload_id) and upload_id != "" do
    attrs = %{"storage_key" => upload_id}

    with {:ok, photo} <- Progress.attach_photo(uid(conn), entry_id, attrs) do
      json(conn, data(JSON.photo(Progress.with_photo_url(photo))))
    end
  end

  def attach_photo(_conn, _params), do: {:error, :bad_request}

  @doc """
  Create (or return) the photo's public, revocable share link — the only way a
  progress photo becomes visible to anyone but its owner.
  """
  def share_photo(conn, %{"id" => id}) do
    with {:ok, photo} <- Progress.share_photo(uid(conn), id) do
      json(conn, data(JSON.photo(Progress.with_photo_url(photo))))
    end
  end

  @doc "Revoke the photo's public share link (the token stops resolving immediately)."
  def unshare_photo(conn, %{"id" => id}) do
    with {:ok, photo} <- Progress.unshare_photo(uid(conn), id) do
      json(conn, data(JSON.photo(Progress.with_photo_url(photo))))
    end
  end

  @doc "Delete a photo (row + storage object)."
  def delete_photo(conn, %{"id" => id}) do
    with {:ok, _} <- Progress.delete_photo(uid(conn), id) do
      send_resp(conn, :no_content, "")
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────────

  defp uid(conn), do: conn.assigns.current_user.id

  defp maybe_configure(_uid, active, nil), do: {:ok, active}
  defp maybe_configure(_uid, active, attrs) when map_size(attrs) == 0, do: {:ok, active}

  defp maybe_configure(uid, active, attrs) when is_map(attrs) do
    case Progress.configure_period(uid, active.id, attrs) do
      {:ok, period} -> {:ok, period}
      # A nutritionist-aligned active period isn't configurable — return it as-is.
      {:error, :not_self_period} -> {:ok, active}
      {:error, _} = error -> error
    end
  end
end
