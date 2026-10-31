defmodule MehungryWeb.NutritionistLive.OnboardingQuestions do
  @moduledoc """
  Nutritionist editor for their own client-onboarding questionnaire. The set is
  seeded (snapshotted) from the admin `client_default` template the first time
  this page is opened, then fully owned by the nutritionist. Clients self-fill it
  at `/:locale/nutritionist/:professional_id/onboarding`.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Onboarding
  alias Mehungry.Onboarding.Question
  alias MehungryWeb.OnboardingQuestionLive.Shared

  @impl true
  def mount(_params, _session, socket) do
    professional_id = socket.assigns.current_user.id
    Onboarding.ensure_client_questions(professional_id)

    {:ok,
     socket
     |> assign(:editing, nil)
     |> assign(:scope, "client")
     |> assign(:professional_id, professional_id)
     |> load()}
  end

  @impl true
  def render(assigns), do: Shared.index(assigns)

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply,
     assign(socket, :editing, %Question{
       scope: "client",
       professional_id: socket.assigns.professional_id,
       options: []
     })}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing, own_question(socket, id))}
  end

  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, :editing, nil)}

  def handle_event("delete", %{"id" => id}, socket) do
    with %Question{} = q <- own_question(socket, id) do
      Onboarding.delete_question(q)
    end

    {:noreply, socket |> load() |> put_flash(:info, "Question deleted.")}
  end

  def handle_event("move_up", %{"id" => id}, socket), do: move(socket, id, :up)
  def handle_event("move_down", %{"id" => id}, socket), do: move(socket, id, :down)

  @impl true
  def handle_info({MehungryWeb.OnboardingQuestionLive.FormComponent, {:saved, _question}}, socket) do
    {:noreply, socket |> assign(:editing, nil) |> load() |> put_flash(:info, "Question saved.")}
  end

  defp move(socket, id, direction) do
    with %Question{} = q <- own_question(socket, id) do
      Onboarding.move_question(q, direction)
    end

    {:noreply, load(socket)}
  end

  # Guard: a nutritionist may only touch questions in their own `client` set.
  defp own_question(socket, id),
    do: Onboarding.get_client_question(socket.assigns.professional_id, id)

  defp load(socket) do
    socket
    |> assign(:questions, Onboarding.list_questions("client", socket.assigns.professional_id))
    |> assign(:heading, "Client onboarding questions")
    |> assign(
      :subheading,
      "The questionnaire your clients fill in when they join you. Seeded from the platform default; edit it freely — your changes are yours alone."
    )
  end
end
