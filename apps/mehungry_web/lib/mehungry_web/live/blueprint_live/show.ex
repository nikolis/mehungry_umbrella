defmodule MehungryWeb.BlueprintLive.Show do
  @moduledoc """
  Public preview of a **public** meal blueprint (`/blueprints/:slug`) — the
  landing page for a blueprint shared to a Facebook group. It renders the
  blueprint's targets and its attached sample meal plans, sets Open Graph meta
  (so Facebook shows a rich card), and offers logged-in users a save toggle and
  a "use this blueprint" shortcut that seeds a personal plan on their calendar.

  Rendered synchronously so the disconnected (crawler) render already carries
  the content + meta, mirroring `PublicNutritionistLive.Show`.
  """
  use MehungryWeb, :live_view

  alias Mehungry.History.MealType
  alias Mehungry.MealBlueprints
  import MehungryWeb.BlueprintComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_new(socket, :current_user, fn -> nil end)}
  end

  @impl true
  def handle_params(%{"slug" => slug}, _uri, socket) do
    blueprint = MealBlueprints.get_public_blueprint_by_slug!(slug)
    plans = MealBlueprints.list_public_plans_for_blueprint(blueprint.id)
    user = socket.assigns.current_user

    saved? = user && MealBlueprints.blueprint_saved?(user.id, blueprint.id)

    {:noreply,
     socket
     |> assign(:blueprint, blueprint)
     |> assign(:plans, plans)
     |> assign(:saved?, !!saved?)
     |> assign(:share_url, url(~p"/blueprints/#{slug}"))
     |> assign_seo(blueprint)}
  end

  @impl true
  def handle_event("toggle_save", _params, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/users/log_in")}

      user ->
        bp = socket.assigns.blueprint

        if socket.assigns.saved? do
          MealBlueprints.remove_saved_blueprint_for_user(user.id, bp.id)

          {:noreply,
           socket
           |> assign(:saved?, false)
           |> put_flash(:info, "Removed from your saved blueprints.")}
        else
          MealBlueprints.save_blueprint_for_user(user.id, bp.id)

          {:noreply,
           socket |> assign(:saved?, true) |> put_flash(:info, "Saved to your profile.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-ink text-parchment pb-16">
      <div class="container max-w-3xl mx-auto px-4 py-8">
        <!-- Header -->
        <div class="bg-ink-panel border border-ink-panel2 rounded-2xl p-6 mb-6">
          <h1 class="text-2xl md:text-3xl font-display font-medium text-parchment">
            {@blueprint.name}
          </h1>
          <p :if={@blueprint.description} class="text-parchment-dim mt-2">
            {@blueprint.description}
          </p>

          <div class="flex flex-wrap items-center gap-1.5 mt-4">
            <span
              :if={@blueprint.condition}
              class="text-[11px] px-2 py-0.5 rounded-full bg-paprika/15 text-paprika-soft"
            >
              {@blueprint.condition.name}
            </span>
            <span class="text-[11px] px-2 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim">
              7 days · 5 meals/day
            </span>
            <span
              :if={author_line(@blueprint)}
              class="text-[11px] px-2 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim"
            >
              by {author_line(@blueprint)}
            </span>
          </div>

          <.tag_row
            label="Prefer"
            tags={@blueprint.required_nutrients ++ @blueprint.required_compounds}
            tone={:basil}
          />
          <.tag_row
            label="Avoid"
            tags={@blueprint.avoid_nutrients ++ @blueprint.avoid_compounds}
            tone={:paprika}
          />
          <.tag_row label="Preferred foods" tags={@blueprint.preferred_foods} tone={:muted} />

          <!-- Actions -->
          <div class="flex flex-wrap items-center gap-2 mt-6" x-data="{}">
            <a
              href={"https://www.facebook.com/sharer/sharer.php?u=" <> URI.encode_www_form(@share_url)}
              target="_blank"
              rel="noopener"
              class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-[#1877F2] hover:opacity-90 text-white text-sm font-semibold transition"
            >
              Share on Facebook
            </a>
            <button
              type="button"
              x-on:click={"navigator.clipboard.writeText('#{@share_url}'); $el.innerText = 'Copied!'"}
              class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-ink-panel2 hover:bg-ink text-parchment text-sm font-semibold transition"
            >
              Copy link
            </button>

            <button
              :if={@current_user}
              type="button"
              phx-click="toggle_save"
              class={[
                "inline-flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-semibold transition",
                if(@saved?,
                  do: "bg-basil/20 text-basil hover:bg-basil/30",
                  else: "bg-ink-panel2 text-parchment hover:bg-ink"
                )
              ]}
            >
              {if @saved?, do: "Saved ✓", else: "Save"}
            </button>
            <.link
              :if={@current_user}
              navigate={~p"/calendar?#{[blueprint_id: @blueprint.id]}"}
              class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink text-sm font-bold transition"
            >
              Use this blueprint
            </.link>
            <.link
              :if={!@current_user}
              navigate={~p"/users/log_in"}
              class="text-parchment-dim text-sm hover:text-parchment"
            >
              Log in to save &amp; use this blueprint
            </.link>
          </div>
        </div>

        <!-- Sample plans -->
        <div :if={@plans != []}>
          <h2 class="text-lg font-display font-medium text-parchment mb-3">Sample meal plans</h2>
          <div class="space-y-4">
            <div
              :for={plan <- @plans}
              class="bg-ink-panel border border-ink-panel2 rounded-xl p-4"
            >
              <div class="flex items-center justify-between mb-3">
                <span class="text-sm font-semibold text-parchment">{plan.name}</span>
                <span class="text-parchment-dim text-xs">{plan.meals_count} meals</span>
              </div>
              <.plan_meals meals={plan.meals} />
            </div>
          </div>
        </div>

        <div :if={@plans == []} class="text-center text-parchment-dim py-10">
          This blueprint doesn't have any sample plans yet.
        </div>

        <!-- Targets -->
        <details class="mt-6 bg-ink-panel border border-ink-panel2 rounded-xl">
          <summary class="cursor-pointer select-none px-4 py-3 font-semibold text-parchment">
            Daily macro targets
          </summary>
          <div class="px-4 pb-4 space-y-4">
            <div :for={day <- @blueprint.days}>
              <div class="text-parchment-dim text-xs font-semibold uppercase tracking-wide mb-1.5">
                Day {day.day_index}
                <span :if={day.total_calorie_target} class="normal-case font-normal">
                  · {day.total_calorie_target} kcal
                </span>
              </div>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-1.5">
                <div :for={meal <- day.meals} class="flex items-center justify-between text-sm">
                  <span class="text-parchment-dim">{MealType.label(meal.meal_type)}</span>
                  <span class="text-parchment [font-variant-numeric:tabular-nums] text-xs">
                    P {meal.protein_pct}% · C {meal.carbs_pct}% · F {meal.fats_pct}%
                  </span>
                </div>
              </div>
            </div>
          </div>
        </details>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :tags, :list, required: true
  attr :tone, :atom, required: true

  defp tag_row(%{tags: []} = assigns), do: ~H""

  defp tag_row(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-1.5 mt-3">
      <span class="text-parchment-dim text-xs">{@label}:</span>
      <span
        :for={tag <- @tags}
        class={[
          "text-[11px] px-2 py-0.5 rounded-full",
          case @tone do
            :basil -> "bg-basil/15 text-basil"
            :paprika -> "bg-paprika/15 text-paprika-soft"
            _ -> "bg-ink-panel2 text-parchment-dim"
          end
        ]}
      >
        {tag}
      </span>
    </div>
    """
  end

  defp author_line(%{user: %{name: name}}) when is_binary(name) and name != "", do: name
  defp author_line(_), do: nil

  # ── SEO ─────────────────────────────────────────────────────────────────────

  defp assign_seo(socket, blueprint) do
    description =
      (blueprint.description ||
         "A 7-day meal blueprint#{condition_suffix(blueprint)} on M3Hungry — browse the sample plans and build your own.")
      |> String.slice(0, 155)

    socket
    |> assign(:page_title, "#{blueprint.name} — Meal Blueprint")
    |> assign(:page_description, description)
    |> assign(:canonical_path, "/blueprints/#{blueprint.slug}")
  end

  defp condition_suffix(%{condition: %{name: name}}) when is_binary(name), do: " for #{name}"
  defp condition_suffix(_), do: ""
end
