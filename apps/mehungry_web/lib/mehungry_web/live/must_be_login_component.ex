defmodule MehungryWeb.MustBeLoginComponent do
  use MehungryWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full h-fit mt-6 p-4">
      <h1 class="text-complementaryd text-xl w-full text-center">
        You must be loged in to perform this action
      </h1>
      <a
        class="flex items-center"
        style="height: 3rem; border-color: var(--clr-complementary-middle)"
        href="/users/log_in"
      >
        <div class="w-full p-2 flex items-center gap-1 font-medium w-full" style=" font-size: 1rem;">
          <span class="w-full text-center" style="color: var(--clr-complementary-middle);">
            Navigate to Login
          </span>
        </div>
      </a>

      <div class="absolute bottom-3 right-0 left-0 m-auto w-fit bg-white">
        <button class="button_outline_primary modal-submit-button" phx-click="keep_browsing">
          Let me browse
        </button>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok, socket}
  end
end
