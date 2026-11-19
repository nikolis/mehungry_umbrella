defmodule MehungryWeb.MealPlanModePrompt do
  @moduledoc """
  The "this week already has meals" choice every AI meal-plan trigger shows
  before generating: **fill gaps** (keep what is there) or **replace the week**
  (delete it and write the new plan). Shared by the consumer calendar and both
  nutritionist surfaces so the wording and the two modes cannot drift.

  The host LiveView parks the request, renders this, and handles two events:
  `mode_event` with `%{"mode" => "fill_gaps" | "replace_week"}` and
  `cancel_event`.
  """
  use Phoenix.Component
  use Gettext, backend: MehungryWeb.Gettext

  attr :existing, :integer, required: true, doc: "meals already in the target week"
  attr :mode_event, :string, required: true
  attr :cancel_event, :string, required: true
  attr :whose, :atom, default: :own, values: [:own, :client]

  def mode_prompt(assigns) do
    ~H"""
    <div
      id="meal-plan-mode-prompt"
      role="alertdialog"
      aria-labelledby="meal-plan-mode-title"
      class="mt-3 rounded-lg border border-amber-500/30 bg-amber-500/10 p-3"
    >
      <p id="meal-plan-mode-title" class="text-amber-300 text-sm font-semibold">
        <%= if @whose == :client do %>
          {ngettext(
            "This week already has %{count} meal on the client's calendar.",
            "This week already has %{count} meals on the client's calendar.",
            @existing
          )}
        <% else %>
          {ngettext(
            "This week already has %{count} meal.",
            "This week already has %{count} meals.",
            @existing
          )}
        <% end %>
      </p>
      <p class="text-parchment-dim text-xs mt-1">
        {gettext("What should the new plan do with them?")}
      </p>
      <div class="mt-3 flex flex-wrap gap-2">
        <button
          type="button"
          phx-click={@mode_event}
          phx-value-mode="fill_gaps"
          class="px-3 py-1.5 rounded-lg bg-basil/20 border border-basil/50 text-parchment text-xs font-semibold hover:bg-basil/30 transition"
        >
          {gettext("Fill the gaps — keep existing meals")}
        </button>
        <button
          type="button"
          phx-click={@mode_event}
          phx-value-mode="replace_week"
          data-confirm={
            ngettext(
              "This permanently deletes the %{count} meal in that week, including any entered by hand, and replaces it with the new plan. Continue?",
              "This permanently deletes all %{count} meals in that week, including any entered by hand, and replaces them with the new plan. Continue?",
              @existing
            )
          }
          class="px-3 py-1.5 rounded-lg border border-paprika/60 text-paprika-soft text-xs font-semibold hover:bg-paprika/10 transition"
        >
          {gettext("Replace the whole week")}
        </button>
        <button
          type="button"
          phx-click={@cancel_event}
          class="px-3 py-1.5 rounded-lg text-parchment-dim text-xs hover:text-parchment transition"
        >
          {gettext("Cancel")}
        </button>
      </div>
    </div>
    """
  end
end
