defmodule MehungryWeb.Onboarding.FormComponent do
  use MehungryWeb, :live_component
  import MehungryWeb.CoreComponents

  alias Mehungry.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <h3 class="p-6">Please specify your relationship with animal products</h3>
      </.header>

      <.simple_form
        for={@form}
        id="onboarding-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="text-center"
      >
        <div class="p-6 pt-0 text-base font-medium">
          <.input field={@form[:vegan]} type="checkbox" label="I am vegan" />
          <.input field={@form[:vegetarian]} type="checkbox" label="I am vegeterian" />
          <.input field={@form[:lactose_intolerant]} type="checkbox" label="I am lactose intolerant" />
          <.input field={@form[:nothing]} type="checkbox" label="Non of the above" />
        </div>
        <:actions>
          <.button class="primary_outline_button" phx-disable-with="Saving...">Save Post</.button>
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
    {:noreply, socket}
  end

  def handle_event("save", params, socket) do
    save_onboarding(socket, params)
  end

  defp save_onboarding(socket, post_params) do
    user_id = socket.assigns.user_profile.user_id

    case Map.get(post_params, "vegan") do
      "true" ->
        restriction = get_restriction()
        categories = get_categories(:vegan)

        categories =
          Enum.map(categories, fn x ->
            %{category_id: x.id, food_restriction_type_id: restriction.id, user_id: user_id}
          end)

        Accounts.update_user_profile(
          socket.assigns.user_profile,
          %{
            onboarding_level: 1,
            user_category_rules: categories
          }
        )

      _ ->
        case Map.get(post_params, "vegetarian") do
          "true" ->
            restriction = get_restriction()
            categories = get_categories(:vegeterian)

            categories =
              Enum.map(categories, fn x ->
                %{category_id: x.id, food_restriction_type_id: restriction.id, user_id: user_id}
              end)

            Accounts.update_user_profile(
              socket.assigns.user_profile,
              %{
                onboarding_level: 1,
                user_category_rules: categories
              }
            )

          _ ->
            case Map.get(post_params, "lactose_intolerant") do
              "true" ->
                restriction = get_restriction()
                categories = get_categories(:lactose_intolerant)

                categories =
                  Enum.map(categories, fn x ->
                    %{
                      category_id: x.id,
                      food_restriction_type_id: restriction.id,
                      user_id: user_id
                    }
                  end)

                Accounts.update_user_profile(
                  socket.assigns.user_profile,
                  %{
                    onboarding_level: 1,
                    user_category_rules: categories
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

  def get_restriction() do
    restrictions = Mehungry.Food.list_food_restriction_types()
    Enum.find(restrictions, fn x -> x.title == "Absolutely not" end)
  end

  defp get_categories(type) do
    [fish] = Mehungry.Food.search_category("fish")
    [poultry] = Mehungry.Food.search_category("Poultry")
    [dairy] = Mehungry.Food.search_category("Dairy")
    [pork] = Mehungry.Food.search_category("Pork")
    [sausages] = Mehungry.Food.search_category("Sausages")
    [lamb] = Mehungry.Food.search_category("Lamb")
    [beef] = Mehungry.Food.search_category("Beef")

    case type do
      :vegan ->
        [fish, poultry, dairy, pork, sausages, lamb, beef]

      :vegeterian ->
        [fish, poultry, pork, sausages, lamb, beef]

      :pescaterian ->
        [poultry, pork, sausages, lamb, beef]

      :lactose_intolerant ->
        [dairy]
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
