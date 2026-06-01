defmodule MehungryWeb.Onboarding.FormComponent do
  use MehungryWeb, :live_component
  import MehungryWeb.CoreComponents

  alias Mehungry.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <h3 class="p-6">Welcome! Let's set up your preferences</h3>
      </.header>
      <.simple_form
        for={@form}
        id="onboarding-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="text-center"
      >
        <div class="p-6 pt-2">
          <p class="text-sm font-semibold text-slate-300 mb-3">Choose your language</p>
          <div class="flex justify-center gap-2 mb-6">
            <button
              type="button"
              phx-click="set_onboarding_language"
              phx-value-lang="en"
              phx-target={@myself}
              class={"px-6 py-2 rounded-full text-sm font-semibold border-2 transition-colors #{if @selected_language == "en", do: "bg-primary-500 border-primary-500 text-white", else: "border-slate-600 text-slate-400 hover:border-slate-400 hover:text-white"}"}
            >
              EN — English
            </button>
            <button
              type="button"
              phx-click="set_onboarding_language"
              phx-value-lang="el"
              phx-target={@myself}
              class={"px-6 py-2 rounded-full text-sm font-semibold border-2 transition-colors #{if @selected_language == "el", do: "bg-primary-500 border-primary-500 text-white", else: "border-slate-600 text-slate-400 hover:border-slate-400 hover:text-white"}"}
            >
              ΕΛ — Ελληνικά
            </button>
          </div>
          <input type="hidden" name="language_preference" value={@selected_language} />

          <p class="text-sm font-semibold text-slate-300 mb-3">
            Your relationship with animal products
          </p>
          <.input field={@form[:vegan]} type="checkbox" label="I am vegan" />
          <.input field={@form[:vegetarian]} type="checkbox" label="I am vegeterian" />
          <.input field={@form[:lactose_intolerant]} type="checkbox" label="I am lactose intolerant" />
          <.input field={@form[:nothing]} type="checkbox" label="Non of the above" />
        </div>
        <:actions>
          <.button
            id="onboarding_submit_button"
            class="primary_outline_button"
            phx-disable-with="Saving..."
          >
            Save
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    map = %{"vegan" => "false", "vegeterian" => "false", "lactose_intolerant" => "false"}

    existing_lang = (assigns.user_profile && assigns.user_profile.language_preference) || "en"

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:user_profile, assigns.user_profile)
     |> assign(:selected_language, existing_lang)
     |> assign_form(map)}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("set_onboarding_language", %{"lang" => lang}, socket)
      when lang in ["en", "el"] do
    {:noreply, assign(socket, :selected_language, lang)}
  end

  def handle_event("save", params, socket) do
    save_onboarding(socket, params)
  end

  defp save_onboarding(socket, post_params) do
    user_id = socket.assigns.user_profile.user_id
    language = Map.get(post_params, "language_preference", socket.assigns.selected_language)

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
            language_preference: language,
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
                  %{onboarding_level: 1, language_preference: language}
                )
            end
        end
    end

    notify_parent("profile-saved")

    {:noreply,
     socket
     |> push_patch(to: socket.assigns.patch)}
  end

  defp assign_form(socket, map) do
    assign(socket, :form, to_form(map))
  end

  def get_restriction() do
    restrictions = Mehungry.Food.list_food_restriction_types()
    Enum.find(restrictions, fn x -> x.title == "Absolutely not" end)
  end

  defp get_categories(type) do
    fish = Mehungry.Food.search_category("fish") |> List.first()
    poultry = Mehungry.Food.search_category("Poultry") |> List.first()
    dairy = Mehungry.Food.search_category("Dairy") |> List.first()
    pork = Mehungry.Food.search_category("Pork") |> List.first()
    sausages = Mehungry.Food.search_category("Sausages") |> List.first()
    lamb = Mehungry.Food.search_category("Lamb") |> List.first()
    beef = Mehungry.Food.search_category("Beef") |> List.first()

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
