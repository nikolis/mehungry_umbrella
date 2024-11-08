defmodule MehungryWeb.ProfessionalLive.ActiveUsers do
  use MehungryWeb, :live_view

  @topic "general"
  def mount(_params, _session, socket) do
    active_users = MehungryWeb.Presence.list_products_and_users()
    MehungryWeb.Endpoint.subscribe(@topic)
    socket = assign(socket, :active_users, active_users)
    {:ok, socket}
  end

  def handle_info(%{event: "presence_diff"}, socket) do
    presense_gen_info = Map.get(MehungryWeb.Presence.list_general(), "general")
    IO.inspect(presense_gen_info)
    presense_gen_info = presense_gen_info.metas

    IO.inspect(presense_gen_info,
      label:
        "presense_gen_info 00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
    )

    socket = assign(socket, :active_users, presense_gen_info)

    {:noreply, socket}
  end
end
