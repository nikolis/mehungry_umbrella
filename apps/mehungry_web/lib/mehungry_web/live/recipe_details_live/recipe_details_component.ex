defmodule MehungryWeb.RecipeDetailsComponent do
  use MehungryWeb, :live_component

  import MehungryWeb.CoreComponents
  import MehungryWeb.RecipeComponents

  alias Mehungry.Posts.Comment
  alias Mehungry.{Posts, Users, Food, Accounts, Subscriptions}
  alias Mehungry.AI.RecipeInsight
  alias Mehungry.Social.Facebook
  alias MehungryWeb.InsightGraphicGenerator
  alias Phoenix.LiveView.AsyncResult

  embed_templates("components/*")
  @color_fill "#00A0D0"

  # cancel_comment_reply
  @impl true
  def handle_event("cancel_comment_reply", _, socket) do
    socket =
      socket
      |> assign(:reply, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("generate_graphic", _params, socket) do
    recipe = socket.assigns.recipe
    user = socket.assigns.current_user

    cond do
      is_nil(user) ->
        {:noreply, assign(socket, :must_be_loged_in, 1)}

      Subscriptions.check_quota(user.id, "graphic_generation") == {:error, :quota_exceeded} ->
        {:noreply,
         assign(
           socket,
           :graphic_error,
           "You've used all your graphic generations this month. Upgrade for more."
         )}

      true ->
        recipe_id = recipe.id
        user_id = user.id

        {:noreply,
         socket
         |> assign(:graphic_running, true)
         |> assign(:graphic_result, nil)
         |> assign(:graphic_error, nil)
         |> start_async(:insight_graphic, fn ->
           InsightGraphicGenerator.generate(recipe_id, user_id)
         end)}
    end
  end

  @impl true
  def handle_async(:insight_graphic, {:ok, {:ok, graphic}}, socket) do
    {:noreply,
     socket
     |> assign(:graphic_running, false)
     |> assign(:graphic_result, graphic)
     |> assign(:graphic_error, nil)}
  end

  @impl true
  def handle_async(:insight_graphic, {:ok, {:error, _reason}}, socket) do
    {:noreply,
     socket
     |> assign(:graphic_running, false)
     |> assign(:graphic_error, "Graphic generation failed. Please try again.")}
  end

  @impl true
  def handle_async(:insight_graphic, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:graphic_running, false)
     |> assign(:graphic_error, "Graphic generation failed. Please try again.")}
  end

  @impl true
  def handle_event("post-on-facebook", %{"recipe_id" => recipe_id, "user_id" => user_id}, socket) do
    recipe = recipe_id |> Food.get_recipe!() |> Food.recipe_with_share_image()
    user = Accounts.get_user!(user_id)

    Facebook.post_recipe_container(user, recipe, %{})

    socket =
      socket
      |> assign(:reply, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("post-on-instagram", %{"recipe_id" => recipe_id, "user_id" => user_id}, socket) do
    recipe = recipe_id |> Food.get_recipe!() |> Food.recipe_with_share_image()
    user = Accounts.get_user!(user_id)
    Mehungry.Social.Instagram.post_recipe(user, recipe)

    socket =
      socket
      |> assign(:reply, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("add-reply-form", %{"id" => comment_id}, socket) do
    case is_nil(socket.assigns.current_user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        {comment_id, _} = Integer.parse(comment_id)

        socket =
          socket
          |> assign(:reply, %{comment_id: comment_id})

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "vote_comment",
        %{"id" => comment_id, "reaction" => reaction} = _params,
        socket
      ) do
    case is_nil(socket.assigns.current_user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        {comment_id, _} = Integer.parse(comment_id)

        # socket =
        # socket
        # |> assign(:reply, %{comment_id: comment_id})

        Mehungry.Posts.vote_comment(comment_id, socket.assigns.current_user.id, reaction)

        {:noreply, socket}
    end
  end

  def get_positive_votes(votes) do
    Enum.reduce(votes, 0, fn x, acc ->
      case x.positive do
        true ->
          acc + 1

        false ->
          acc
      end
    end)
  end

  def toggle_user_saved_recipes(socket, recipe_id) do
    case is_nil(socket.assigns.user) do
      true ->
        assign(socket, :must_be_loged_in, 1)

      false ->
        case Enum.any?(socket.assigns.user_recipes, fn x -> x == recipe_id end) do
          true ->
            Users.remove_user_saved_recipe(socket.assigns.user.id, recipe_id)

          false ->
            Users.save_user_recipe(socket.assigns.user.id, recipe_id)
        end
    end
  end

  def get_style2(item_list, user, positive) do
    has =
      case is_nil(user) or is_nil(item_list) or Enum.empty?(item_list) do
        true ->
          false

        false ->
          Enum.any?(item_list, fn x -> x.user_id == user.id and x.positive == positive end)
      end

    case has do
      true ->
        @color_fill

      false ->
        "#FFFFFF"
    end
  end

  # Total active time shown in the recipe header — prep + cook lower bounds,
  # tolerating a nil on either side.
  defp total_time(recipe) do
    (recipe.preperation_time_lower_limit || 0) + (recipe.cooking_time_lower_limit || 0)
  end

  # Difficulty is stored as an integer (1/2/3); tolerate legacy string values too.
  # Returns {localized label, tailwind dot color}. (The old stats-row matched on
  # the string "Easy", so it always fell through to the red "X" — this fixes it.)
  defp difficulty_label(d) when d in [1, "1", "Easy"], do: {gettext("Easy"), "bg-green-500"}
  defp difficulty_label(d) when d in [2, "2", "Medium"], do: {gettext("Medium"), "bg-yellow-500"}
  defp difficulty_label(d) when d in [3, "3", "Hard"], do: {gettext("Hard"), "bg-red-500"}
  defp difficulty_label(_), do: {gettext("Easy"), "bg-green-500"}

  # Regulated per-serving nutrient claims (Food.NutrientClaims → recipes.badges),
  # ordered for the NRV panel: "high in" before "source of", each by descending
  # %NRV. See docs/implementation/food/food.md (NutrientClaims).
  defp claim_rows(recipe) do
    (Map.get(recipe, :badges) || [])
    |> Enum.filter(&(&1["level"] in ["high", "source"]))
    |> Enum.sort_by(fn b -> {b["level"] == "source", -(b["percent_nrv"] || 0)} end)
  end

  # Whole-number formatting for the at-a-glance macro tiles. RecipeInsight.macros/1
  # always returns numbers (0 when a recipe has no computed nutrition).
  defp fmt_macro(v), do: v |> round() |> Integer.to_string()

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="recipe_presentation_modal"
      phx-hook="RecipeDetailTimer"
      class="recipe-details-page min-h-screen bg-ink text-parchment pb-10"
    >
      <div class="mx-auto px-4 py-8 max-w-4xl">
        <% hero_image = MehungryWeb.RecipeSeo.absolute_image(@recipe.image_url) %>
        <% {diff_label, diff_dot} = difficulty_label(@recipe.difficulty) %>
        <% macros = RecipeInsight.macros(@recipe) %>
        <% has_nutrition = macros.calories > 0 %>
        <% claims = claim_rows(@recipe) %>
        <% following? = not is_nil(@current_user) and @recipe.user.id in @user_follows %>
        <% locale = Gettext.get_locale(MehungryWeb.Gettext) %>
        <!-- Hero -->
        <div class="bg-ink-panel rounded-2xl overflow-hidden border border-ink-panel2 mb-6">
          <!-- Image -->
          <div class="relative aspect-video bg-ink-panel2">
            <%= if hero_image do %>
              <img src={hero_image} alt={@recipe.title} class="w-full h-full object-cover" />
            <% else %>
              <div class="w-full h-full flex items-center justify-center">
                <svg
                  class="w-20 h-20 text-parchment-dim"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
                  />
                </svg>
              </div>
            <% end %>
            <.recipe_like_container
              type="browse"
              user_recipes={@user_recipes}
              recipe={@recipe}
              current_user={@current_user}
              id={@id <> "like_container"}
              myself={@myself}
            />
            <%= if hero_image do %>
              <button
                type="button"
                phx-click="generate_graphic"
                phx-target={@myself}
                disabled={@graphic_running}
                class="absolute bottom-3 right-3 flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-paprika/90 hover:bg-paprika disabled:opacity-60 text-white font-semibold text-xs shadow-lg backdrop-blur transition-colors"
              >
                <.icon
                  name={if @graphic_running, do: "hero-arrow-path", else: "hero-sparkles"}
                  class={"w-4 h-4 #{if @graphic_running, do: "animate-spin"}"}
                />
                {if @graphic_running, do: "Creating graphic…", else: "Shareable graphic"}
              </button>
            <% end %>
          </div>

          <div
            :if={@graphic_error}
            class="mx-6 mt-4 rounded-lg bg-red-900/40 border border-red-700 text-red-200 text-xs px-3 py-2"
          >
            {@graphic_error}
          </div>

          <div
            :if={@graphic_result}
            class="mx-6 mt-4 rounded-xl bg-ink border border-ink-panel2 p-3 flex gap-3"
          >
            <img
              src={@graphic_result.image_url}
              alt="Shareable insight graphic"
              class="w-28 h-28 rounded-lg object-cover shrink-0"
            />
            <div class="min-w-0 flex flex-col">
              <p class="text-parchment text-sm font-semibold">{@graphic_result.headline}</p>
              <p class="text-parchment-dim text-xs mt-1 line-clamp-3">{@graphic_result.caption}</p>
              <a
                href={@graphic_result.image_url}
                target="_blank"
                rel="noopener"
                class="mt-auto inline-flex items-center gap-1.5 text-paprika hover:text-paprika-soft text-xs font-semibold"
              >
                <.icon name="hero-arrow-down-tray" class="w-3.5 h-3.5" /> Download to share
              </a>
            </div>
          </div>
          <!-- Content -->
          <div class="p-6">
            <!-- Eyebrow: cuisine · difficulty -->
            <p class="font-mono text-[0.72rem] tracking-[0.14em] uppercase text-basil flex flex-wrap items-center gap-2 mb-3">
              <span :if={@recipe.cousine not in [nil, ""]}>{@recipe.cousine}</span>
              <span
                :if={@recipe.cousine not in [nil, ""]}
                class="w-1 h-1 rounded-full bg-parchment-dim/60"
              >
              </span>
              <span class="inline-flex items-center gap-1.5">
                <span class={["w-1.5 h-1.5 rounded-full", diff_dot]}></span>{diff_label}
              </span>
            </p>

            <h1 class="text-2xl md:text-3xl font-display font-medium text-parchment mb-2">
              {@recipe.title}
            </h1>
            <p class="text-parchment-dim mb-4">{@recipe.description}</p>

            <.recipe_tags recipe={@recipe} />
            <!-- Stats chips -->
            <div class="flex flex-wrap gap-2 mt-4 mb-5">
              <span
                :if={total_time(@recipe) > 0}
                class="font-mono text-xs px-2.5 py-1 rounded-md bg-black/20 border border-ink-panel2 text-parchment"
              >
                {total_time(@recipe)} {gettext("min total")}
              </span>
              <span
                :if={@recipe.preperation_time_lower_limit}
                class="font-mono text-xs px-2.5 py-1 rounded-md bg-black/20 border border-ink-panel2 text-parchment-dim"
              >
                {gettext("Prep")} {@recipe.preperation_time_lower_limit}
              </span>
              <span
                :if={@recipe.cooking_time_lower_limit}
                class="font-mono text-xs px-2.5 py-1 rounded-md bg-black/20 border border-ink-panel2 text-parchment-dim"
              >
                {gettext("Cook")} {@recipe.cooking_time_lower_limit}
              </span>
              <span
                :if={@recipe.servings}
                class="font-mono text-xs px-2.5 py-1 rounded-md bg-black/20 border border-ink-panel2 text-parchment-dim"
              >
                {@recipe.servings} {gettext("servings")}
              </span>
            </div>
            <!-- Author -->
            <div class="flex items-center justify-between gap-3 p-4 border border-ink-panel2 bg-black/20 rounded-xl">
              <div class="flex items-center gap-3 min-w-0">
                <img
                  src={@recipe.user.profile_pic}
                  alt={@recipe.user.name}
                  class="w-11 h-11 rounded-full object-cover flex-none"
                />
                <div class="min-w-0">
                  <p class="font-mono text-[0.64rem] tracking-[0.12em] uppercase text-parchment-dim">
                    {gettext("Recipe by")}
                  </p>
                  <a
                    href={"/profile/#{@recipe.user.id}"}
                    class="block truncate text-parchment font-semibold hover:text-paprika-soft transition"
                  >
                    {@recipe.user.name}
                  </a>
                </div>
              </div>
              <%= if !is_nil(@current_user) do %>
                <button
                  phx-click="save_user_follow"
                  phx-value-follow_id={@recipe.user.id}
                  class={[
                    "px-4 py-2 rounded-lg font-bold transition flex-none",
                    (following? && "text-parchment-dim hover:text-parchment") ||
                      "bg-paprika hover:bg-paprika-soft text-ink"
                  ]}
                >
                  {if following?, do: gettext("Following"), else: gettext("Follow")}
                </button>
              <% else %>
                <a
                  href="/users/log_in"
                  class="px-4 py-2 rounded-lg font-bold transition bg-paprika hover:bg-paprika-soft text-ink flex-none"
                >
                  {gettext("Follow")}
                </a>
              <% end %>
            </div>
          </div>
        </div>
        <!-- At a glance: per-serving macros -->
        <div
          :if={has_nutrition}
          class="grid grid-cols-2 sm:grid-cols-4 gap-px bg-ink-panel2 border border-ink-panel2 rounded-xl overflow-hidden"
        >
          <div class="bg-ink-panel p-4">
            <div class="text-2xl font-display text-parchment [font-variant-numeric:tabular-nums]">
              {fmt_macro(macros.calories)}<span class="text-sm text-parchment-dim"> kcal</span>
            </div>
            <div class="text-xs uppercase tracking-wide text-parchment-dim mt-0.5">
              {gettext("Energy")}
            </div>
          </div>
          <div class="bg-ink-panel p-4">
            <div class="text-2xl font-display text-parchment [font-variant-numeric:tabular-nums]">
              {fmt_macro(macros.protein_g)}<span class="text-sm text-parchment-dim"> g</span>
            </div>
            <div class="text-xs uppercase tracking-wide text-parchment-dim mt-0.5">
              {gettext("Protein")}
            </div>
          </div>
          <div class="bg-ink-panel p-4">
            <div class="text-2xl font-display text-parchment [font-variant-numeric:tabular-nums]">
              {fmt_macro(macros.carbs_g)}<span class="text-sm text-parchment-dim"> g</span>
            </div>
            <div class="text-xs uppercase tracking-wide text-parchment-dim mt-0.5">
              {gettext("Carbs")}
            </div>
          </div>
          <div class="bg-ink-panel p-4">
            <div class="text-2xl font-display text-parchment [font-variant-numeric:tabular-nums]">
              {fmt_macro(macros.fat_g)}<span class="text-sm text-parchment-dim"> g</span>
            </div>
            <div class="text-xs uppercase tracking-wide text-parchment-dim mt-0.5">
              {gettext("Fat")}
            </div>
          </div>
        </div>
        <%!-- "Per serving" note + inline link that opens the full breakdown in a
             modal (keeps the card uncluttered). --%>
        <p :if={has_nutrition} class="text-xs text-parchment-dim mt-2">
          {gettext("Per serving.")}
          <button
            type="button"
            phx-click={show_modal("recipe-nutrition-#{@recipe.id}")}
            class="ml-1 inline-flex items-center gap-1 font-medium text-basil hover:text-basil-soft underline underline-offset-2 transition-colors"
          >
            {gettext("Full nutrition facts")}
            <.icon name="hero-arrow-up-right" class="w-3.5 h-3.5" />
          </button>
        </p>
        <!-- Nutrient-claim panel: the nutritionist differentiator. Regulated,
             per-serving claims drawn from recipes.badges (Food.NutrientClaims). -->
        <section
          :if={claims != []}
          class="mt-10 bg-ink-panel border border-ink-panel2 rounded-xl p-6"
        >
          <div class="flex items-baseline justify-between flex-wrap gap-2">
            <div>
              <p class="font-mono text-[0.7rem] tracking-[0.14em] uppercase text-basil">
                {gettext("Nutrient profile")}
              </p>
              <h2 class="text-xl font-display font-medium text-parchment mt-0.5">
                {gettext("Claims & reference intakes")}
              </h2>
            </div>
            <span class="font-mono text-xs text-parchment-dim">
              {gettext("per serving · % of adult NRV")}
            </span>
          </div>

          <div class="flex gap-5 flex-wrap text-xs text-parchment-dim mt-3 mb-5">
            <span class="inline-flex items-center gap-1.5">
              <span class="w-0.5 h-3.5 bg-parchment-dim/70"></span>{gettext("15% — source of")}
            </span>
            <span class="inline-flex items-center gap-1.5">
              <span class="w-0.5 h-3.5 bg-paprika"></span>{gettext("30% — high in")}
            </span>
          </div>

          <div>
            <div
              :for={claim <- claims}
              class="grid grid-cols-[1fr_auto] sm:grid-cols-[140px_1fr_96px] items-center gap-x-4 gap-y-1.5 py-2.5 border-t border-ink-panel2 last:border-b"
            >
              <span class="font-semibold text-parchment">
                {MehungryWeb.NutrientLabels.translate_name(claim["nutrient"])}
              </span>
              <div class="col-span-2 sm:col-span-1 order-last sm:order-none relative h-2.5 rounded bg-ink-panel2">
                <div
                  class={[
                    "absolute inset-y-0 left-0 rounded",
                    (claim["level"] == "high" && "bg-basil") || "bg-paprika"
                  ]}
                  style={"width: #{min(claim["percent_nrv"] || 0, 100)}%"}
                >
                </div>
                <span class="absolute -top-0.5 -bottom-0.5 w-0.5 bg-parchment-dim/60" style="left: 15%">
                </span>
                <span class="absolute -top-0.5 -bottom-0.5 w-0.5 bg-paprika" style="left: 30%"></span>
              </div>
              <span class={[
                "justify-self-end font-mono text-[0.64rem] font-semibold tracking-wide px-1.5 py-0.5 rounded whitespace-nowrap",
                (claim["level"] == "high" && "bg-basil/15 text-basil-soft") ||
                  "bg-paprika/15 text-paprika-soft"
              ]}>
                {(claim["level"] == "high" && gettext("High")) || gettext("Source")} · {claim[
                  "percent_nrv"
                ]}%
              </span>
            </div>
          </div>

          <p class="text-xs text-parchment-dim mt-4 pt-4 border-t border-dashed border-ink-panel2">
            {gettext(
              "Nutrients computed from matched USDA ingredients; claims assessed against EU Reg. 1169/2011 & 1924/2006 (≥15% NRV “source of”, ≥30% “high in”, per serving)."
            )}
          </p>
        </section>
        <!-- Ingredients + Method -->
        <% step_count = length(@recipe.steps) %>
        <section class="mt-6 bg-ink-panel border border-ink-panel2 rounded-xl overflow-hidden">
          <div class="grid md:grid-cols-2 md:divide-x divide-ink-panel2">
            <div class="p-6">
              <p class="font-mono text-[0.7rem] tracking-[0.14em] uppercase text-basil">
                {gettext("Ingredients")}
              </p>
              <h2 class="text-xl font-display font-medium text-parchment mt-0.5">
                {ngettext("For %{count} serving", "For %{count} servings", @recipe.servings || 1,
                  count: @recipe.servings || 1
                )}
              </h2>
              <.recipe_ingredients
                recipe_ingredients={@recipe.recipe_ingredients}
                ingredient_display_names={@ingredient_display_names}
              />
            </div>
            <div class="p-6 border-t md:border-t-0 border-ink-panel2">
              <p class="font-mono text-[0.7rem] tracking-[0.14em] uppercase text-basil">
                {gettext("Method")}
              </p>
              <h2 class="text-xl font-display font-medium text-parchment mt-0.5">
                {ngettext("%{count} step", "%{count} steps", step_count, count: step_count)}
              </h2>
              <.recipe_steps
                steps={@recipe.steps}
                original_url={@recipe.original_url}
                author={@recipe.author}
                license={@recipe.license}
              />
            </div>
          </div>
        </section>
        <!-- Comments -->
        <section
          class="mt-6 bg-ink-panel rounded-xl border border-ink-panel2 p-6"
          id="comments"
        >
          <h2 class="text-xl font-display font-medium text-parchment mb-4">
            <.async_result :let={comments} assign={@recipe_comments}>
              <:loading>{gettext("Comments")}</:loading>
              <:failed :let={_reason}>{gettext("Comments")}</:failed>
              {gettext("Comments")} · {length(comments)}
            </.async_result>
          </h2>

          <%= if !is_nil(@current_user) do %>
            <.live_component
              module={MehungryWeb.RecipeDetailsLive.FormComponentComment}
              id="comment_form"
              title={@page_title}
              action={@live_action}
              current_user={@current_user}
              comment={@comment}
            />
          <% end %>

          <.async_result :let={comments} assign={@recipe_comments}>
            <:loading>
              <div class="text-center py-8 text-parchment-dim">{gettext("Loading comments…")}</div>
            </:loading>
            <:failed :let={_reason}>
              <div class="text-center py-8 text-parchment-dim">
                {gettext("Couldn't load comments.")}
              </div>
            </:failed>
            <%= if Enum.empty?(comments) do %>
              <div class="text-center py-8 text-parchment-dim">
                {gettext("No comments yet. Be the first to comment!")}
              </div>
            <% else %>
              <div class="mt-2 divide-y divide-ink-panel2">
                <%= for comment <- comments do %>
                  <.comment
                    comment={comment}
                    user={comment.user}
                    current_user={@current_user}
                    live_action={@live_action}
                    page_title={@page_title}
                    myself={@myself}
                    reply={@reply}
                  />
                <% end %>
              </div>
            <% end %>
          </.async_result>
        </section>

        <%!-- Full nutrition lives in a modal (opened by the button above) rather
             than inline, to keep the recipe card uncluttered. The accordion is
             the same shared NutritionAccordion used on the calendar. --%>
        <.modal
          :if={has_nutrition}
          id={"recipe-nutrition-#{@recipe.id}"}
          show={false}
          on_cancel={%JS{}}
        >
          {MehungryWeb.RecipeComponents.recipe_nutrients(@recipe, locale)}
        </.modal>
      </div>
    </div>
    """
  end

  def handle_info(%{new_vote: vote, type_: _type_}, socket) do
    post = Posts.get_post!(vote.post_id)

    posts =
      Enum.map(socket.assigns.posts, fn x ->
        case x.id == post.id do
          false ->
            x

          true ->
            post
        end
      end)

    socket =
      socket
      |> assign(:posts, posts)

    {:noreply, socket}
  end

  def handle_info(%{new_comment: comment}, socket) do
    recipe_comments = socket.assigns.recipe_comments
    comment = Posts.get_comment!(comment.id)

    comments =
      Enum.into(Enum.filter(recipe_comments, fn x -> x.id != comment.id end), [comment])
      |> Enum.sort_by(& &1.updated_at)

    socket =
      socket
      |> assign(:recipe_comments, comments)

    {:noreply, socket}
  end

  @doc """
    Every LiveView that uses this component is also importing
    MehungryWeb.LiveHelpers, :hook_for_update_recipe_details_component
    behaviour so this update is here to handle the updates by this behaviour
    so as not to make a mess with the "typical" update
  """
  @impl true
  def update(%{reply: nil} = assigns, socket) do
    reply = Map.get(assigns, :reply, nil)
    socket = assign(socket, :reply, reply)

    {:ok, socket}
  end

  @impl true
  def update(%{recipe_comments: recipe_comments} = _assigns, socket) do
    # Live comment updates arrive as a plain list; fold it into the AsyncResult
    # the template renders so a new/edited comment shows without a re-fetch.
    async =
      case socket.assigns[:recipe_comments] do
        %AsyncResult{} = ar -> AsyncResult.ok(ar, recipe_comments)
        _ -> AsyncResult.ok(recipe_comments)
      end

    {:ok, assign(socket, :recipe_comments, async)}
  end

  @impl true
  def update(assigns, socket) do
    user_follows =
      if(is_nil(Map.get(assigns, :user_follows))) do
        []
      else
        assigns.user_follows
      end

    reply = Map.get(assigns, :reply, nil)

    ingredient_ids =
      assigns.recipe.recipe_ingredients
      |> Enum.map(& &1.ingredient_id)

    socket =
      socket
      |> assign(assigns)
      |> assign(:recipe, assigns.recipe)
      |> assign(:reply, reply)
      |> assign(:user_follows, user_follows)
      |> assign_new(:graphic_running, fn -> false end)
      |> assign_new(:graphic_result, fn -> nil end)
      |> assign_new(:graphic_error, fn -> nil end)
      |> assign(
        :comment,
        get_when_first_exists(assigns.current_user, fn ->
          %Comment{user_id: assigns.current_user.id, recipe_id: assigns.recipe.id}
        end)
      )
      |> maybe_assign_display_names(assigns.recipe, ingredient_ids, assigns.current_user)
      |> maybe_load_recipe_async(assigns.recipe, ingredient_ids)

    {:ok, socket}
  end

  # Resolve the recipe's ingredient display names in the viewer's language. The
  # profile lookup + name resolution depend only on (recipe, viewer), so skip
  # them when neither changed — otherwise every unrelated parent re-render of this
  # (widely-reused) modal re-ran a profile query + a name resolve. Guarded the same
  # once-per-recipe way as maybe_load_recipe_async/3 below.
  defp maybe_assign_display_names(socket, recipe, ingredient_ids, current_user) do
    user_id = current_user && current_user.id

    if socket.assigns[:display_names_key] == {recipe.id, user_id} do
      socket
    else
      profile =
        case current_user do
          nil -> nil
          user -> Accounts.get_user_profile_by_user_id(user.id)
        end

      user_language = (profile && profile.language_preference) || recipe.language_name
      display_names = Food.ingredient_display_names(ingredient_ids, user_language)

      socket
      |> assign(:display_names_key, {recipe.id, user_id})
      |> assign(:ingredient_display_names, display_names)
    end
  end

  # Comments and nutrient interactions are below the fold (comments even start
  # collapsed), so they load asynchronously: the modal paints immediately with
  # the recipe, ingredients and flags, then these fill in. Guarded to load once
  # per recipe so a routine parent re-render doesn't reset them to a spinner or
  # re-run the queries. The live comment-update path (send_update with
  # `%{recipe_comments: ...}`) refreshes the list without going through here.
  defp maybe_load_recipe_async(socket, recipe, _ingredient_ids) do
    if socket.assigns[:async_recipe_id] == recipe.id do
      socket
    else
      recipe_id = recipe.id

      socket
      |> assign(:async_recipe_id, recipe_id)
      |> assign_async(:recipe_comments, fn ->
        {:ok, %{recipe_comments: Food.get_recipe_comments(recipe_id)}}
      end)
      # "Nutrition Insights" (nutrient-interaction panel) is HIDDEN for now — its
      # recipe-level inference is low-signal/occasionally misleading (it keys on
      # per-100g ingredient density, not the amount actually used). See
      # docs/implementation/food/nutrient_interactions.md. Return [] so the panel renders nothing
      # and we skip the DB query; to re-enable, restore the call below and un-hide
      # the render block (search "Nutrition Insights").
      #   Food.get_interactions_for_ingredients(ingredient_ids)
      |> assign_async(:interactions, fn -> {:ok, %{interactions: []}} end)
    end
  end
end
