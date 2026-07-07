defmodule MehungryWeb.FeedbackLive do
  use MehungryWeb, :live_view

  alias Mehungry.Feedback

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    changeset = Feedback.change_feedback()

    {:ok,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:submitted, false)
     |> assign(:current_user, user)}
  end

  @impl true
  def handle_event("validate", %{"feedback" => params}, socket) do
    changeset =
      Feedback.change_feedback(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("submit", %{"feedback" => params}, socket) do
    user = socket.assigns.current_user

    attrs =
      if user do
        Map.merge(params, %{"user_id" => user.id, "email" => user.email})
      else
        params
      end

    case Feedback.create_feedback(attrs) do
      {:ok, _feedback} ->
        {:noreply, assign(socket, :submitted, true)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-slate-900 flex items-center justify-center px-4 py-12">
      <div class="w-full max-w-lg">
        <div class="mb-8 text-center">
          <div class="inline-flex items-center justify-center w-14 h-14 rounded-full bg-primary-500/10 mb-4">
            <.icon name="hero-chat-bubble-left-ellipsis" class="h-7 w-7 text-primary-400" />
          </div>
          <h1 class="text-2xl font-bold text-white">Share your feedback</h1>
          <p class="text-slate-400 text-sm mt-2">
            Tell us what you think — what works, what doesn't, what's missing.
          </p>
        </div>

        <%= if @submitted do %>
          <div class="bg-slate-800 border border-slate-700 rounded-xl p-8 text-center">
            <div class="inline-flex items-center justify-center w-12 h-12 rounded-full bg-green-500/10 mb-4">
              <.icon name="hero-check-circle" class="h-6 w-6 text-green-400" />
            </div>
            <h2 class="text-lg font-semibold text-white">Thank you!</h2>
            <p class="text-slate-400 text-sm mt-1">
              Your feedback has been saved. We really appreciate it.
            </p>
            <a
              href="/browse"
              class="inline-block mt-6 px-5 py-2.5 rounded-lg bg-primary-500 hover:bg-primary-600 text-white text-sm font-medium transition"
            >
              Back to browsing
            </a>
          </div>
        <% else %>
          <div class="bg-slate-800 border border-slate-700 rounded-xl p-6">
            <.form for={@form} phx-change="validate" phx-submit="submit" class="space-y-5">
              <div>
                <label class="block text-sm font-medium text-slate-300 mb-1.5">Your feedback</label>
                <.input
                  field={@form[:message]}
                  type="textarea"
                  placeholder="What do you like? What's confusing? What feature would make this app a must-have for you?"
                  class="w-full bg-slate-900 border-slate-600 text-white placeholder-slate-500 rounded-lg resize-none"
                  rows="6"
                />
              </div>

              <%= if is_nil(@current_user) do %>
                <div>
                  <label class="block text-sm font-medium text-slate-300 mb-1.5">
                    Email
                    <span class="text-slate-500 font-normal">(optional — if you'd like a reply)</span>
                  </label>
                  <.input
                    field={@form[:email]}
                    type="email"
                    placeholder="you@example.com"
                    class="w-full bg-slate-900 border-slate-600 text-white placeholder-slate-500 rounded-lg"
                  />
                </div>
              <% end %>

              <button
                type="submit"
                class="w-full py-2.5 rounded-lg bg-primary-500 hover:bg-primary-600 text-white font-medium transition"
              >
                Send feedback
              </button>
            </.form>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
