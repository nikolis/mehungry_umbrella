defmodule MehungryWeb.ProfessionalLive.ActiveUsers do
  use MehungryWeb, :live_view

  alias Mehungry.Accounts.TestAccounts

  @topic "general"
  def mount(_params, _session, socket) do
    active_users = MehungryWeb.Presence.list_products_and_users()
    MehungryWeb.Endpoint.subscribe(@topic)

    socket =
      socket
      |> assign(:active_users, active_users)
      |> assign(:test_accounts_password, TestAccounts.password())
      |> assign(:test_accounts, TestAccounts.status())

    {:ok, socket}
  end

  def handle_info(%{event: "presence_diff"}, socket) do
    presense_gen_info = Map.get(MehungryWeb.Presence.list("general"), "general")
    presense_gen_info = presense_gen_info.metas

    socket = assign(socket, :active_users, presense_gen_info)

    {:noreply, socket}
  end

  def handle_event("seed_test_accounts", _params, socket) do
    TestAccounts.seed()

    {:noreply,
     socket
     |> assign(:test_accounts, TestAccounts.status())
     |> put_flash(:info, "Seeded the 3 test accounts.")}
  end

  def handle_event("reset_test_accounts", _params, socket) do
    TestAccounts.reset()

    {:noreply,
     socket
     |> assign(:test_accounts, TestAccounts.status())
     |> put_flash(:info, "Reset the 3 test accounts (deleted + recreated).")}
  end
end
