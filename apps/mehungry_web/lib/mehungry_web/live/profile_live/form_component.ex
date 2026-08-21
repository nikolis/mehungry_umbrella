defmodule MehungryWeb.ProfileLive.Form do
  use MehungryWeb, :live_component
  import MehungryWeb.CoreComponents

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
            Diet
          </h3>
          <p class="text-center text-parchment-dim text-sm mt-1">
            The diet you follow. Filters your Home and Browse feeds and tunes recipe suggestions.
          </p>
        </div>

        <div class="bg-ink-panel2 rounded-lg p-4 mb-4">
          <input type="hidden" name="user_profile[diet]" value={@base_diet} />
          <div class="flex flex-wrap gap-2 mb-4">
            <button
              :for={{value, label} <- diet_options()}
              type="button"
              phx-target={@myself}
              phx-click="set_base_diet"
              phx-value-diet={value}
              class={chip_class(@base_diet == value)}
            >
              {if @base_diet == value, do: "✓ ", else: ""}{label}
            </button>
          </div>

          <input
            type="hidden"
            name="user_profile[lactose_intolerant]"
            value={to_string(@lactose_intolerant)}
          />
          <button
            type="button"
            phx-target={@myself}
            phx-click="toggle_flag"
            phx-value-flag="lactose_intolerant"
            class={chip_class(@lactose_intolerant)}
          >
            {if @lactose_intolerant, do: "✓ ", else: ""}Also lactose intolerant
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
     |> assign_new(:base_diet, fn -> user_profile.diet || "omnivore" end)
     |> assign_new(:lactose_intolerant, fn -> user_profile.lactose_intolerant || false end)
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
    # The diet chips are the single source of truth for dietary-restriction rules:
    # regenerate the category rules from the selected diet on every save so the
    # persisted `diet`, the rules that feed recipe grading, and the feed filter all
    # stay in sync.
    params =
      user_profile_params
      |> Map.put("diet", socket.assigns.base_diet)
      |> Map.put("lactose_intolerant", socket.assigns.lactose_intolerant)
      |> Map.put("user_category_rules", diet_category_rules(socket))

    save_user_profile(socket, socket.assigns.action, params)
  end

  def handle_event("set_base_diet", %{"diet" => diet}, socket)
      when diet in ["omnivore", "vegetarian", "vegan", "pescatarian"] do
    {:noreply, assign(socket, :base_diet, diet)}
  end

  def handle_event("toggle_flag", %{"flag" => "lactose_intolerant"}, socket) do
    {:noreply, assign(socket, :lactose_intolerant, !socket.assigns.lactose_intolerant)}
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
        notify_parent({:error, save_error_message()})
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
        notify_parent({:error, save_error_message()})
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_error_message do
    "Couldn't save your profile. Please check the highlighted fields and try again."
  end

  # The category rules a diet excludes, as cast_assoc params. Passed as the full
  # `user_category_rules` set on save so `on_replace: :delete` regenerates them:
  # old rules drop, the selected diet's exclusions (all "Absolutely not") replace
  # them. Omnivore yields `[]`, clearing all rules.
  defp diet_category_rules(socket) do
    restriction = absolutely_not(socket.assigns.food_restrictions)
    flags = if socket.assigns.lactose_intolerant, do: [:lactose_intolerant], else: []
    user_id = socket.assigns.current_user.id

    if restriction do
      socket.assigns.base_diet
      |> String.to_existing_atom()
      |> Food.diet_category_ids(flags)
      |> Enum.map(fn category_id ->
        %{
          "category_id" => category_id,
          "food_restriction_type_id" => restriction.id,
          "user_id" => user_id
        }
      end)
    else
      []
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
