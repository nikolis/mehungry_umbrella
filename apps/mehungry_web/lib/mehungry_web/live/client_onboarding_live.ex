defmodule MehungryWeb.ClientOnboardingLive do
  @moduledoc """
  Client-facing self-fill of a nutritionist's onboarding questionnaire. Mounted
  only for a user who actually has a client file with the given nutritionist; the
  answers are stored against that `ProfessionalClient` and surfaced back to the
  nutritionist on the client's file.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Onboarding
  alias Mehungry.Onboarding.Question
  alias Mehungry.Professionals

  @impl true
  def mount(%{"professional_id" => professional_id}, _session, socket) do
    professional_id = String.to_integer(professional_id)
    user = socket.assigns.current_user

    case Professionals.get_client_record_by_user(professional_id, user.id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("This questionnaire isn't available to you."))
         |> redirect(to: "/home")}

      record ->
        Onboarding.ensure_client_questions(professional_id)
        questions = Onboarding.list_active_questions("client", professional_id)

        {:ok,
         socket
         |> assign(:professional_client, record)
         |> assign(:questions, questions)
         |> assign(:answers, Onboarding.get_answers("professional_client", record.id))
         |> assign(:locale, Gettext.get_locale(MehungryWeb.Gettext))
         |> assign(:saved?, false)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-semibold mb-1">{gettext("Your onboarding questionnaire")}</h1>
      <p class="text-sm text-slate-400 mb-6">
        {gettext("Your nutritionist uses these answers to prepare for your first session.")}
      </p>

      <div
        :if={@saved?}
        class="mb-6 px-4 py-3 rounded-xl bg-green-500/10 border border-green-500/30 text-green-400 text-sm"
      >
        {gettext("Thanks — your answers have been saved. You can update them any time.")}
      </div>

      <div :if={@questions == []} class="text-slate-400 text-sm py-8 text-center">
        {gettext("Your nutritionist hasn't set up any questions yet.")}
      </div>

      <form :if={@questions != []} phx-submit="save" class="space-y-6">
        <div :for={q <- @questions} class="space-y-2">
          <label class="block text-sm font-semibold text-slate-200">
            {Question.prompt(q, @locale)}<span :if={q.required} class="text-paprika"> *</span>
          </label>
          <.question_input q={q} answer={Map.get(@answers, q.id)} locale={@locale} />
        </div>

        <button
          type="submit"
          phx-disable-with={gettext("Saving...")}
          class="px-6 py-2 rounded-full text-sm font-semibold bg-primary-500 text-white hover:bg-primary-600 transition-colors"
        >
          {gettext("Save answers")}
        </button>
      </form>
    </div>
    """
  end

  defp question_input(%{q: %Question{question_type: "value", value_kind: "number"}} = assigns) do
    ~H"""
    <input
      type="number"
      name={"answers[#{@q.id}][value_text]"}
      value={@answer && @answer.value_text}
      class="w-full rounded-lg border-2 border-slate-600 bg-transparent text-white px-4 py-2 focus:border-primary-500 focus:outline-none"
    />
    """
  end

  defp question_input(%{q: %Question{question_type: "value"}} = assigns) do
    ~H"""
    <textarea
      name={"answers[#{@q.id}][value_text]"}
      rows="2"
      class="w-full rounded-lg border-2 border-slate-600 bg-transparent text-white px-4 py-2 focus:border-primary-500 focus:outline-none"
    >{@answer && @answer.value_text}</textarea>
    """
  end

  defp question_input(%{q: %Question{question_type: "single_choice"}} = assigns) do
    assigns = assign(assigns, :selected, selected_keys(assigns.answer))

    ~H"""
    <div class="space-y-1">
      <label :for={opt <- @q.options} class="flex items-center gap-2 text-sm text-slate-300">
        <input
          type="radio"
          name={"answers[#{@q.id}][selected_options][]"}
          value={opt.key}
          checked={opt.key in @selected}
          class="accent-primary-500"
        />
        {Mehungry.Onboarding.QuestionOption.label(opt, @locale)}
      </label>
    </div>
    """
  end

  defp question_input(%{q: %Question{question_type: "multi_choice"}} = assigns) do
    assigns = assign(assigns, :selected, selected_keys(assigns.answer))

    ~H"""
    <div class="space-y-1">
      <label :for={opt <- @q.options} class="flex items-center gap-2 text-sm text-slate-300">
        <input
          type="checkbox"
          name={"answers[#{@q.id}][selected_options][]"}
          value={opt.key}
          checked={opt.key in @selected}
          class="accent-primary-500"
        />
        {Mehungry.Onboarding.QuestionOption.label(opt, @locale)}
      </label>
    </div>
    """
  end

  defp selected_keys(nil), do: []
  defp selected_keys(%{selected_options: keys}), do: keys || []

  @impl true
  def handle_event("save", params, socket) do
    answers = Map.get(params, "answers", %{})
    record = socket.assigns.professional_client

    Onboarding.upsert_answers("professional_client", record.id, answers, socket.assigns.questions)

    {:noreply,
     socket
     |> assign(:answers, Onboarding.get_answers("professional_client", record.id))
     |> assign(:saved?, true)}
  end
end
