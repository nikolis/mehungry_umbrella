defmodule MehungryWeb.ProfileLive.Form do
  use MehungryWeb, :live_component
  import MehungryWeb.CoreComponents

  alias MehungryWeb.ProfileLive.FormCategoryComponent

  alias Mehungry.Accounts
  alias Mehungry.Food
  alias Mehungry.Health

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
          <.input
            field={@form[:daily_calorie_target]}
            type="number"
            label="Daily calorie target (kcal)"
            min="1"
            max="19999"
          />
        </div>

        <div class="mt-10 mb-4">
          <h3 class="text-center text-parchment font-display text-xl font-medium">
            Dietary Restrictions
          </h3>
          <p class="text-center text-parchment-dim text-sm mt-1">
            Foods to avoid, and how strongly you feel about them.
          </p>
        </div>

        <div class="bg-ink-panel2 rounded-lg p-4 mb-4">
          <p class="text-parchment-dim text-xs mb-3">
            Quick start — pick a diet and apply it to generate your restrictions.
          </p>
          <div class="flex flex-wrap gap-2 mb-3">
            <button
              :for={{value, label} <- diet_options()}
              type="button"
              phx-target={@myself}
              phx-click="set_base_diet"
              phx-value-diet={value}
              class={chip_class(@base_diet == value)}
            >
              {label}
            </button>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <button
              type="button"
              phx-target={@myself}
              phx-click="toggle_flag"
              phx-value-flag="lactose_intolerant"
              class={chip_class(@lactose_intolerant)}
            >
              {if @lactose_intolerant, do: "✓ ", else: ""}Lactose intolerant
            </button>
            <div class="flex-1"></div>
            <button
              type="button"
              phx-target={@myself}
              phx-click="apply_diet_preset"
              class="text-sm text-paprika-soft hover:text-paprika transition font-semibold"
            >
              Apply preset →
            </button>
          </div>
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

        <div class="mt-10 mb-4">
          <h3 class="text-center text-parchment font-display text-xl font-medium">
            Health Condition Badges
          </h3>
          <p class="text-center text-parchment-dim text-sm mt-1">
            Recipes are flagged when they contain compounds relevant to the conditions you pick.
          </p>
        </div>

        <div :if={@conditions_by_category == []} class="text-center text-parchment-dim text-sm">
          No conditions available yet.
        </div>

        <div class="space-y-4">
          <div :for={{category, conditions} <- @conditions_by_category}>
            <p class="text-xs uppercase tracking-wide text-parchment-dim mb-2">{category}</p>
            <div class="flex flex-wrap gap-2">
              <button
                :for={condition <- conditions}
                type="button"
                phx-target={@myself}
                phx-click="toggle_condition"
                phx-value-id={condition.id}
                class={chip_class(MapSet.member?(@selected_condition_ids, condition.id))}
              >
                {if MapSet.member?(@selected_condition_ids, condition.id), do: "✓ ", else: ""}{condition.name}
              </button>
            </div>
          </div>
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

  defp chip_class(selected?) do
    base = "px-4 py-1.5 rounded-full text-sm font-semibold border transition"

    if selected? do
      "#{base} bg-paprika border-paprika text-ink"
    else
      "#{base} border-ink-panel2 text-parchment-dim hover:text-parchment hover:border-parchment-dim"
    end
  end

  defp diet_options do
    [
      {"omnivore", "Omnivore"},
      {"vegetarian", "Vegetarian"},
      {"vegan", "Vegan"},
      {"pescatarian", "Pescatarian"}
    ]
  end

  @impl true
  def update(%{user_profile: user_profile} = assigns, socket) do
    changeset = Accounts.change_user_profile(user_profile)

    conditions_by_category =
      Health.list_conditions_for_presentation()
      |> Enum.group_by(&(&1.category || "Other"))
      |> Enum.sort_by(fn {category, _} -> category end)

    selected_condition_ids =
      user_profile.id
      |> Accounts.list_opted_in_condition_ids()
      |> MapSet.new()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:conditions_by_category, conditions_by_category)
     |> assign_new(:selected_condition_ids, fn -> selected_condition_ids end)
     |> assign_new(:base_diet, fn -> "omnivore" end)
     |> assign_new(:lactose_intolerant, fn -> false end)
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

  def handle_event("set_base_diet", %{"diet" => diet}, socket)
      when diet in ["omnivore", "vegetarian", "vegan", "pescatarian"] do
    {:noreply, assign(socket, :base_diet, diet)}
  end

  def handle_event("toggle_flag", %{"flag" => "lactose_intolerant"}, socket) do
    {:noreply, assign(socket, :lactose_intolerant, !socket.assigns.lactose_intolerant)}
  end

  def handle_event("apply_diet_preset", _params, socket) do
    restriction = absolutely_not(socket.assigns.food_restrictions)
    flags = if socket.assigns.lactose_intolerant, do: [:lactose_intolerant], else: []
    user_id = socket.assigns.current_user.id

    rules =
      if restriction do
        Food.diet_category_ids(String.to_existing_atom(socket.assigns.base_diet), flags)
        |> Enum.map(fn category_id ->
          %{category_id: category_id, food_restriction_type_id: restriction.id, user_id: user_id}
        end)
      else
        []
      end

    socket =
      update(socket, :form, fn %{source: changeset} ->
        changeset
        |> Ecto.Changeset.put_assoc(:user_category_rules, rules)
        |> to_form()
      end)

    {:noreply, socket}
  end

  def handle_event("toggle_condition", %{"id" => id}, socket) do
    id = String.to_integer(id)
    selected = socket.assigns.selected_condition_ids

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, :selected_condition_ids, selected)}
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
        Accounts.set_condition_opt_ins(
          user_profile.id,
          MapSet.to_list(socket.assigns.selected_condition_ids)
        )

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
        Accounts.set_condition_opt_ins(
          user_profile.id,
          MapSet.to_list(socket.assigns.selected_condition_ids)
        )

        notify_parent({:saved, user_profile})

        {:noreply,
         socket
         |> put_flash(:info, "User profile created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp absolutely_not(food_restrictions) do
    Enum.find(food_restrictions, fn x -> x.title == "Absolutely not" end)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
