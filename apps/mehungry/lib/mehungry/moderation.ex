defmodule Mehungry.Moderation do
  @moduledoc """
  Moderation of user-generated content (App Store Guideline 1.2): users report
  recipes, comments and other users; users block other users; the admin reviews
  both in `/professional/moderation`.

  Data-protection rules this module keeps (see `moderation_plan.md` in the
  mobile repo):

    * a reporter is never revealed to the reported user — nothing here returns
      `reporter` on a user-facing path;
    * blocks are one-way and silent;
    * resolved reports are purged after 12 months (`purge_resolved_reports/1`);
    * deleting an account deletes its blocks (FK cascade), un-attributes the
      reports it filed (FK nilify) and closes the open reports against it
      (`close_reports_against/2`, called from `Accounts.delete_user/1`).
  """
  import Ecto.Query

  alias Mehungry.Accounts
  alias Mehungry.Accounts.{User, UserFollow, UserProfile}
  alias Mehungry.Food.Recipe
  alias Mehungry.Moderation.{ContentReport, UserBlock}
  alias Mehungry.Posts.{Comment, CommentAnswer, CommentAnswerVote, CommentVote}
  alias Mehungry.Repo

  @retention_months 12

  # ── reports ──────────────────────────────────────────────────────────────

  @doc """
  File a report by `reporter` against a recipe, comment or user.

  `attrs` (string keys): `target_type`, `target_id`, `reason`, optional `note`.

  Returns `{:ok, report, :created}`, or `{:ok, report, :existing}` when the
  reporter already has an open report on the same target (no duplicate is
  stored). Errors: `{:error, changeset}` for a bad type/reason/note,
  `{:error, :not_found}` when the target does not exist,
  `{:error, :cannot_report_yourself}` for your own content.
  """
  def create_report(%User{id: reporter_id}, attrs) when is_map(attrs) do
    base =
      attrs
      |> Map.take(["target_type", "target_id", "reason", "note"])
      |> Map.put("reporter_id", reporter_id)

    changeset = ContentReport.changeset(%ContentReport{}, base)

    with {:ok, draft} <- Ecto.Changeset.apply_action(changeset, :insert),
         {:ok, owner_id, snapshot} <- resolve_target(draft.target_type, draft.target_id),
         :ok <- not_own_content(reporter_id, owner_id) do
      case open_report(reporter_id, draft.target_type, draft.target_id) do
        %ContentReport{} = existing ->
          {:ok, existing, :existing}

        nil ->
          base
          |> Map.merge(%{"target_user_id" => owner_id, "snapshot" => snapshot})
          |> insert_report(reporter_id, draft)
      end
    end
  end

  defp insert_report(attrs, reporter_id, draft) do
    case %ContentReport{} |> ContentReport.changeset(attrs) |> Repo.insert() do
      {:ok, report} ->
        # Tell the admin right away — reports are to be reviewed within 24 hours.
        Mehungry.ObanWorkers.ModerationReportMailerWorker.enqueue(report.id)
        {:ok, report, :created}

      # Lost a race with an identical concurrent request — hand back the winner.
      {:error, %Ecto.Changeset{} = changeset} ->
        case open_report(reporter_id, draft.target_type, draft.target_id) do
          %ContentReport{} = existing -> {:ok, existing, :existing}
          nil -> {:error, changeset}
        end
    end
  end

  defp open_report(reporter_id, type, id) do
    Repo.one(
      from r in ContentReport,
        where:
          r.reporter_id == ^reporter_id and r.target_type == ^type and r.target_id == ^id and
            r.status == "open",
        limit: 1
    )
  end

  defp not_own_content(reporter_id, reporter_id), do: {:error, :cannot_report_yourself}
  defp not_own_content(_reporter_id, _owner_id), do: :ok

  # → {:ok, owner_user_id, snapshot_text} | {:error, :not_found}
  defp resolve_target("recipe", id) do
    case Repo.get(Recipe, id) do
      nil -> {:error, :not_found}
      recipe -> {:ok, recipe.user_id, join_snapshot([recipe.title, recipe.description])}
    end
  end

  defp resolve_target("comment", id) do
    case Repo.get(Comment, id) do
      nil -> {:error, :not_found}
      comment -> {:ok, comment.user_id, comment.text}
    end
  end

  defp resolve_target("user", id) do
    case Repo.get(User, id) do
      nil ->
        {:error, :not_found}

      user ->
        profile = Repo.get_by(UserProfile, user_id: user.id)
        {:ok, user.id, join_snapshot([display_name(user, profile), profile && profile.intro])}
    end
  end

  defp join_snapshot(parts) do
    parts
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join("\n\n")
  end

  @doc "The name a user is shown under: profile alias, else account name, else email."
  def display_name(%User{} = user, profile \\ nil) do
    (profile && profile.alias) || user.name || user.email
  end

  @doc "Reports with `status` (default open), oldest first, reporter + author preloaded."
  def list_reports(status \\ "open") do
    Repo.all(
      from r in ContentReport,
        where: r.status == ^status,
        order_by: [asc: r.inserted_at, asc: r.id],
        preload: [:reporter, :target_user]
    )
  end

  def get_report!(id), do: Repo.get!(ContentReport, id)

  def open_report_count do
    Repo.aggregate(from(r in ContentReport, where: r.status == "open"), :count)
  end

  @doc "Whether a report's target still exists (the admin page links to it or shows “deleted”)."
  def target_exists?(%ContentReport{target_type: "recipe", target_id: id}),
    do: Repo.exists?(from r in Recipe, where: r.id == ^id)

  def target_exists?(%ContentReport{target_type: "comment", target_id: id}),
    do: Repo.exists?(from c in Comment, where: c.id == ^id)

  def target_exists?(%ContentReport{target_type: "user", target_id: id}),
    do: Repo.exists?(from u in User, where: u.id == ^id)

  @doc "Open reports against, and blocks received by, a user — shown beside each report."
  def user_stats(nil), do: %{open_reports: 0, blocks_received: 0}

  def user_stats(user_id) when is_integer(user_id) do
    %{
      open_reports:
        Repo.aggregate(
          from(r in ContentReport, where: r.target_user_id == ^user_id and r.status == "open"),
          :count
        ),
      blocks_received:
        Repo.aggregate(from(b in UserBlock, where: b.blocked_id == ^user_id), :count)
    }
  end

  # ── admin actions ────────────────────────────────────────────────────────

  @doc "Close a report without acting on the content."
  def dismiss_report(%ContentReport{} = report, admin_note \\ nil) do
    resolve([report.id], "dismissed", "none", admin_note)
    {:ok, get_report!(report.id)}
  end

  @doc """
  Delete the reported recipe or comment and close every open report on it (and,
  for a recipe, on its comments, which die with it). `{:error, :not_removable}`
  for a report against a user — use `remove_account/2`.
  """
  def remove_content(report, admin_note \\ nil)

  def remove_content(%ContentReport{target_type: "user"}, _admin_note),
    do: {:error, :not_removable}

  def remove_content(%ContentReport{target_type: type, target_id: id} = report, admin_note) do
    result =
      Repo.transaction(fn ->
        report_ids = open_report_ids_on(type, id)

        case delete_target(type, id) do
          :ok ->
            resolve(
              Enum.uniq([report.id | report_ids]),
              "actioned",
              "content_removed",
              admin_note
            )

            get_report!(report.id)

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)

    with {:ok, resolved} <- result do
      notify_author_of_removal(resolved)
      result
    end
  end

  # Tell the author what was removed and why (the reason category only) — never
  # who reported it. Sent after the transaction commits; a delivery problem must
  # not undo the removal.
  defp notify_author_of_removal(%ContentReport{target_user_id: nil}), do: :ok

  defp notify_author_of_removal(%ContentReport{} = report) do
    Mehungry.Notifications.emit(report.target_user_id, "content_removed",
      data: %{
        "target_type" => report.target_type,
        "reason" => report.reason,
        "preview" => report.snapshot |> to_string() |> String.slice(0, 120)
      }
    )

    :ok
  end

  @doc """
  Delete the account of the reported content's author (the existing
  `Accounts.delete_user/1`, which removes all their content) and close every
  open report against them.
  """
  def remove_account(report, admin_note \\ nil)

  def remove_account(%ContentReport{target_user_id: nil}, _admin_note),
    do: {:error, :not_found}

  def remove_account(%ContentReport{target_user_id: user_id} = report, admin_note) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      user ->
        Repo.transaction(fn ->
          # Resolve first: deleting the user nilifies `target_user_id`.
          ids =
            Repo.all(
              from r in ContentReport,
                where: r.target_user_id == ^user_id and r.status == "open",
                select: r.id
            )

          resolve(Enum.uniq([report.id | ids]), "actioned", "account_removed", admin_note)

          case Accounts.delete_user(user) do
            {:ok, _} -> get_report!(report.id)
            {:error, reason} -> Repo.rollback(reason)
            other -> Repo.rollback(other)
          end
        end)
    end
  end

  @doc """
  Close the open reports against a user whose account is going away on its own
  (self-deletion) — the content is gone, nothing is left to review. Called from
  `Accounts.delete_user/1`; a no-op after `remove_account/2` already resolved them.
  """
  def close_reports_against(user_id, admin_note \\ "Account deleted") when is_integer(user_id) do
    ids =
      Repo.all(
        from r in ContentReport,
          where: r.target_user_id == ^user_id and r.status == "open",
          select: r.id
      )

    resolve(ids, "dismissed", "none", admin_note)
    :ok
  end

  defp open_report_ids_on("recipe", recipe_id) do
    comment_ids = Repo.all(from c in Comment, where: c.recipe_id == ^recipe_id, select: c.id)

    Repo.all(
      from r in ContentReport,
        where:
          r.status == "open" and
            ((r.target_type == "recipe" and r.target_id == ^recipe_id) or
               (r.target_type == "comment" and r.target_id in ^comment_ids)),
        select: r.id
    )
  end

  defp open_report_ids_on(type, id) do
    Repo.all(
      from r in ContentReport,
        where: r.status == "open" and r.target_type == ^type and r.target_id == ^id,
        select: r.id
    )
  end

  # Already gone (deleted by its author since the report) counts as removed.
  defp delete_target("recipe", id) do
    case Repo.get(Recipe, id) do
      nil ->
        :ok

      _recipe ->
        delete_comments(Repo.all(from c in Comment, where: c.recipe_id == ^id, select: c.id))

        case Mehungry.Food.delete_recipe(id) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp delete_target("comment", id) do
    delete_comments([id])
    :ok
  end

  # Leaf rows first — the comment FKs do not cascade (same order as
  # `Accounts.delete_user/1`).
  defp delete_comments([]), do: :ok

  defp delete_comments(comment_ids) do
    answer_ids =
      Repo.all(from a in CommentAnswer, where: a.comment_id in ^comment_ids, select: a.id)

    Repo.delete_all(from v in CommentAnswerVote, where: v.comment_answer_id in ^answer_ids)
    Repo.delete_all(from v in CommentVote, where: v.comment_id in ^comment_ids)
    Repo.delete_all(from a in CommentAnswer, where: a.comment_id in ^comment_ids)
    Repo.delete_all(from c in Comment, where: c.id in ^comment_ids)
    :ok
  end

  defp resolve([], _status, _resolution, _note), do: :ok

  defp resolve(ids, status, resolution, admin_note) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.update_all(
      from(r in ContentReport, where: r.id in ^ids and r.status == "open"),
      set: [
        status: status,
        resolution: resolution,
        admin_note: admin_note,
        resolved_at: now,
        updated_at: now
      ]
    )

    :ok
  end

  @doc """
  Delete reports resolved more than #{@retention_months} months ago (data
  minimisation). Open reports are never purged. Returns the number deleted.
  """
  def purge_resolved_reports(months \\ @retention_months) do
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-months * 30 * 24 * 3600, :second)

    {count, _} =
      Repo.delete_all(
        from r in ContentReport, where: r.status != "open" and r.resolved_at < ^cutoff
      )

    count
  end

  # ── blocks ───────────────────────────────────────────────────────────────

  @doc """
  `blocker` blocks user `blocked_id`: they stop seeing that user's recipes and
  comments, and any follow between the two (either direction) is removed.
  Idempotent. `{:error, :cannot_block_yourself}` / `{:error, :not_found}`.
  """
  def block_user(%User{id: id}, id), do: {:error, :cannot_block_yourself}

  def block_user(%User{id: blocker_id}, blocked_id) when is_integer(blocked_id) do
    if Repo.exists?(from u in User, where: u.id == ^blocked_id) do
      %UserBlock{}
      |> UserBlock.changeset(%{blocker_id: blocker_id, blocked_id: blocked_id})
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:blocker_id, :blocked_id])

      Repo.delete_all(
        from f in UserFollow,
          where:
            (f.user_id == ^blocker_id and f.follow_id == ^blocked_id) or
              (f.user_id == ^blocked_id and f.follow_id == ^blocker_id)
      )

      :ok
    else
      {:error, :not_found}
    end
  end

  @doc "Remove a block. Idempotent."
  def unblock_user(%User{id: blocker_id}, blocked_id) when is_integer(blocked_id) do
    Repo.delete_all(
      from b in UserBlock, where: b.blocker_id == ^blocker_id and b.blocked_id == ^blocked_id
    )

    :ok
  end

  @doc "Whether `viewer` (a user or nil) has blocked `user_id`."
  def blocked?(nil, _user_id), do: false

  def blocked?(%User{id: blocker_id}, user_id) when is_integer(user_id) do
    Repo.exists?(
      from b in UserBlock, where: b.blocker_id == ^blocker_id and b.blocked_id == ^user_id
    )
  end

  @doc "Ids of the users `viewer` has blocked (`[]` for an anonymous viewer)."
  def blocked_ids(nil), do: []

  def blocked_ids(%User{id: blocker_id}) do
    Repo.all(from b in UserBlock, where: b.blocker_id == ^blocker_id, select: b.blocked_id)
  end

  @doc """
  Drop the items of `list` authored by someone `viewer` blocked. `author_id`
  maps an item to its author's user id (nil → kept).
  """
  def reject_blocked(list, viewer, author_id) when is_function(author_id, 1) do
    case blocked_ids(viewer) do
      [] -> list
      ids -> Enum.reject(list, &(author_id.(&1) in ids))
    end
  end

  @doc "The users `user` has blocked, newest first: `[%{user:, alias:, blocked_at:}]`."
  def list_blocks(%User{id: blocker_id}) do
    Repo.all(
      from b in UserBlock,
        join: u in User,
        on: u.id == b.blocked_id,
        left_join: p in UserProfile,
        on: p.user_id == u.id,
        where: b.blocker_id == ^blocker_id,
        order_by: [desc: b.inserted_at, desc: b.id],
        select: {u, p, b.inserted_at}
    )
    |> Enum.map(fn {user, profile, at} ->
      %{user: user, alias: display_name(user, profile), blocked_at: at}
    end)
  end

  # ── admin: blocks overview ───────────────────────────────────────────────

  @doc """
  Users who have been blocked, most-blocked first:
  `[%{user:, blocks_received:, open_reports:}]`. The admin view is organised
  around who is *being* blocked, not who blocked whom.
  """
  def blocks_received do
    rows =
      Repo.all(
        from b in UserBlock,
          join: u in User,
          on: u.id == b.blocked_id,
          group_by: u.id,
          order_by: [desc: count(b.id), asc: u.id],
          select: {u, count(b.id)}
      )

    open =
      Repo.all(
        from r in ContentReport,
          where: r.status == "open" and not is_nil(r.target_user_id),
          group_by: r.target_user_id,
          select: {r.target_user_id, count(r.id)}
      )
      |> Map.new()

    Enum.map(rows, fn {user, count} ->
      %{user: user, blocks_received: count, open_reports: Map.get(open, user.id, 0)}
    end)
  end

  @doc "Who blocked `user_id`, newest first: `[%{user:, blocked_at:}]` (admin drill-down)."
  def blockers_of(user_id) when is_integer(user_id) do
    Repo.all(
      from b in UserBlock,
        join: u in User,
        on: u.id == b.blocker_id,
        where: b.blocked_id == ^user_id,
        order_by: [desc: b.inserted_at, desc: b.id],
        select: {u, b.inserted_at}
    )
    |> Enum.map(fn {user, at} -> %{user: user, blocked_at: at} end)
  end
end
