defmodule MehungryWeb.BlueprintComponents do
  @moduledoc """
  Shared UI for meal blueprints — the browse/profile card and the day-grouped
  plan-meal list — used by the public preview page, the browse toggle, and the
  profile "saved blueprints" tab.
  """
  use Phoenix.VerifiedRoutes,
    endpoint: MehungryWeb.Endpoint,
    router: MehungryWeb.Router

  use Phoenix.Component

  alias Mehungry.History.MealType

  @doc """
  A blueprint summary card linking to its public preview, with an author block
  (avatar + name + role) linking to the creator's profile. Expects a blueprint
  with `:condition` and (optionally) `user: :professional_profile` preloaded and
  `:plans_count` populated.
  """
  attr :blueprint, :map, required: true
  attr :class, :string, default: ""

  def blueprint_card(assigns) do
    assigns = assign(assigns, :author, author(assigns.blueprint))

    ~H"""
    <div class={[
      "group flex flex-col bg-ink-panel border border-ink-panel2 rounded-xl overflow-hidden hover:border-basil/50 transition",
      @class
    ]}>
      <.link navigate={~p"/blueprints/#{@blueprint.slug}"} class="block p-4 flex-1">
        <div class="flex items-start gap-2">
          <.icon_clipboard />
          <div class="min-w-0 flex-1">
            <div class="font-semibold text-parchment truncate group-hover:text-basil transition">
              {@blueprint.name}
            </div>
            <div :if={@blueprint.description} class="text-parchment-dim text-sm truncate mt-0.5">
              {@blueprint.description}
            </div>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-1.5 mt-3">
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
            :if={(@blueprint.plans_count || 0) > 0}
            class="text-[11px] px-2 py-0.5 rounded-full bg-basil/15 text-basil"
          >
            {@blueprint.plans_count} sample {plural(@blueprint.plans_count, "plan")}
          </span>
        </div>
      </.link>

      <.link
        :if={@author}
        navigate={author_path(@author)}
        class="flex items-center gap-2.5 px-4 py-3 border-t border-ink-panel2 hover:bg-ink-panel2/60 transition"
      >
        <.author_avatar author={@author} />
        <div class="min-w-0">
          <div class="text-parchment text-xs font-medium truncate">
            {author_display_name(@author)}
          </div>
          <div class="text-parchment-dim text-[11px] truncate">{author_role(@author)}</div>
        </div>
      </.link>
    </div>
    """
  end

  @doc """
  Renders a generated plan's meals grouped by relative day (1..7). Expects each
  meal to have `:recipe` and `:ingredient` preloaded.
  """
  attr :meals, :list, required: true

  def plan_meals(assigns) do
    ~H"""
    <div :if={@meals == []} class="text-parchment-dim text-xs py-2">
      No meals in this plan.
    </div>
    <div class="space-y-3">
      <div :for={{day_index, meals} <- group_by_day_index(@meals)}>
        <div class="text-parchment-dim text-xs font-semibold uppercase tracking-wide mb-1.5">
          Day {day_index}
        </div>
        <div class="space-y-1.5">
          <div :for={m <- meals} class="flex items-center gap-2">
            <span class="text-parchment-dim text-[11px] w-24 shrink-0">
              {MealType.label(m.meal_type)}
            </span>
            <div class="min-w-0 flex-1">
              <.recipe_line m={m} />
              <.ingredient_line m={m} />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── internal components / helpers ─────────────────────────────────────────────

  defp icon_clipboard(assigns) do
    ~H"""
    <span class="w-9 h-9 rounded-lg bg-basil/15 text-basil flex items-center justify-center shrink-0">
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
        />
      </svg>
    </span>
    """
  end

  attr :m, :map, required: true

  def recipe_line(%{m: %{recipe: recipe}} = assigns) when not is_nil(recipe) do
    ~H"""
    <div class="flex items-center gap-2 py-0.5">
      <div class="w-9 h-9 rounded-md overflow-hidden bg-ink-panel2 shrink-0">
        <img
          :if={@m.recipe.image_url}
          src={@m.recipe.image_url}
          alt={@m.recipe.title}
          class="w-full h-full object-cover"
        />
        <div
          :if={!@m.recipe.image_url}
          class="w-full h-full flex items-center justify-center text-parchment-dim text-xs"
        >
          🍽
        </div>
      </div>
      <div class="min-w-0">
        <div class="text-sm text-parchment truncate">{@m.recipe.title}</div>
        <div class="text-parchment-dim text-[11px] truncate">{recipe_info(@m.recipe)}</div>
      </div>
    </div>
    """
  end

  def recipe_line(assigns), do: ~H""

  attr :m, :map, required: true

  def ingredient_line(%{m: %{ingredient: ingredient}} = assigns) when not is_nil(ingredient) do
    ~H"""
    <div class="flex items-center justify-between gap-2 py-0.5 pl-1">
      <div class="flex items-center gap-2 min-w-0">
        <span class="w-9 h-9 rounded-md bg-basil/15 text-basil flex items-center justify-center text-xs shrink-0">
          🥗
        </span>
        <span class="text-sm text-parchment truncate">{@m.ingredient.name}</span>
      </div>
      <span class="text-parchment-dim text-xs shrink-0 [font-variant-numeric:tabular-nums]">
        {format_quantity(@m.quantity)} {Mehungry.Food.RecipeIngredient.unit_label(@m)}
      </span>
    </div>
    """
  end

  def ingredient_line(assigns), do: ~H""

  defp group_by_day_index(meals) do
    meals
    |> Enum.group_by(& &1.day_index)
    |> Enum.sort_by(fn {day_index, _} -> day_index end)
  end

  defp recipe_info(recipe) do
    [
      recipe.servings && "#{recipe.servings} servings",
      difficulty_label(recipe.difficulty),
      cooking_time(recipe)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp difficulty_label(1), do: "Easy"
  defp difficulty_label(2), do: "Medium"
  defp difficulty_label(3), do: "Difficult"
  defp difficulty_label(_), do: nil

  defp cooking_time(%{cooking_time_lower_limit: t}) when is_integer(t) and t > 0, do: "#{t} min"
  defp cooking_time(_), do: nil

  defp format_quantity(q) when is_float(q) do
    if q == Float.round(q), do: q |> trunc() |> Integer.to_string(), else: Float.to_string(q)
  end

  defp format_quantity(nil), do: ""
  defp format_quantity(q), do: to_string(q)

  # Author avatar: the creator's photo (professional photo first, then their
  # account picture), falling back to a monogram tile when neither is set.
  attr :author, :map, required: true

  defp author_avatar(assigns) do
    assigns = assign(assigns, :avatar_url, author_avatar_url(assigns.author))

    ~H"""
    <span class="w-8 h-8 rounded-full overflow-hidden bg-basil/15 text-basil flex items-center justify-center shrink-0 ring-1 ring-ink-panel2">
      <img
        :if={@avatar_url}
        src={@avatar_url}
        alt={author_display_name(@author)}
        class="w-full h-full object-cover"
      />
      <span :if={!@avatar_url} class="text-xs font-semibold uppercase">
        {author_initial(@author)}
      </span>
    </span>
    """
  end

  # The creator user, whenever the `:user` association is actually loaded — a
  # blueprint may be rendered without it preloaded. We show the author even when
  # the account has no `name` (email signups), falling back on the display name.
  defp author(%{user: %Mehungry.Accounts.User{} = user}), do: user
  defp author(_), do: nil

  # A public professional profile makes the author link resolve to the public
  # nutritionist page; otherwise it points at their regular user profile.
  defp author_path(user) do
    case public_professional_profile(user) do
      %{slug: slug} when is_binary(slug) and slug != "" -> ~p"/nutritionists/#{slug}"
      _ -> ~p"/profile/#{user.id}"
    end
  end

  # Prefer the public professional display name, then the account name, then the
  # local part of the email — the same `name || email` fallback used elsewhere —
  # so an author is always named even for a nameless email account.
  defp author_display_name(user) do
    case public_professional_profile(user) do
      %{display_name: name} when is_binary(name) and name != "" -> name
      _ -> presence(user.name) || email_handle(user)
    end
  end

  defp email_handle(%{email: email}) when is_binary(email) do
    email |> String.split("@") |> List.first()
  end

  defp email_handle(_), do: "Community member"

  # The role line under the name: the nutritionist's specialization for a public
  # professional, else a plain "Meal blueprint author" attribution.
  defp author_role(user) do
    case public_professional_profile(user) do
      %{specialization: spec} when is_binary(spec) and spec != "" -> spec
      %{} -> "Nutritionist"
      _ -> "Meal blueprint author"
    end
  end

  defp author_avatar_url(user) do
    professional_photo =
      case public_professional_profile(user) do
        %{photo_url: url} when is_binary(url) and url != "" -> url
        _ -> nil
      end

    professional_photo || presence(user.profile_pic)
  end

  defp author_initial(user) do
    user |> author_display_name() |> String.first() |> Kernel.||("?")
  end

  # The author's professional profile only when it is loaded *and* public;
  # a private or unloaded profile is treated as absent.
  defp public_professional_profile(%{professional_profile: %{is_public: true} = profile}),
    do: profile

  defp public_professional_profile(_), do: nil

  defp presence(value) when is_binary(value) and value != "", do: value
  defp presence(_), do: nil

  defp plural(1, word), do: word
  defp plural(_, word), do: word <> "s"
end
