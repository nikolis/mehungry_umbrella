defmodule MehungryWeb.Onboarding.FormComponent do
  use MehungryWeb, :live_component
  import MehungryWeb.CoreComponents

  alias Mehungry.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <:subtitle>Please specify your relationship with animal products </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="onboarding-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:vegan]} type="checkbox" label="I am vegan" />
        <.input field={@form[:vegetarian]} type="checkbox" label="I am vegeterian" />
        <.input field={@form[:lactose_intolerant]} type="checkbox" label="I am lactose intolerant" />

        <:actions>
          <.button phx-disable-with="Saving...">Save Post</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    map = %{vegan: "true", vegeterian: "false", lactose_intolerant: "false"}

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:user_profile, assigns.user_profile)
     |> assign_form(map)}
  end

  @impl true
  def handle_event("validate", params, socket) do
    IO.inspect(params)
    # assign_form(socket, changeset)}
    {:noreply, socket}
  end

  def handle_event("save", params, socket) do
    save_onboarding(socket, params)
  end

  defp save_onboarding(socket, post_params) do
    IO.inspect(post_params, label: "Post params")
    user_id =  socket.assigns.user_profile.user_id
    case Map.get(post_params, "vegan") do
      "true" ->
        Accounts.update_user_profile(
          socket.assigns.user_profile,
          %{
            onboarding_level: 1,
            user_category_rules: [
              %{category_id: 207, food_restriction_type_id: 1, user_id: user_id},
              %{category_id: 203, food_restriction_type_id: 1, user_id: user_id},
              %{category_id: 201, food_restriction_type_id: 1, user_id: user_id},
              %{category_id: 204, food_restriction_type_id: 1, user_id: user_id},
              %{category_id: 200, food_restriction_type_id: 1, user_id: user_id},
              %{category_id: 216, food_restriction_type_id: 1, user_id: user_id},
              %{category_id: 211, food_restriction_type_id: 1, user_id: user_id}
            ]
          }
        )

      _ ->

        case Map.get(post_params, "vegetarian") do
          "true" ->
            Accounts.update_user_profile(
              socket.assigns.user_profile,
              %{
                onboarding_level: 1,
                user_category_rules: [
                  %{category_id: 207, food_restriction_type_id: 1, user_id: user_id },
                  %{category_id: 203, food_restriction_type_id: 1, user_id: user_id},
                  %{category_id: 204, food_restriction_type_id: 1, user_id: user_id},
                  %{category_id: 200, food_restriction_type_id: 1, user_id: user_id},
                  %{category_id: 216, food_restriction_type_id: 1, user_id: user_id},
                  %{category_id: 211, food_restriction_type_id: 1, user_id: user_id}
                ]
              }
            )

          _ ->
            case Map.get(post_params, "lactose_intolerant") do
              "true" ->
                Accounts.update_user_profile(
                  socket.assigns.user_profile,
                  %{
                    onboarding_level: 1,
                    user_category_rules: [
                      %{category_id: 201, food_restriction_type_id: 1, user_id: user_id}
                    ]
                  }
                )

              _ ->
                Accounts.update_user_profile(
                  socket.assigns.user_profile,
                  %{onboarding_level: 1}
                )
            end
        end
    end

    notify_parent("profile-saved")

    {:noreply,
     socket
     |> push_patch(to: socket.assigns.patch)}
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp save_post(socket, :edit, post_params) do
    case Posts.update_post(socket.assigns.post, post_params) do
      {:ok, post} ->
        notify_parent({:saved, post})

        {:noreply,
         socket
         |> put_flash(:info, "Post updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, map) do
    assign(socket, :form, to_form(map))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
