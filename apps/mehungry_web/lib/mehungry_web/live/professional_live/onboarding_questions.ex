defmodule MehungryWeb.ProfessionalLive.OnboardingQuestions do
  @moduledoc """
  Admin editor for the global onboarding question sets. `:scope` in the path is
  either `user` (appended to the normal-user wizard) or `client-default` (the
  default template snapshotted into each nutritionist's client questionnaire).
  """
  use MehungryWeb, :live_view

  alias Mehungry.Onboarding
  alias Mehungry.Onboarding.Question
  alias MehungryWeb.OnboardingQuestionLive.Shared

  @scope_from_path %{"user" => "user", "client-default" => "client_default"}

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, :editing, nil)}

  @impl true
  def handle_params(%{"scope" => scope_path}, _url, socket) do
    scope = Map.fetch!(@scope_from_path, scope_path)
    {:noreply, socket |> assign(:scope, scope) |> assign(:professional_id, nil) |> load()}
  end

  @impl true
  def render(assigns), do: Shared.index(assigns)

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply, assign(socket, :editing, %Question{scope: socket.assigns.scope, options: []})}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing, Onboarding.get_question!(id))}
  end

  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, :editing, nil)}

  def handle_event("delete", %{"id" => id}, socket) do
    id |> Onboarding.get_question!() |> Onboarding.delete_question()
    {:noreply, socket |> load() |> put_flash(:info, "Question deleted.")}
  end

  def handle_event("move_up", %{"id" => id}, socket), do: move(socket, id, :up)
  def handle_event("move_down", %{"id" => id}, socket), do: move(socket, id, :down)

  @impl true
  def handle_info({MehungryWeb.OnboardingQuestionLive.FormComponent, {:saved, _question}}, socket) do
    {:noreply, socket |> assign(:editing, nil) |> load() |> put_flash(:info, "Question saved.")}
  end

  defp move(socket, id, direction) do
    id |> Onboarding.get_question!() |> Onboarding.move_question(direction)
    {:noreply, load(socket)}
  end

  defp load(socket) do
    scope = socket.assigns.scope

    socket
    |> assign(:questions, Onboarding.list_questions(scope, socket.assigns.professional_id))
    |> assign(:heading, heading(scope))
    |> assign(:subheading, subheading(scope))
  end

  defp heading("user"), do: "User onboarding questions"
  defp heading("client_default"), do: "Nutritionist client questionnaire — default"

  defp subheading("user"),
    do:
      "Extra questions appended to the normal-user onboarding wizard (after the diet/language/calorie step). Answers are visible to a nutritionist on the user's client file."

  defp subheading("client_default"),
    do:
      "The default questionnaire each nutritionist starts from. It is copied into a nutritionist's own set the first time they open theirs — later edits here don't change existing nutritionist copies."
end
