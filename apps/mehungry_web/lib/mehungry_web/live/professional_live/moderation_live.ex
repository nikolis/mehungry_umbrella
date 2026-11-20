defmodule MehungryWeb.ProfessionalLive.ModerationLive do
  @moduledoc """
  Admin review of user-generated-content moderation (App Store Guideline 1.2),
  backed by `Mehungry.Moderation`.

    * **Reports** — the queue of reports users filed against recipes, comments
      and users, oldest first. Each can be dismissed, or acted on by removing the
      content or the author's account.
    * **Blocks** — which users are being blocked, most-blocked first, with a
      drill-down to who blocked them. Read-only; organised around the *blocked*
      user so it serves spotting abusive accounts, not browsing who blocked whom.

  Admin-only: mounted in the `/professional` live session behind
  `MehungryWeb.AdminAuthLive`.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Moderation
  alias Mehungry.Repo

  @statuses ~w(open actioned dismissed)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(tab: "reports", status: "open", expanded: nil, blockers: [])
     |> load()}
  end

  @impl true
  def handle_event("tab", %{"tab" => tab}, socket) when tab in ["reports", "blocks"] do
    {:noreply, socket |> assign(:tab, tab) |> load()}
  end

  def handle_event("status", %{"status" => status}, socket) when status in @statuses do
    {:noreply, socket |> assign(:status, status) |> load()}
  end

  def handle_event("resolve", %{"report_id" => id, "action" => action} = params, socket) do
    report = Moderation.get_report!(id)
    note = blank_to_nil(params["admin_note"])

    result =
      case action do
        "dismiss" -> Moderation.dismiss_report(report, note)
        "remove_content" -> Moderation.remove_content(report, note)
        "remove_account" -> Moderation.remove_account(report, note)
      end

    socket =
      case result do
        {:ok, _} -> put_flash(socket, :info, flash_for(action))
        {:error, reason} -> put_flash(socket, :error, "Could not complete: #{inspect(reason)}")
      end

    {:noreply, load(socket)}
  end

  def handle_event("toggle_blockers", %{"id" => id}, socket) do
    id = String.to_integer(id)

    socket =
      if socket.assigns.expanded == id do
        assign(socket, expanded: nil, blockers: [])
      else
        assign(socket, expanded: id, blockers: Moderation.blockers_of(id))
      end

    {:noreply, socket}
  end

  defp load(socket) do
    socket
    |> assign(:open_count, Moderation.open_report_count())
    |> assign(:reports, Enum.map(Moderation.list_reports(socket.assigns.status), &decorate/1))
    |> assign(:blocked, Moderation.blocks_received())
  end

  # Everything the row needs beyond the report itself.
  defp decorate(report) do
    exists? = Moderation.target_exists?(report)

    %{
      report: report,
      exists?: exists?,
      link: if(exists?, do: target_link(report)),
      stats: Moderation.user_stats(report.target_user_id)
    }
  end

  defp target_link(%{target_type: "recipe", target_id: id}), do: "/show_recipe/#{id}"
  defp target_link(%{target_type: "user", target_id: id}), do: "/professional/user/#{id}"

  defp target_link(%{target_type: "comment", target_id: id}) do
    case Repo.get(Mehungry.Posts.Comment, id) do
      %{recipe_id: recipe_id} when not is_nil(recipe_id) -> "/show_recipe/#{recipe_id}"
      _ -> nil
    end
  end

  defp flash_for("dismiss"), do: "Report dismissed."
  defp flash_for("remove_content"), do: "Content removed and its author notified."
  defp flash_for("remove_account"), do: "Account removed."

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp user_label(nil), do: "deleted account"
  defp user_label(user), do: user.name || user.email

  defp reason_label("spam"), do: "Spam"
  defp reason_label("harassment"), do: "Harassment or hate"
  defp reason_label("sexual"), do: "Sexual content"
  defp reason_label("dangerous_advice"), do: "Dangerous or misleading advice"
  defp reason_label(_), do: "Other"

  defp stamp(nil), do: "—"
  defp stamp(dt), do: Calendar.strftime(dt, "%d %b %Y, %H:%M")

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-ink">
      <div class="container mx-auto px-4 py-6 max-w-4xl">
        <div class="mb-6">
          <h1 class="text-2xl font-bold text-white flex items-center gap-3">
            <.icon name="hero-flag" class="w-7 h-7 text-paprika flex-shrink-0" /> Moderation
          </h1>
          <p class="text-parchment-dim text-sm mt-1">
            {@open_count} open report{if @open_count != 1, do: "s"} — review within 24 hours.
          </p>
        </div>

        <div class="flex gap-2 mb-5">
          <button
            :for={{tab, label} <- [{"reports", "Reports"}, {"blocks", "Blocks"}]}
            id={"tab-#{tab}"}
            phx-click="tab"
            phx-value-tab={tab}
            class={[
              "px-4 py-2 rounded-lg text-sm font-medium transition",
              if(@tab == tab,
                do: "bg-paprika text-white",
                else: "bg-ink-panel text-parchment hover:text-white"
              )
            ]}
          >
            {label}
          </button>
        </div>

        <div :if={@tab == "reports"}>
          <div class="flex gap-2 mb-4">
            <button
              :for={status <- ["open", "actioned", "dismissed"]}
              id={"status-#{status}"}
              phx-click="status"
              phx-value-status={status}
              class={[
                "px-3 py-1 rounded-full text-xs font-medium border transition",
                if(@status == status,
                  do: "border-paprika text-paprika-soft bg-paprika/10",
                  else: "border-ink-panel2 text-parchment-dim hover:text-white"
                )
              ]}
            >
              {String.capitalize(status)}
            </button>
          </div>

          <div
            :if={@reports == []}
            class="bg-ink-panel border border-ink-panel2 rounded-xl p-12 text-center"
          >
            <.icon name="hero-inbox" class="w-10 h-10 text-parchment-dim mx-auto mb-3" />
            <p class="text-parchment-dim">No {@status} reports.</p>
          </div>

          <div class="space-y-3">
            <div
              :for={%{report: r} = row <- @reports}
              id={"report-#{r.id}"}
              class="bg-ink-panel border border-ink-panel2 rounded-xl p-5"
            >
              <div class="flex flex-wrap items-center gap-2 mb-3">
                <span class="text-xs bg-paprika/10 text-paprika-soft border border-paprika/20 px-2 py-0.5 rounded-full">
                  {r.target_type}
                </span>
                <span class="text-xs bg-ink-panel2 text-parchment border border-ink-panel2 px-2 py-0.5 rounded-full">
                  {reason_label(r.reason)}
                </span>
                <span class="text-xs text-parchment-dim">#{r.id} · {stamp(r.inserted_at)}</span>
                <a
                  :if={row.link}
                  href={row.link}
                  target="_blank"
                  class="ml-auto text-xs text-paprika-soft hover:underline"
                >
                  Open live content
                </a>
                <span :if={!row.exists?} class="ml-auto text-xs text-parchment-dim">
                  content deleted
                </span>
              </div>

              <p class="text-white text-sm leading-relaxed whitespace-pre-wrap border-l-2 border-ink-panel2 pl-3">
                {r.snapshot || "(no text)"}
              </p>

              <p :if={r.note} class="text-parchment text-sm mt-3">
                <span class="text-parchment-dim">Reporter's note:</span> {r.note}
              </p>

              <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-1 mt-3 text-xs text-parchment-dim">
                <div>Author: <span class="text-parchment">{user_label(r.target_user)}</span></div>
                <div>
                  Reported by: <span class="text-parchment">{user_label(r.reporter)}</span>
                </div>
                <div>
                  Open reports against author:
                  <span class="text-parchment">{row.stats.open_reports}</span>
                </div>
                <div>
                  Blocks received by author:
                  <span class="text-parchment">{row.stats.blocks_received}</span>
                </div>
              </dl>

              <form
                :if={r.status == "open"}
                id={"resolve-#{r.id}"}
                phx-submit="resolve"
                class="mt-4 flex flex-col gap-3"
              >
                <input type="hidden" name="report_id" value={r.id} />
                <input
                  type="text"
                  name="admin_note"
                  maxlength="2000"
                  placeholder="Admin note (optional)"
                  class="w-full rounded-lg bg-ink border border-ink-panel2 text-sm text-white px-3 py-2"
                />
                <div class="flex flex-wrap gap-2">
                  <button
                    type="submit"
                    name="action"
                    value="dismiss"
                    class="px-3 py-1.5 rounded-lg text-sm bg-ink-panel2 text-parchment hover:text-white"
                  >
                    Dismiss
                  </button>
                  <button
                    :if={r.target_type != "user"}
                    type="submit"
                    name="action"
                    value="remove_content"
                    data-confirm={"Permanently delete this #{r.target_type}? Its author will be notified."}
                    class="px-3 py-1.5 rounded-lg text-sm bg-red-500/10 text-red-300 hover:bg-red-500/20"
                  >
                    Remove content
                  </button>
                  <button
                    :if={r.target_user}
                    type="submit"
                    name="action"
                    value="remove_account"
                    data-confirm={"Permanently delete the account of #{user_label(r.target_user)} and everything they posted? This cannot be undone."}
                    class="px-3 py-1.5 rounded-lg text-sm bg-red-500/20 text-red-200 hover:bg-red-500/30"
                  >
                    Remove account
                  </button>
                </div>
              </form>

              <p :if={r.status != "open"} class="text-xs text-parchment-dim mt-4">
                {String.capitalize(r.status)} · {r.resolution} · {stamp(r.resolved_at)}
                <span :if={r.admin_note}> · {r.admin_note}</span>
              </p>
            </div>
          </div>
        </div>

        <div :if={@tab == "blocks"}>
          <p class="text-parchment-dim text-sm mb-4">
            Users who have been blocked by others, most-blocked first.
          </p>

          <div
            :if={@blocked == []}
            class="bg-ink-panel border border-ink-panel2 rounded-xl p-12 text-center"
          >
            <p class="text-parchment-dim">Nobody has been blocked.</p>
          </div>

          <div class="space-y-2">
            <div
              :for={row <- @blocked}
              id={"blocked-#{row.user.id}"}
              class="bg-ink-panel border border-ink-panel2 rounded-xl p-4"
            >
              <div class="flex flex-wrap items-center gap-3">
                <a
                  href={"/professional/user/#{row.user.id}"}
                  class="text-white text-sm font-medium hover:underline"
                >
                  {user_label(row.user)}
                </a>
                <span class="text-xs text-parchment-dim">
                  blocked by {row.blocks_received} · open reports: {row.open_reports}
                </span>
                <button
                  phx-click="toggle_blockers"
                  phx-value-id={row.user.id}
                  class="ml-auto text-xs text-paprika-soft hover:underline"
                >
                  {if @expanded == row.user.id, do: "Hide", else: "Who blocked them"}
                </button>
              </div>

              <ul :if={@expanded == row.user.id} class="mt-3 space-y-1 text-xs text-parchment">
                <li :for={b <- @blockers}>
                  {user_label(b.user)} <span class="text-parchment-dim">· {stamp(b.blocked_at)}</span>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
