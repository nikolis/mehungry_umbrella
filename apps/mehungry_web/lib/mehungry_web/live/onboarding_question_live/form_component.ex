defmodule MehungryWeb.OnboardingQuestionLive.FormComponent do
  @moduledoc """
  Shared create/edit form for an `Onboarding.Question`, used by both the admin
  editor (`user` / `client_default` scopes) and the nutritionist editor
  (`client` scope). The owning scope + `professional_id` are preset on the
  `%Question{}` the parent hands in, so they aren't editable here.

  Choices are managed with the app's `sort_param`/`drop_param` convention: the
  "Add"/"Remove" buttons submit a `question[_action]` sentinel that rebuilds the
  in-memory changeset (nothing persists until Save).
  """
  use MehungryWeb, :live_component

  alias Mehungry.Onboarding
  alias Mehungry.Onboarding.Question

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>{@title}</.header>

      <.simple_form
        for={@form}
        id="onboarding-question-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:prompt_en]} label="Question (English)" />
        <.input field={@form[:prompt_el]} label="Question (Greek)" />

        <.input
          field={@form[:question_type]}
          type="select"
          label="Answer type"
          options={[
            {"Free text / number (value)", "value"},
            {"Multiple choice — pick one", "single_choice"},
            {"Multiple choice — pick many", "multi_choice"}
          ]}
        />

        <.input
          :if={@form[:question_type].value == "value"}
          field={@form[:value_kind]}
          type="select"
          label="Value kind"
          options={[{"Text", "text"}, {"Number", "number"}]}
        />

        <div :if={Question.choice_type?(@form[:question_type].value)} class="space-y-3">
          <p class="text-sm font-semibold text-parchment-dim">Choices</p>
          <.inputs_for :let={opt} field={@form[:options]}>
            <div class="flex flex-col sm:flex-row sm:items-end gap-3 bg-black/20 border border-ink-panel2 rounded-xl p-3">
              <input type="hidden" name="question[options_sort][]" value={opt.index} />
              <input type="hidden" name={opt[:key].name} value={opt[:key].value} />
              <div class="flex-1">
                <.input field={opt[:label_en]} label="Choice (English)" />
              </div>
              <div class="flex-1">
                <.input field={opt[:label_el]} label="Choice (Greek)" />
              </div>
              <button
                type="submit"
                name="question[_action]"
                value={"remove_option:#{opt.index}"}
                class="self-end text-parchment-dim hover:text-red-400 transition-colors p-1"
              >
                <.icon name="hero-x-mark" class="w-4 h-4" />
              </button>
            </div>
          </.inputs_for>

          <button
            type="submit"
            name="question[_action]"
            value="add_option"
            class="inline-flex items-center gap-1 px-3 py-1.5 rounded-full border border-ink-panel2 text-parchment-dim hover:bg-ink-panel2 hover:text-parchment text-xs font-semibold transition-colors"
          >
            + Add choice
          </button>
        </div>

        <.input field={@form[:required]} type="checkbox" label="Required" />
        <.input field={@form[:active]} type="checkbox" label="Active (shown in onboarding)" />

        <:actions>
          <.button phx-disable-with="Saving...">Save question</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{question: question} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(Onboarding.change_question(question))}
  end

  @impl true
  def handle_event("validate", %{"question" => params}, socket) do
    changeset =
      socket.assigns.question
      |> Onboarding.change_question(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  # Add/remove a choice row — rebuilds the in-memory form only.
  def handle_event("save", %{"question" => %{"_action" => "add_option"} = params}, socket) do
    params = Map.update(params, "options_sort", ["new"], &(&1 ++ ["new"]))
    {:noreply, assign_form(socket, Onboarding.change_question(socket.assigns.question, params))}
  end

  def handle_event(
        "save",
        %{"question" => %{"_action" => "remove_option:" <> index} = params},
        socket
      ) do
    params = Map.update(params, "options_drop", [index], &(&1 ++ [index]))
    {:noreply, assign_form(socket, Onboarding.change_question(socket.assigns.question, params))}
  end

  def handle_event("save", %{"question" => params}, socket) do
    # When the last choice is removed, the form omits the `options` key entirely;
    # inject an empty collection so cast_embed clears the orphans (on_replace).
    params = Map.put_new(params, "options", %{})
    save_question(socket, socket.assigns.action, params)
  end

  defp save_question(socket, :new, params) do
    case Onboarding.create_question(params_with_scope(socket, params)) do
      {:ok, question} ->
        notify_parent({:saved, question})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_question(socket, :edit, params) do
    case Onboarding.update_question(socket.assigns.question, params) do
      {:ok, question} ->
        notify_parent({:saved, question})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # Scope + professional_id come from the preset struct, never the form.
  defp params_with_scope(socket, params) do
    params
    |> Map.put("scope", socket.assigns.question.scope)
    |> Map.put("professional_id", socket.assigns.question.professional_id)
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
