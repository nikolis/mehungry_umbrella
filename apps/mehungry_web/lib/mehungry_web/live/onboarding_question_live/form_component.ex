defmodule MehungryWeb.OnboardingQuestionLive.FormComponent do
  @moduledoc """
  Shared create/edit form for an `Onboarding.Question`, used by both the admin
  editor (`user` / `client_default` scopes) and the nutritionist editor
  (`client` scope). The owning scope + `professional_id` are preset on the
  `%Question{}` the parent hands in, so they aren't editable here.

  The schema splits "how is it answered?" across two fields — `question_type`
  (`value`/`single_choice`/`multi_choice`) and, for a `value` question,
  `value_kind` (`text`/`number`). Authors don't think in those terms, so the
  form presents a single radio group over four plain-language shapes
  (short text / number / pick one / pick several) via a virtual `answer_shape`
  param that `apply_answer_shape/1` expands back into the two real fields before
  the changeset sees them.

  Choices are managed with the app's `sort_param`/`drop_param` convention: the
  "Add"/"Remove" buttons submit a `question[_action]` sentinel that rebuilds the
  in-memory changeset (nothing persists until Save).
  """
  use MehungryWeb, :live_component

  alias Mehungry.Onboarding
  alias Mehungry.Onboarding.Question
  alias MehungryWeb.CoreComponents
  alias Phoenix.LiveView.JS

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
        <section class="space-y-4">
          <p class="text-[11px] uppercase tracking-wider font-bold text-paprika-soft">
            {gettext("The question")}
          </p>

          <div>
            <label for={@form[:prompt_en].id} class="block text-sm font-medium text-parchment mb-1.5">
              {gettext("What are you asking the client?")}<span
                class="text-paprika ml-0.5"
                aria-hidden="true"
              >*</span>
            </label>
            <input
              type="text"
              id={@form[:prompt_en].id}
              name={@form[:prompt_en].name}
              value={Phoenix.HTML.Form.normalize_value("text", @form[:prompt_en].value)}
              required
              aria-required="true"
              class={field_class(@form[:prompt_en].errors)}
            />
            <.field_errors field={@form[:prompt_en]} />
          </div>

          <div>
            <label for={@form[:prompt_el].id} class="block text-sm font-medium text-parchment mb-1">
              {gettext("Greek")}
            </label>
            <p class="text-xs text-parchment-dim mb-1.5">
              {gettext("Optional — English is shown if you leave this blank.")}
            </p>
            <input
              type="text"
              id={@form[:prompt_el].id}
              name={@form[:prompt_el].name}
              value={Phoenix.HTML.Form.normalize_value("text", @form[:prompt_el].value)}
              class={field_class(@form[:prompt_el].errors)}
            />
            <.field_errors field={@form[:prompt_el]} />
          </div>
        </section>

        <section class="space-y-3 border-t border-ink-panel2 pt-5">
          <p class="text-[11px] uppercase tracking-wider font-bold text-paprika-soft">
            {gettext("How do they answer?")}
          </p>

          <div class="flex flex-col gap-2.5">
            <label
              :for={{val, title, hint} <- answer_shapes()}
              class={[
                "flex items-start gap-3 p-3 rounded-xl border cursor-pointer transition-colors",
                if(answer_shape(@form) == val,
                  do: "border-paprika bg-paprika/5",
                  else: "border-ink-panel2 hover:border-paprika-soft/60"
                )
              ]}
            >
              <input
                type="radio"
                name="question[answer_shape]"
                value={val}
                checked={answer_shape(@form) == val}
                class="mt-1 border-ink-panel2 bg-ink text-paprika focus:ring-paprika-soft/40"
              />
              <span>
                <span class="block text-sm font-semibold text-parchment">{title}</span>
                <span class="block text-xs text-parchment-dim">{hint}</span>
              </span>
            </label>
          </div>

          <div :if={Question.choice_type?(@form[:question_type].value)} class="space-y-3 pt-1">
            <div>
              <p class="text-sm font-medium text-parchment">{gettext("Answer options")}</p>
              <p class="text-xs text-parchment-dim">
                {gettext("These are the choices your client will see.")}
              </p>
            </div>

            <.inputs_for :let={opt} field={@form[:options]}>
              <div class="flex flex-col sm:flex-row sm:items-center gap-3 bg-black/20 border border-ink-panel2 rounded-xl p-3">
                <input type="hidden" name="question[options_sort][]" value={opt.index} />
                <input type="hidden" name={opt[:key].name} value={opt[:key].value} />
                <div class="flex-1">
                  <input
                    type="text"
                    name={opt[:label_en].name}
                    value={Phoenix.HTML.Form.normalize_value("text", opt[:label_en].value)}
                    placeholder={gettext("Option in English")}
                    aria-label={gettext("Option in English")}
                    class={field_class(opt[:label_en].errors, :sm)}
                  />
                  <.field_errors field={opt[:label_en]} />
                </div>
                <div class="flex-1">
                  <input
                    type="text"
                    name={opt[:label_el].name}
                    value={Phoenix.HTML.Form.normalize_value("text", opt[:label_el].value)}
                    placeholder={gettext("Greek (optional)")}
                    aria-label={gettext("Greek (optional)")}
                    class={field_class(opt[:label_el].errors, :sm)}
                  />
                </div>
                <button
                  type="submit"
                  name="question[_action]"
                  value={"remove_option:#{opt.index}"}
                  aria-label={gettext("Remove option")}
                  class="self-end sm:self-center text-parchment-dim hover:text-red-400 transition-colors p-2"
                >
                  <.icon name="hero-x-mark" class="w-4 h-4" />
                </button>
              </div>
            </.inputs_for>

            <p
              :for={msg <- Enum.map(@form[:options].errors, &CoreComponents.translate_error/1)}
              class="text-xs text-red-400"
            >
              {msg}
            </p>

            <button
              type="submit"
              name="question[_action]"
              value="add_option"
              class="inline-flex items-center gap-1 px-3 py-1.5 rounded-full border border-ink-panel2 text-parchment-dim hover:bg-ink-panel2 hover:text-parchment text-xs font-semibold transition-colors"
            >
              {gettext("+ Add option")}
            </button>
          </div>
        </section>

        <section class="space-y-3 border-t border-ink-panel2 pt-5">
          <p class="text-[11px] uppercase tracking-wider font-bold text-paprika-soft">
            {gettext("Settings")}
          </p>

          <label class="flex items-start gap-3 cursor-pointer">
            <input type="hidden" name={@form[:required].name} value="false" />
            <input
              type="checkbox"
              id={@form[:required].id}
              name={@form[:required].name}
              value="true"
              checked={Phoenix.HTML.Form.normalize_value("checkbox", @form[:required].value)}
              class="mt-0.5 rounded border-ink-panel2 bg-ink text-paprika focus:ring-2 focus:ring-paprika-soft/40"
            />
            <span class="text-sm font-medium text-parchment">
              {gettext("Clients must answer this")}
            </span>
          </label>

          <label class="flex items-start gap-3 cursor-pointer">
            <input type="hidden" name={@form[:active].name} value="false" />
            <input
              type="checkbox"
              id={@form[:active].id}
              name={@form[:active].name}
              value="true"
              checked={Phoenix.HTML.Form.normalize_value("checkbox", @form[:active].value)}
              class="mt-0.5 rounded border-ink-panel2 bg-ink text-paprika focus:ring-2 focus:ring-paprika-soft/40"
            />
            <span>
              <span class="block text-sm font-medium text-parchment">
                {gettext("Show this question to clients")}
              </span>
              <span class="block text-xs text-parchment-dim">
                {gettext("Turn off to hide it without deleting it.")}
              </span>
            </span>
          </label>
        </section>

        <:actions>
          <.action
            type="button"
            variant={:ghost}
            phx-click={JS.exec("data-cancel", to: "#onboarding-question-modal")}
          >
            {gettext("Cancel")}
          </.action>
          <.action type="submit" variant={:primary} phx-disable-with={gettext("Saving…")}>
            {gettext("Save question")}
          </.action>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  # Inline field error list, on-palette and in normal flow (unlike the shared
  # `.error`, which is absolutely positioned and off-palette).
  attr :field, Phoenix.HTML.FormField, required: true

  defp field_errors(assigns) do
    ~H"""
    <p
      :for={msg <- Enum.map(@field.errors, &CoreComponents.translate_error/1)}
      class="mt-1 text-xs text-red-400"
    >
      {msg}
    </p>
    """
  end

  defp field_class(errors, size \\ :md) do
    pad = if size == :sm, do: "px-2.5 py-1.5 text-sm", else: "px-3 py-2"

    base =
      "w-full #{pad} rounded-lg bg-ink text-parchment placeholder-parchment-dim/50 " <>
        "border focus:outline-none focus:ring-2 focus:ring-paprika-soft/40 transition-colors"

    if errors == [],
      do: base <> " border-ink-panel2 focus:border-paprika",
      else: base <> " border-red-400 focus:border-red-400"
  end

  defp answer_shapes do
    [
      {"short_text", gettext("Short text"), gettext("A sentence or a few words")},
      {"number", gettext("Number"), gettext("A single value, e.g. age or weight")},
      {"single_choice", gettext("Pick one"), gettext("Client chooses exactly one option")},
      {"multi_choice", gettext("Pick several"), gettext("Client can choose any number of options")}
    ]
  end

  # Collapse the two stored fields into the one shape the radio group renders.
  defp answer_shape(form) do
    case {form[:question_type].value, form[:value_kind].value} do
      {"single_choice", _} -> "single_choice"
      {"multi_choice", _} -> "multi_choice"
      {"value", "number"} -> "number"
      _ -> "short_text"
    end
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
      |> Onboarding.change_question(apply_answer_shape(params))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  # Add/remove a choice row — rebuilds the in-memory form only.
  def handle_event("save", %{"question" => %{"_action" => "add_option"} = params}, socket) do
    params =
      params
      |> apply_answer_shape()
      |> Map.update("options_sort", ["new"], &(&1 ++ ["new"]))

    {:noreply, assign_form(socket, Onboarding.change_question(socket.assigns.question, params))}
  end

  def handle_event(
        "save",
        %{"question" => %{"_action" => "remove_option:" <> index} = params},
        socket
      ) do
    params =
      params
      |> apply_answer_shape()
      |> Map.update("options_drop", [index], &(&1 ++ [index]))

    {:noreply, assign_form(socket, Onboarding.change_question(socket.assigns.question, params))}
  end

  def handle_event("save", %{"question" => params}, socket) do
    params =
      params
      |> apply_answer_shape()
      |> maybe_clear_options()

    save_question(socket, socket.assigns.action, params)
  end

  # Expand the virtual `answer_shape` radio into the two stored fields.
  defp apply_answer_shape(%{"answer_shape" => shape} = params) do
    params
    |> Map.delete("answer_shape")
    |> Map.merge(shape_to_fields(shape))
  end

  defp apply_answer_shape(params), do: params

  defp shape_to_fields("number"), do: %{"question_type" => "value", "value_kind" => "number"}
  defp shape_to_fields("single_choice"), do: %{"question_type" => "single_choice"}
  defp shape_to_fields("multi_choice"), do: %{"question_type" => "multi_choice"}
  defp shape_to_fields(_), do: %{"question_type" => "value", "value_kind" => "text"}

  # A free-text (`value`) question carries no choices; clear any left behind by
  # an earlier choice selection. For choice types, ensure the key exists so that
  # removing the last row still clears the orphans via on_replace.
  defp maybe_clear_options(%{"question_type" => "value"} = params),
    do: Map.put(params, "options", %{})

  defp maybe_clear_options(params), do: Map.put_new(params, "options", %{})

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
