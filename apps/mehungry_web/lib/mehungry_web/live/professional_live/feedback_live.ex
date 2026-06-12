defmodule MehungryWeb.ProfessionalLive.FeedbackLive do
  use MehungryWeb, :live_view

  alias Mehungry.Feedback

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :feedbacks, Feedback.list_feedbacks())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    feedback = Feedback.get_feedback!(id)
    {:ok, _} = Feedback.delete_feedback(feedback)
    {:noreply, assign(socket, :feedbacks, Feedback.list_feedbacks())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-slate-900">
      <div class="container mx-auto px-4 py-6 max-w-3xl">
        <div class="mb-6">
          <h1 class="text-2xl font-bold text-white flex items-center gap-3">
            <.icon name="hero-chat-bubble-left-ellipsis" class="w-7 h-7 text-primary-500 flex-shrink-0" />
            User Feedback
          </h1>
          <p class="text-slate-400 text-sm mt-1">{length(@feedbacks)} submission{if length(@feedbacks) != 1, do: "s", else: ""}</p>
        </div>

        <%= if @feedbacks == [] do %>
          <div class="bg-slate-800 border border-slate-700 rounded-xl p-12 text-center">
            <.icon name="hero-inbox" class="w-10 h-10 text-slate-500 mx-auto mb-3" />
            <p class="text-slate-400">No feedback submitted yet.</p>
          </div>
        <% else %>
          <div class="space-y-3">
            <%= for fb <- @feedbacks do %>
              <div class="bg-slate-800 border border-slate-700 rounded-xl p-5">
                <div class="flex items-start justify-between gap-4">
                  <div class="flex-1 min-w-0">
                    <p class="text-white text-sm leading-relaxed whitespace-pre-wrap">{fb.message}</p>
                    <div class="flex flex-wrap items-center gap-3 mt-3">
                      <%= if fb.email do %>
                        <span class="flex items-center gap-1 text-xs text-slate-400">
                          <.icon name="hero-envelope" class="w-3.5 h-3.5" />
                          {fb.email}
                        </span>
                      <% end %>
                      <span class="flex items-center gap-1 text-xs text-slate-500">
                        <.icon name="hero-clock" class="w-3.5 h-3.5" />
                        {Calendar.strftime(fb.inserted_at, "%d %b %Y, %H:%M")}
                      </span>
                      <%= if fb.user_id do %>
                        <span class="text-xs bg-primary-500/10 text-primary-400 border border-primary-500/20 px-2 py-0.5 rounded-full">
                          registered user
                        </span>
                      <% else %>
                        <span class="text-xs bg-slate-700 text-slate-400 border border-slate-600 px-2 py-0.5 rounded-full">
                          anonymous
                        </span>
                      <% end %>
                    </div>
                  </div>
                  <button
                    phx-click="delete"
                    phx-value-id={fb.id}
                    data-confirm="Delete this feedback?"
                    class="flex-shrink-0 p-1.5 rounded-lg text-slate-500 hover:text-red-400 hover:bg-red-500/10 transition"
                  >
                    <.icon name="hero-trash" class="w-4 h-4" />
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
