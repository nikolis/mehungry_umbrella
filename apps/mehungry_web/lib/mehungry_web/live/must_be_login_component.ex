defmodule MehungryWeb.MustBeLoginComponent do
  use MehungryWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-6 px-8 py-10 text-center">
      <div class="flex items-center justify-center w-16 h-16 rounded-full bg-primary-500/10">
        <svg class="w-8 h-8 text-primary-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
          />
        </svg>
      </div>

      <div>
        <h2 class="text-xl font-semibold text-white">Sign in required</h2>
        <p class="mt-1 text-slate-400 text-sm">You need to be logged in to perform this action.</p>
      </div>

      <div class="flex flex-col sm:flex-row gap-3 w-full">
        <a
          href="/users/log_in"
          class="flex-1 flex items-center justify-center gap-2 px-5 py-2.5 rounded-lg bg-primary-500 hover:bg-primary-600 text-white font-medium transition"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M11 16l-4-4m0 0l4-4m-4 4h14m-5 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h7a3 3 0 013 3v1"
            />
          </svg>
          Log in
        </a>
        <button
          class="flex-1 px-5 py-2.5 rounded-lg border border-slate-600 text-slate-300 hover:bg-slate-700 hover:text-white font-medium transition"
          phx-click="keep_browsing"
        >
          Keep browsing
        </button>
      </div>
    </div>
    """
  end

  @impl true
  def update(_assigns, socket) do
    {:ok, socket}
  end
end
