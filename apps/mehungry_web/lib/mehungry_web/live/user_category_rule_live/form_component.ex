defmodule MehungryWeb.UserCategoryRuleLive.FormComponent do
  use MehungryWeb, :live_component
  import MehungryWeb.CoreComponents

  alias Mehungry.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage user_category_rule records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="user_category_rule-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >

        <:actions>
          <.button phx-disable-with="Saving...">Save User category rule</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{user_category_rule: user_category_rule} = assigns, socket) do
    changeset = Accounts.change_user_category_rule(user_category_rule)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"user_category_rule" => user_category_rule_params}, socket) do
    changeset =
      socket.assigns.user_category_rule
      |> Accounts.change_user_category_rule(user_category_rule_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"user_category_rule" => user_category_rule_params}, socket) do
    save_user_category_rule(socket, socket.assigns.action, user_category_rule_params)
  end

  defp save_user_category_rule(socket, :edit, user_category_rule_params) do
    case Accounts.update_user_category_rule(
           socket.assigns.user_category_rule,
           user_category_rule_params
         ) do
      {:ok, user_category_rule} ->
        notify_parent({:saved, user_category_rule})

        {:noreply,
         socket
         |> put_flash(:info, "User category rule updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_user_category_rule(socket, :new, user_category_rule_params) do
    case Accounts.create_user_category_rule(user_category_rule_params) do
      {:ok, user_category_rule} ->
        notify_parent({:saved, user_category_rule})

        {:noreply,
         socket
         |> put_flash(:info, "User category rule created successfully")
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
