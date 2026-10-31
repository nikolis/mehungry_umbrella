defmodule MehungryWeb.OnboardingQuestionLive.Shared do
  @moduledoc """
  Shared markup + helpers for the two onboarding-question editors (admin and
  nutritionist). Both LiveViews delegate `render/1` here; they differ only in
  mount/scope/auth, so the index UI, modal, and reorder controls live once.

  Expected assigns: `:questions`, `:scope`, `:professional_id`, `:editing`
  (nil | %Question{}), `:heading`, `:subheading`.
  """
  use MehungryWeb, :html

  alias Mehungry.Onboarding.Question
  alias Phoenix.LiveView.JS

  def index(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <div class="flex items-center justify-between mb-2">
        <h1 class="text-xl font-display font-medium text-parchment">{@heading}</h1>
        <button
          phx-click="new"
          class="px-4 py-2 rounded-full bg-paprika hover:bg-paprika-soft text-ink text-sm font-semibold transition-colors"
        >
          + Add question
        </button>
      </div>
      <p class="text-sm text-parchment-dim mb-6">{@subheading}</p>

      <div :if={@questions == []} class="text-parchment-dim text-sm py-8 text-center">
        No questions yet. Click <span class="font-semibold">Add question</span> to create one.
      </div>

      <ul class="space-y-2">
        <li
          :for={{q, idx} <- Enum.with_index(@questions)}
          class="flex items-center gap-3 bg-ink-panel border border-ink-panel2 rounded-xl px-4 py-3"
        >
          <div class="flex flex-col">
            <button
              phx-click="move_up"
              phx-value-id={q.id}
              disabled={idx == 0}
              class="text-parchment-dim hover:text-parchment disabled:opacity-20 disabled:hover:text-parchment-dim"
            >
              <.icon name="hero-chevron-up" class="w-4 h-4" />
            </button>
            <button
              phx-click="move_down"
              phx-value-id={q.id}
              disabled={idx == length(@questions) - 1}
              class="text-parchment-dim hover:text-parchment disabled:opacity-20 disabled:hover:text-parchment-dim"
            >
              <.icon name="hero-chevron-down" class="w-4 h-4" />
            </button>
          </div>

          <div class="flex-1 min-w-0">
            <p class="text-parchment font-medium truncate">{q.prompt_en}</p>
            <p class="text-xs text-parchment-dim flex items-center gap-2 mt-0.5">
              <span>{type_label(q)}</span>
              <span :if={q.required} class="text-paprika">• required</span>
              <span :if={!q.active} class="text-parchment-dim/60">• hidden</span>
            </p>
          </div>

          <button
            phx-click="edit"
            phx-value-id={q.id}
            class="text-parchment-dim hover:text-parchment transition-colors p-1"
          >
            <.icon name="hero-pencil-square" class="w-4 h-4" />
          </button>
          <button
            phx-click="delete"
            phx-value-id={q.id}
            data-confirm="Delete this question? Existing answers to it will also be removed."
            class="text-parchment-dim hover:text-red-400 transition-colors p-1"
          >
            <.icon name="hero-trash" class="w-4 h-4" />
          </button>
        </li>
      </ul>

      <.modal :if={@editing} id="onboarding-question-modal" show on_cancel={JS.push("cancel")}>
        <.live_component
          module={MehungryWeb.OnboardingQuestionLive.FormComponent}
          id={"onboarding-question-form-#{@editing.id || "new"}"}
          title={if(@editing.id, do: "Edit question", else: "New question")}
          action={if(@editing.id, do: :edit, else: :new)}
          question={@editing}
        />
      </.modal>
    </div>
    """
  end

  def type_label(%Question{question_type: "value", value_kind: "number"}), do: "Number"
  def type_label(%Question{question_type: "value"}), do: "Free text"

  def type_label(%Question{question_type: "single_choice", options: options}),
    do: "Pick one of #{length(options)}"

  def type_label(%Question{question_type: "multi_choice", options: options}),
    do: "Pick any of #{length(options)}"
end
