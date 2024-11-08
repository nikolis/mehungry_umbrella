defmodule MehungryWeb.Presence do
  @moduledoc false
  @topic "user_activity"
  # @recipe_activity "recipe_activity"
  alias Mehungry.Meta

  use Phoenix.Presence,
    otp_app: :mehungry_web,
    pubsub_server: Mehungry.PubSub

  alias MehungryWeb.Presence

  def user_tracking do
    quote do
      @topic "user_activity"
      @recipe_activity "recipe_activity"

      def get_address_agent(socket) do
        try do
          {first, second, third, forth} =
            Phoenix.LiveView.get_connect_info(socket, :peer_data).address

          address =
            Integer.to_string(first) <>
              "." <>
              Integer.to_string(second) <>
              "." <> Integer.to_string(third) <> "." <> Integer.to_string(forth)

          agent = Phoenix.LiveView.get_connect_info(socket, :user_agent)

          {address, agent}
        catch
          _ ->
            nil
        end
      end

      def maybe_track_user(product, socket) do
        if connected?(socket) do
          ret =
            Presence.track(self(), "general", "general", %{
              address: socket.assigns.address,
              agent: socket.assigns.agent,
              path: socket.assigns.path
            })

          Mehungry.Meta.create_visit(%{
            ip_address: socket.assigns.address,
            details: %{agent: socket.assigns.agent, path: socket.assigns.path}
          })
          |> IO.inspect()

          ret
        else
          nil
        end

        # Presence.track(socket, "General" ,"General", %{addres: address, agent: agent, path: path} )
      end

      """
            def maybe_track_user(
                  %{page: page, recipe: recipe},
                  %{assigns: %{live_action: _, current_user: current_user}} = socket
                ) do
              if connected?(socket) do
                {address, agent} = get_address_agent(socket)

                result =
                  if(is_nil(current_user)) do
                    Presence.track(self(), @topic, "Unknow user", %{users: [recipe: recipe.title]})
                  else
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
      """
    end
  end

  def list_general do
    IO.inspect(Presence.list("general"),
      label:
        "asdafdsfadsfads----------------------------------------------------------------------------------------------------------------"
    )
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
