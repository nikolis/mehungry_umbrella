defmodule MehungryWeb.ProfessionalLive.IdentityReviewComponent do
  @moduledoc """
  Human-verification queue for scientific-identity candidates produced by
  identity resolution. Lists `Food.list_pending_verification/1` (status
  `candidate`, lowest-confidence first) and lets an admin Verify or Reject each.

  Self-contained: its stream, pagination and events are `phx-target={@myself}`
  so they never collide with the host `SciencePipeline` LiveView (which reuses the
  same `reject`/`load-more` event names). Verifying an identity is what promotes it
  to `verified` — the status the literature crawler reads.
  """
  use MehungryWeb, :live_component

  alias Mehungry.Food

  @per_page 25

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:page, fn -> 1 end)
      |> assign_new(:skipped_page, fn -> 1 end)
      |> assign_new(:streamed, fn -> false end)

    socket =
      if socket.assigns.streamed do
        socket
      else
        socket
        |> assign(:streamed, true)
        |> stream(:identities, Food.list_pending_verification(limit: @per_page, offset: 0))
        |> stream(:skipped, Food.list_skipped_resolutions(limit: @per_page, offset: 0))
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("verify", %{"id" => id}, socket) do
    {:ok, _} = Food.verify_identity(String.to_integer(id), socket.assigns[:current_user_id])
    {:noreply, stream_delete_by_dom_id(socket, :identities, "identities-#{id}")}
  end

  @impl true
  def handle_event("reject", %{"id" => id}, socket) do
    {:ok, _} = Food.reject_identity(String.to_integer(id))
    {:noreply, stream_delete_by_dom_id(socket, :identities, "identities-#{id}")}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    page = socket.assigns.page + 1
    offset = (page - 1) * @per_page

    {:noreply,
     socket
     |> assign(:page, page)
     |> stream(:identities, Food.list_pending_verification(limit: @per_page, offset: offset))}
  end

  @impl true
  def handle_event("load-more-skipped", _params, socket) do
    page = socket.assigns.skipped_page + 1
    offset = (page - 1) * @per_page

    {:noreply,
     socket
     |> assign(:skipped_page, page)
     |> stream(:skipped, Food.list_skipped_resolutions(limit: @per_page, offset: offset))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <h2 class="text-lg font-medium text-parchment mb-2">Identity verification</h2>
      <p class="text-parchment-dim text-sm mb-3">
        Resolved scientific names awaiting sign-off, lowest confidence first.
        <span class="font-medium">Verify</span>
        promotes it to the identity the literature crawler uses;
        <span class="font-medium">Reject</span>
        dismisses it. Both leave the queue.
      </p>

      <div id={"#{@id}-list"} phx-update="stream" class="divide-y divide-ink-panel2">
        <div
          :for={{dom_id, identity} <- @streams.identities}
          id={dom_id}
          class="py-3 flex flex-wrap items-center gap-3 justify-between"
        >
          <div class="min-w-0 flex-1">
            <div class="text-parchment font-medium truncate">
              {identity.ingredient.name}
              <span class="text-parchment-dim">is</span>
              <em>{identity.scientific_name}</em>
              <span :if={identity.rank} class="text-parchment-dim">({identity.rank})</span>
            </div>
            <div class="text-xs text-parchment-dim">
              confidence: {confidence_label(identity.confidence)} · source: {identity.source || "—"}
              <span :if={identity.ncbi_taxonomy_id}>· NCBI taxon: {identity.ncbi_taxonomy_id}</span>
            </div>
          </div>

          <div class="flex items-center gap-2">
            <button
              type="button"
              phx-click="verify"
              phx-value-id={identity.id}
              phx-target={@myself}
              class="px-3 py-1.5 rounded bg-basil text-ink text-sm font-medium hover:opacity-90"
            >
              Verify
            </button>
            <button
              type="button"
              phx-click="reject"
              phx-value-id={identity.id}
              phx-target={@myself}
              data-confirm="Reject this identity? It won't be used and the ingredient stays unverified."
              class="px-3 py-1.5 rounded border border-ink-panel2 text-parchment text-sm font-medium hover:opacity-90"
            >
              Reject
            </button>
          </div>
        </div>
      </div>

      <div class="mt-4 flex items-center gap-3">
        <button
          type="button"
          phx-click="load-more"
          phx-target={@myself}
          class="px-3 py-1.5 rounded border border-ink-panel2 text-parchment text-sm font-medium hover:opacity-90"
        >
          Load more
        </button>
        <span class="text-parchment-dim text-xs">
          Verified and rejected rows leave this list. Nothing here means the queue is clear.
        </span>
      </div>

      <div class="mt-8 border-t border-ink-panel2 pt-6">
        <h3 class="text-base font-medium text-parchment mb-2">Skipped (no identity)</h3>
        <p class="text-parchment-dim text-sm mb-3">
          Ingredients that were processed but produced no scientific identity, and why.
          Read-only — nothing to action here.
        </p>

        <div id={"#{@id}-skipped"} phx-update="stream" class="divide-y divide-ink-panel2">
          <div
            :for={{dom_id, attempt} <- @streams.skipped}
            id={dom_id}
            class="py-3 flex flex-wrap items-center gap-3 justify-between"
          >
            <div class="min-w-0 flex-1">
              <div class="text-parchment font-medium truncate">
                {attempt.ingredient.name}
              </div>
              <div class="text-xs text-parchment-dim">
                {reason_label(attempt.outcome)}
                <span :if={attempt.detail}>· {attempt.detail}</span>
              </div>
            </div>
            <span class={"text-xs font-medium #{outcome_class(attempt.outcome)}"}>
              {attempt.outcome}
            </span>
          </div>
        </div>

        <div class="mt-4 flex items-center gap-3">
          <button
            type="button"
            phx-click="load-more-skipped"
            phx-target={@myself}
            class="px-3 py-1.5 rounded border border-ink-panel2 text-parchment text-sm font-medium hover:opacity-90"
          >
            Load more
          </button>
          <span class="text-parchment-dim text-xs">
            Empty means every processed ingredient resolved to an identity.
          </span>
        </div>
      </div>
    </section>
    """
  end

  # ── View helpers ───────────────────────────────────────────────────────────

  defp confidence_label(nil), do: "—"
  defp confidence_label(c) when is_float(c), do: :erlang.float_to_binary(c, decimals: 2)
  defp confidence_label(c), do: to_string(c)

  defp reason_label("no_scientific_name"), do: "No scientific name in USDA data"
  defp reason_label("error"), do: "Resolution error"
  defp reason_label(other), do: other

  defp outcome_class("error"), do: "text-red-400"
  defp outcome_class(_), do: "text-parchment-dim"
end
