defmodule MehungryWeb.Onboarding.FormComponent do
  @moduledoc """
  First-run onboarding wizard: a 3-step modal (dietary preferences + language →
  daily calorie target → health-condition badge opt-in) that persists everything
  to the user's profile on finish and sets `onboarding_level: 1`.
  """
  use MehungryWeb, :live_component
  import MehungryWeb.CoreComponents

  alias Mehungry.Accounts
  alias Mehungry.Food
  alias Mehungry.Health

  @total_steps 3

  # ═══════════════════════════════════════════════════════════════════════════
  # View (Render)
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <h3 class="p-6 pb-2">Welcome! Let's set up your preferences</h3>
      </.header>

      <.step_indicator step={@step} total={@total_steps} />

      <div class="p-6 pt-2 text-center">
        <%= case @step do %>
          <% 1 -> %>
            {diet_step(assigns)}
          <% 2 -> %>
            {calories_step(assigns)}
          <% 3 -> %>
            {health_step(assigns)}
        <% end %>
      </div>

      <div class="flex justify-between gap-3 px-6 pb-6">
        <button
          :if={@step > 1}
          type="button"
          phx-click="prev_step"
          phx-target={@myself}
          class="px-5 py-2 rounded-full text-sm font-semibold border-2 border-slate-600 text-slate-300 hover:border-slate-400 hover:text-white transition-colors"
        >
          Back
        </button>
        <div class="flex-1"></div>
        <button
          :if={@step < @total_steps}
          type="button"
          phx-click="next_step"
          phx-target={@myself}
          class="px-6 py-2 rounded-full text-sm font-semibold bg-primary-500 text-white hover:bg-primary-600 transition-colors"
        >
          Next
        </button>
        <button
          :if={@step == @total_steps}
          type="button"
          id="onboarding_submit_button"
          phx-click="save"
          phx-target={@myself}
          phx-disable-with="Saving..."
          class="px-6 py-2 rounded-full text-sm font-semibold bg-primary-500 text-white hover:bg-primary-600 transition-colors"
        >
          Finish
        </button>
      </div>
    </div>
    """
  end

  defp step_indicator(assigns) do
    ~H"""
    <div class="flex justify-center gap-2 mb-2">
      <span
        :for={n <- 1..@total}
        class={"h-1.5 w-8 rounded-full transition-colors #{if n <= @step, do: "bg-primary-500", else: "bg-slate-600"}"}
      ></span>
    </div>
    """
  end

  # Step 1 — dietary preferences (+ compact language selector)
  defp diet_step(assigns) do
    ~H"""
    <div>
      <p class="text-sm font-semibold text-slate-300 mb-3">Choose your language</p>
      <div class="flex justify-center gap-2 mb-6">
        <button
          :for={{code, label} <- [{"en", "EN — English"}, {"el", "ΕΛ — Ελληνικά"}]}
          type="button"
          phx-click="set_onboarding_language"
          phx-value-lang={code}
          phx-target={@myself}
          class={pill_class(@selected_language == code)}
        >
          {label}
        </button>
      </div>

      <p class="text-sm font-semibold text-slate-300 mb-3">What best describes your diet?</p>
      <div class="flex flex-wrap justify-center gap-2 mb-6">
        <button
          :for={{value, label} <- diet_options()}
          type="button"
          phx-click="set_base_diet"
          phx-value-diet={value}
          phx-target={@myself}
          class={pill_class(@base_diet == value)}
        >
          {label}
        </button>
      </div>

      <p class="text-sm font-semibold text-slate-300 mb-3">Anything else?</p>
      <button
        type="button"
        phx-click="toggle_flag"
        phx-value-flag="lactose_intolerant"
        phx-target={@myself}
        class={pill_class(@lactose_intolerant)}
      >
        {if @lactose_intolerant, do: "✓ ", else: ""}I am lactose intolerant
      </button>
    </div>
    """
  end

  # Step 2 — daily calorie target
  defp calories_step(assigns) do
    ~H"""
    <div>
      <p class="text-sm font-semibold text-slate-300 mb-1">Daily calorie target</p>
      <p class="text-xs text-slate-400 mb-4">
        Optional — set a kcal/day goal to track against your meal plans. You can change or clear this later.
      </p>
      <form phx-change="set_calories" phx-target={@myself} class="flex justify-center">
        <input
          type="number"
          name="daily_calorie_target"
          value={@daily_calorie_target}
          min="1"
          max="19999"
          placeholder="e.g. 2000"
          class="w-40 text-center rounded-lg border-2 border-slate-600 bg-transparent text-white px-4 py-2 focus:border-primary-500 focus:outline-none"
        />
      </form>
    </div>
    """
  end

  # Step 3 — health condition badge opt-in
  defp health_step(assigns) do
    ~H"""
    <div>
      <p class="text-sm font-semibold text-slate-300 mb-1">Health condition badges</p>
      <p class="text-xs text-slate-400 mb-4">
        Optional — pick any conditions and we'll flag recipes on your feed that contain compounds relevant to them.
      </p>

      <div :if={@conditions_by_category == []} class="text-sm text-slate-400">
        No conditions available yet — you can set these later from your profile.
      </div>

      <div class="text-left max-h-72 overflow-y-auto space-y-4">
        <div :for={{category, conditions} <- @conditions_by_category}>
          <p class="text-xs uppercase tracking-wide text-slate-500 mb-2">{category}</p>
          <div class="flex flex-wrap gap-2">
            <button
              :for={condition <- conditions}
              type="button"
              phx-click="toggle_condition"
              phx-value-id={condition.id}
              phx-target={@myself}
              class={pill_class(MapSet.member?(@selected_condition_ids, condition.id))}
            >
              {if MapSet.member?(@selected_condition_ids, condition.id), do: "✓ ", else: ""}{condition.name}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp pill_class(selected?) do
    base =
      "px-5 py-2 rounded-full text-sm font-semibold border-2 transition-colors"

    if selected? do
      "#{base} bg-primary-500 border-primary-500 text-white"
    else
      "#{base} border-slate-600 text-slate-400 hover:border-slate-400 hover:text-white"
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

  # ═══════════════════════════════════════════════════════════════════════════
  # Update
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def update(assigns, socket) do
    existing_lang = (assigns.user_profile && assigns.user_profile.language_preference) || "en"

    conditions_by_category =
      Health.list_conditions_for_presentation()
      |> Enum.group_by(&(&1.category || "Other"))
      |> Enum.sort_by(fn {category, _} -> category end)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:total_steps, @total_steps)
     |> assign_new(:step, fn -> 1 end)
     |> assign_new(:selected_language, fn -> existing_lang end)
     |> assign_new(:base_diet, fn -> "omnivore" end)
     |> assign_new(:lactose_intolerant, fn -> false end)
     |> assign_new(:daily_calorie_target, fn -> nil end)
     |> assign_new(:selected_condition_ids, fn -> MapSet.new() end)
     |> assign(:conditions_by_category, conditions_by_category)}
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Events
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def handle_event("next_step", _params, socket) do
    {:noreply, assign(socket, :step, min(socket.assigns.step + 1, @total_steps))}
  end

  def handle_event("prev_step", _params, socket) do
    {:noreply, assign(socket, :step, max(socket.assigns.step - 1, 1))}
  end

  def handle_event("set_onboarding_language", %{"lang" => lang}, socket)
      when lang in ["en", "el"] do
    {:noreply, assign(socket, :selected_language, lang)}
  end

  def handle_event("set_base_diet", %{"diet" => diet}, socket)
      when diet in ["omnivore", "vegetarian", "vegan", "pescatarian"] do
    {:noreply, assign(socket, :base_diet, diet)}
  end

  def handle_event("toggle_flag", %{"flag" => "lactose_intolerant"}, socket) do
    {:noreply, assign(socket, :lactose_intolerant, !socket.assigns.lactose_intolerant)}
  end

  def handle_event("set_calories", %{"daily_calorie_target" => value}, socket) do
    {:noreply, assign(socket, :daily_calorie_target, parse_calories(value))}
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

  def handle_event("save", _params, socket) do
    save_onboarding(socket)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Persistence
  # ═══════════════════════════════════════════════════════════════════════════

  defp save_onboarding(socket) do
    profile = socket.assigns.user_profile
    user_id = profile.user_id
    restriction = get_restriction()

    category_rules =
      if restriction do
        flags = if socket.assigns.lactose_intolerant, do: [:lactose_intolerant], else: []

        Food.diet_category_ids(String.to_existing_atom(socket.assigns.base_diet), flags)
        |> Enum.map(fn category_id ->
          %{category_id: category_id, food_restriction_type_id: restriction.id, user_id: user_id}
        end)
      else
        []
      end

    attrs =
      %{
        onboarding_level: 1,
        language_preference: socket.assigns.selected_language,
        diet: socket.assigns.base_diet,
        lactose_intolerant: socket.assigns.lactose_intolerant,
        user_category_rules: category_rules
      }
      |> maybe_put_calories(socket.assigns.daily_calorie_target)

    Accounts.update_user_profile(profile, attrs)

    Accounts.set_condition_opt_ins(
      profile.id,
      MapSet.to_list(socket.assigns.selected_condition_ids)
    )

    notify_parent("profile-saved")

    {:noreply, push_patch(socket, to: socket.assigns.patch)}
  end

  defp maybe_put_calories(attrs, nil), do: attrs
  defp maybe_put_calories(attrs, target), do: Map.put(attrs, :daily_calorie_target, target)

  defp parse_calories(value) do
    case Integer.parse(to_string(value)) do
      {int, _} when int > 0 -> int
      _ -> nil
    end
  end

  def get_restriction() do
    restrictions = Food.list_food_restriction_types()
    Enum.find(restrictions, fn x -> x.title == "Absolutely not" end)
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
