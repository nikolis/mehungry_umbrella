defmodule MehungryWeb.Presence do
  @moduledoc false
  @topic "user_activity"
  # @recipe_activity "recipe_activity"
  # alias Mehungry.Meta

  use Phoenix.Presence,
    otp_app: :mehungry_web,
    pubsub_server: Mehungry.PubSub

  alias MehungryWeb.Presence

  def user_tracking do
    quote do
      require Logger

      @topic "user_activity"
      @recipe_activity "recipe_activity"

      def get_address_agent(socket) do
        case tracking_context(socket) do
          %{address: address, agent: agent} -> {address, agent}
          nil -> {"", ""}
        end
      end

      # Connect info only exists while the LiveView is mounting; cache it in
      # the process dictionary so patch navigations (handle_params after
      # mount) can still record visits.
      def tracking_context(socket) do
        case read_connect_context(socket) do
          {:ok, context} ->
            Process.put(:tracking_context, context)
            context

          :error ->
            Process.get(:tracking_context)
        end
      end

      defp read_connect_context(socket) do
        session = Phoenix.LiveView.get_connect_info(socket, :session) || %{}
        agent = Phoenix.LiveView.get_connect_info(socket, :user_agent) || ""

        {:ok, %{address: client_address(socket), agent: agent, session: session}}
      rescue
        _ -> :error
      end

      # Behind the ALB the socket peer is the load balancer, so prefer the
      # first hop of x-forwarded-for.
      defp client_address(socket) do
        x_headers = Phoenix.LiveView.get_connect_info(socket, :x_headers) || []
        forwarded_address(x_headers) || peer_address(socket)
      end

      defp forwarded_address(x_headers) do
        with {_, forwarded} <- List.keyfind(x_headers, "x-forwarded-for", 0),
             address when address != "" <-
               forwarded |> String.split(",") |> List.first() |> String.trim() do
          address
        else
          _ -> nil
        end
      end

      defp peer_address(socket) do
        with %{address: address} when is_tuple(address) <-
               Phoenix.LiveView.get_connect_info(socket, :peer_data),
             formatted when is_list(formatted) <- :inet.ntoa(address) do
          to_string(formatted)
        else
          _ -> ""
        end
      end

      def maybe_track_user(_product, socket) do
        context = if connected?(socket), do: tracking_context(socket)

        with %{session: session, address: address, agent: agent} <- context,
             "accepted" <- Map.get(session, "cookie_consent") do
          referrer = Map.get(socket.assigns, :referrer, "")
          path = Map.get(socket.assigns, :path, "")
          current_user = Map.get(socket.assigns, :current_user)

          {user_token, visitor_id} =
            {Map.get(session, "user_token"), Map.get(session, "visitor_id")}

          session_key =
            if user_token do
              :crypto.hash(:sha256, user_token)
              |> Base.encode16(case: :lower)
              |> String.slice(0, 24)
            else
              date = Date.utc_today() |> Date.to_string()

              :crypto.hash(:sha256, "#{address}|#{agent}|#{date}")
              |> Base.encode16(case: :lower)
              |> String.slice(0, 24)
            end

          ret =
            Presence.track(self(), "general", "general", %{
              address: address,
              agent: agent,
              path: path
            })

          case Mehungry.Meta.create_visit(%{
                 ip_address: address,
                 session_key: session_key,
                 details: %{
                   agent: agent,
                   path: path,
                   referrer: referrer,
                   visitor_id: visitor_id,
                   user_id: current_user && current_user.id,
                   user_email: current_user && current_user.email
                 }
               }) do
            {:ok, visit} ->
              Process.put(:current_visit_id, visit.id)
              Phoenix.PubSub.broadcast(Mehungry.PubSub, "mehungry:analytics", :new_visit)

            {:error, changeset} ->
              Logger.warning(
                "[VisitTracking] failed to record visit: #{inspect(changeset.errors)}"
              )
          end

          ret
        else
          _ -> nil
        end
      end

      def handle_event("page_timing", %{"ttfb_ms" => ttfb, "load_ms" => load}, socket) do
        visit_id = Process.get(:current_visit_id)
        if visit_id, do: Mehungry.Meta.update_visit_timing(visit_id, ttfb, load)
        {:noreply, socket}
      end

      # Presence.track(socket, "General" ,"General", %{addres: address, agent: agent, path: path} )

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
