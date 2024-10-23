defmodule MehungryWeb.Presence do
  @moduledoc false
  @topic "user_activity"
  # @recipe_activity "recipe_activity"

  use Phoenix.Presence,
    otp_app: :mehungry_web,
    pubsub_server: Mehungry.PubSub

  alias MehungryWeb.Presence

  def user_tracking do
    quote do
      @topic "user_activity"
      @recipe_activity "recipe_activity"

      def maybe_track_user(
            %{recipe: recipe},
            %{assigns: %{live_action: _, current_user: current_user}} = socket
          ) do
        if connected?(socket) do
          result =
            if(is_nil(current_user)) do
              IO.inspect(current_user, label: "Current user is")

              Presence.track(self(), @topic, "Unknow user", %{users: [recipe: recipe.title]})
            else
              IO.inspect(current_user, label: "Current user is")
              if is_nil(current_user.email) do
                Presence.track(self(), @topic, "Unknown user", %{users: [recipe: recipe.title]})
              else
                Presence.track(self(), @topic, current_user.email, %{
                  users: [recipe: recipe.title]
                })
              end
            end
        end
      end

      def maybe_track_user(
            metadata,
            %{assigns: %{live_action: :index, current_user: current_user}} =
              socket
          ) do
        if connected?(socket) do
          result =
            if(is_nil(current_user)) do
              IO.inspect(current_user, label: "Current user is")

            Presence.track(self(), @topic, "Unknown User", %{
              users: [recipe_search: metadata.query]
            })
            else
              if is_nil(current_user.email) do
            Presence.track(self(), @topic, current_user.id, %{
              users: [recipe_search: metadata.query]
            })
              else
            Presence.track(self(), @topic, current_user.email, %{
              users: [recipe_search: metadata.query]
            })
              end
            end
        end
      end

      def maybe_track_user(_product, _socket) do
        nil
      end
    end
  end

  def list_products_and_users do
    Presence.list(@topic)
    |> Enum.map(&extract_recipe_with_users/1)
  end

  defp extract_recipe_with_users({recipe_name, %{metas: metas}}) do
    {recipe_name, users_from_metas_list(metas)}
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
      @topic,
      view_name,
      %{users: [%{email: user_email}]}
    )
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
