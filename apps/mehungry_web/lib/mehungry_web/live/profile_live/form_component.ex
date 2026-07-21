defmodule MehungryWeb.ProfileLive.Form do
  use MehungryWeb, :live_component
  import MehungryWeb.CoreComponents

  alias MehungryWeb.ProfileLive.FormCategoryComponent

  alias Mehungry.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-ink-panel rounded-xl border border-ink-panel2 text-parchment w-fit lg:w-1/2 m-auto p-2 pb-10">
      <h3 class="text-center mb-8 text-parchment font-display text-2xl font-medium">
        {@title}
      </h3>
      <.simple_form
        for={@form}
        id="user_profile-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="profile-form relative w-full max-w-xl m-auto"
      >
        <div class="flex flex-col gap-5">
          <.input required field={@form[:alias]} type="text" label="Alias" />
          <.input required field={@form[:intro]} type="textarea" label="Intro" />
        </div>

        <div class="mt-10 mb-4">
          <h3 class="text-center text-parchment font-display text-xl font-medium">
            Dietary Restrictions
          </h3>
          <p class="text-center text-parchment-dim text-sm mt-1">
            Foods to avoid, and how strongly you feel about them.
          </p>
        </div>

        <div class="flex flex-col gap-2.5">
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

        <div class="flex justify-center mt-4">
          <button
            type="button"
            phx-target={@myself}
            phx-click="add_category_rule"
            class="flex items-center gap-1.5 text-sm text-paprika-soft hover:text-paprika transition font-semibold"
          >
            <.icon name="hero-plus-circle" class="w-5 h-5" /> Add a rule
          </button>
        </div>

        <div class="flex gap-4 pt-8">
          <button
            type="submit"
            phx-disable-with="Saving..."
            class="flex-1 bg-paprika hover:bg-paprika-soft text-ink font-bold py-2.5 px-4 rounded-lg transition"
          >
            Save Changes
          </button>
        </div>
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
