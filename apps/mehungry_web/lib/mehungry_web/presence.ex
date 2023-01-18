defmodule MehungryWeb.Presence do
  use Phoenix.Presence,
    otp_app: :mehungry_web,
    pubsub_server: Mehungry.PubSub

  alias MehungryWeb.Presence
  @user_activity_topic "user_activity"

  def list_views_and_users do
    Presence.list(@user_activity_topic)
    |> Enum.map(&extract_views_with_users/1)
  end

  defp extract_views_with_users({view_name, %{metas: metas}}) do
    {view_name, users_from_metas_list(metas)}
  end

  defp users_from_metas_list(metas_list) do
    Enum.map(metas_list, &users_from_meta_map/1)
    |> List.flatten()
    |> Enum.uniq()
  end

  def users_from_meta_map(meta_map) do
    get_in(meta_map, [:users])
  end

  def track_user(pid, view_name, user_email) do
    Presence.track(
      pid,
      @user_activity_topic,
      view_name,
      %{users: [%{email: user_email}]}
    )
  end
end
