defmodule MehungryWeb.PrivacyPolicyLive do
  use MehungryWeb, :live_view
  use MehungryWeb.Searchable, :transfers_to_search

  def mount_search(_params, session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <h1 class="text-center p-4 pb-2">Privacy policy</h1>
    <h3 class="text-center text-base">Data usage</h3>
    <p class="px-10">
      We keep statistic data based on your intereaction with m3hungry in order to develop and train our models to provide a better more personalized browsing experience. Your data are not shared with any other party in any way or form besides the parties you explicitely chose for example using Facebook, Instagram or other social media integrations. By deleting your m3hungry account, every information that were associated with your account is being deleted with it.
    </p>
    """
  end
end
