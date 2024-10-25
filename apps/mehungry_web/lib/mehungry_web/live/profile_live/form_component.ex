defmodule MehungryWeb.ProfileLive.Form do
  use MehungryWeb, :live_component
  import MehungryWeb.CoreComponents

  alias MehungryWeb.ProfileLive.FormCategoryComponent

  alias Mehungry.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div class="form-main h-120 w-full xl:px-10">
      <h3 class="text-center mt-4 mb-8">
        <%= @title %>
      </h3>

      <.simple_form
        for={@form}
        id="user_profile-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="profile-form pb-10 relative w-fit md:w-8/12 m-auto"
      >
        <div>
            <.input required field={@form[:alias]} type="text" label="Alias" class="mt-4" />
          </div>
      <div class="mt-4">
        <.input required field={@form[:intro]} type="textarea" label="Intro" class="" />
      </div>
        <h3 class="text-center m-8">Diatery Restrictions</h3>
        <div class="max-h-64 overflow-auto min-h-80	">
          <.inputs_for :let={f_user_category_rule} field={@form[:user_category_rules]}>
            <FormCategoryComponent.render
              category_ids={@category_ids}
              categories={@categories}
              food_restrictions={@food_restrictions}
              food_restriction_ids={@food_restriction_ids}
              f={f_user_category_rule}
              parent={@myself}
            />
          </.inputs_for>
        </div>
        <div class="flex justify-end">
          <button
            class=" list_button_complementary"
            type="button"
            phx-target={@myself}
            phx-click="add_category_rule"
          >
            Add Rule
          </button>
        </div>
        <button
          class="block w-1/3 mt-12 mx-auto text-2xl font-bold  uppercase primary_button"
          phx-disable-with="Saving..."
        >
          Save
        </button>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{user_profile: user_profile} = assigns, socket) do
    changeset = Accounts.change_user_profile(user_profile)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"user_profile" => user_profile_params}, socket) do
    changeset =
      socket.assigns.user_profile
      |> Accounts.change_user_profile(user_profile_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"user_profile" => user_profile_params}, socket) do
    save_user_profile(socket, socket.assigns.action, user_profile_params)
  end

  def handle_event("add_category_rule", _data, socket) do
    socket =
      update(socket, :form, fn %{source: changeset} ->
        existing = Ecto.Changeset.get_assoc(changeset, :user_category_rules)

        changeset =
          Ecto.Changeset.put_assoc(
            changeset,
            :user_category_rules,
            existing ++ [%{user_id: socket.assigns.current_user.id}]
          )

        to_form(changeset)
      end)

    {:noreply, socket}
  end

  def handle_event("delete_category_rule", %{"index" => index}, socket) do
    index = String.to_integer(index)

    socket =
      update(socket, :form, fn %{source: changeset} ->
        existing = Ecto.Changeset.get_assoc(changeset, :user_category_rules)
        {to_delete, rest} = List.pop_at(existing, index)

        user_category_rules =
          if Ecto.Changeset.change(to_delete).data.id do
            List.replace_at(existing, index, Ecto.Changeset.change(to_delete, delete: true))
          else
            rest
          end

        changeset
        |> Ecto.Changeset.put_assoc(:user_category_rules, user_category_rules)
        |> to_form()
      end)

    {:noreply, socket}
  end

  defp save_user_profile(socket, :index, user_profile_params) do
    case Accounts.update_user_profile(socket.assigns.user_profile, user_profile_params) do
      {:ok, user_profile} ->
        notify_parent({:saved, user_profile})

        {:noreply,
         socket
         |> put_flash(:info, "User profile updated successfully")
         |> push_patch(to: "/profile")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_user_profile(socket, :new, user_profile_params) do
    case Accounts.create_user_profile(user_profile_params) do
      {:ok, user_profile} ->
        notify_parent({:saved, user_profile})

        {:noreply,
         socket
         |> put_flash(:info, "User profile created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
