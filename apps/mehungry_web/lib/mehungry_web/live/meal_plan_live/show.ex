defmodule MehungryWeb.MealPlanLive.Show do
  @moduledoc """
  Public, crawlable preview of a published weekly meal plan
  (`/meal-plans/:slug`) — the SEO + sharing landing page for meal planning.

  Rendered **synchronously** so the disconnected (crawler) render already carries
  the full day-by-day plan, the daily-average macros, the grocery list and the
  prose summary — mirroring `BlueprintLive.Show`. Every recipe links to its own
  indexable `/browse/:id` page (internal linking), and JSON-LD (`BreadcrumbList`
  + `ItemList`) describes the recipes in the plan.

  The plan is an immutable snapshot (`Mehungry.PublishedPlans`), so this page is
  stable for Google and never leaks the author's live calendar.
  """
  use MehungryWeb, :live_view

  alias Mehungry.History.MealType
  alias Mehungry.Posts
  alias Mehungry.PublishedPlans
  alias MehungryWeb.CalendarLive.Calendar.Locale

  @base_url "https://www.m3hungry.com"

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_new(socket, :current_user, fn -> nil end)}
  end

  @impl true
  def handle_params(%{"slug" => slug} = params, _uri, socket) do
    plan = PublishedPlans.get_public_plan_by_slug!(slug)
    socket = assign(socket, :from, params["from"])
    locale = Gettext.get_locale(MehungryWeb.Gettext)

    # Localize everything the snapshot knows how to link to, in the viewer's
    # language. The snapshot carries the real FK **links** for both ingredient
    # meals and (since this feature) the grocery list (`ingredient_id` +
    # `measurement_unit_id`), so those are localized by id — bullet-proof against
    # name drift. Older snapshots that only carry names fall back to the
    # ingredient-name join.
    #
    # Ingredient/unit translation rows live under several language codes for one
    # locale (canonical ISO + legacy alias, e.g. "el" + "Gr"); read **all** of
    # them and let the canonical code win — exactly as the calendar (`History`)
    # and recipe translations do. A single raw-locale lookup would miss rows
    # stored under the other code. All three maps are empty for English.
    codes = Mehungry.Languages.Locale.data_codes(locale)

    ingredient_names_by_id =
      merge_by_codes(codes, &Mehungry.Food.ingredient_display_names(page_ingredient_ids(plan), &1))

    ingredient_names =
      merge_by_codes(
        codes,
        &Mehungry.Food.ingredient_display_names_by_name(page_ingredient_names(plan), &1)
      )

    unit_names =
      merge_by_codes(codes, &Mehungry.Food.get_unit_translations_map(page_unit_ids(plan), &1))

    {:noreply,
     socket
     |> assign(:plan, plan)
     |> assign(:locale, locale)
     |> assign(:ingredient_names_by_id, ingredient_names_by_id)
     |> assign(:ingredient_names, ingredient_names)
     |> assign(:unit_names, unit_names)
     |> assign(:share_url, url(~p"/meal-plans/#{slug}"))
     |> assign_share_text(plan, ingredient_names_by_id, ingredient_names, unit_names)
     |> assign_plan_social(plan)
     |> assign_seo(plan)}
  end

  # Build the two copy-ready social captions (a short image caption + a longer
  # text-only post) from the plan snapshot, in the viewer's language. Pure — safe
  # in the synchronous (crawler) render too.
  defp assign_share_text(socket, plan, ingredient_names_by_id, ingredient_names, unit_names) do
    opts = [
      share_url: socket.assigns.share_url,
      locale: socket.assigns.locale,
      ingredient_names_by_id: ingredient_names_by_id,
      ingredient_names: ingredient_names,
      unit_names: unit_names
    ]

    socket
    |> assign(:share_image_caption, MehungryWeb.MealPlanShareText.image_caption(plan, opts))
    |> assign(:share_text_post, MehungryWeb.MealPlanShareText.text_post(plan, opts))
  end

  # Loads the plan's feed post (likes + comments live on the post, not the
  # immutable plan snapshot) and subscribes to its topic for live updates. Older
  # plans with no feed post simply render without the social block.
  defp assign_plan_social(socket, plan) do
    post = Posts.get_weekly_plan_post_for_plan(plan.id)

    if post && connected?(socket) do
      # Votes come on the shared post topic; comments on a dedicated comments
      # topic (see `Posts.create_post_comment/1` for why they're separate).
      Posts.subscribe_to_post(%{post_id: post.id})
      Posts.subscribe_to_post_comments(post.id)
    end

    socket
    |> assign(:post, post)
    |> assign_engagement(post)
    |> assign(:comment_text, "")
  end

  defp assign_engagement(socket, nil) do
    socket
    |> assign(:like_count, 0)
    |> assign(:liked_by_me, false)
    |> assign(:comments, [])
  end

  defp assign_engagement(socket, post) do
    user = socket.assigns[:current_user]

    socket
    |> assign(:like_count, length(post.upvotes))
    |> assign(:liked_by_me, user && Enum.any?(post.upvotes, &(&1.user_id == user.id)))
    |> assign(:comments, Posts.list_post_comments(post.id))
  end

  @impl true
  def handle_event("use_plan", _params, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/users/log_in")}

      user ->
        start_date = Date.beginning_of_week(Date.utc_today())

        case PublishedPlans.import_to_calendar(socket.assigns.plan, user.id, start_date) do
          {:ok, 0, _skipped} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("This plan has no meals that can be added to a calendar.")
             )}

          {:ok, created, _skipped} ->
            {:noreply,
             socket
             |> put_flash(
               :info,
               gettext("Added %{count} meals to your calendar for this week.", count: created)
             )
             |> push_navigate(to: ~p"/calendar")}
        end
    end
  end

  @impl true
  def handle_event("toggle_like", _params, socket) do
    case {socket.assigns.current_user, socket.assigns.post} do
      {nil, _} ->
        {:noreply, push_navigate(socket, to: ~p"/users/log_in")}

      {_user, nil} ->
        {:noreply, socket}

      {user, post} ->
        Posts.upvote_post(post.id, user.id)
        # The broadcast comes back on the post topic and refreshes the counts.
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_comment", %{"comment" => %{"text" => text}}, socket) do
    text = String.trim(text || "")

    case {socket.assigns.current_user, socket.assigns.post} do
      {nil, _} ->
        {:noreply, push_navigate(socket, to: ~p"/users/log_in")}

      {_user, nil} ->
        {:noreply, socket}

      {_user, _post} when text == "" ->
        {:noreply, socket}

      {user, post} ->
        case Posts.create_post_comment(%{text: text, user_id: user.id, post_id: post.id}) do
          {:ok, _comment} ->
            # The broadcast refreshes the thread (here and on any open feed card).
            {:noreply, assign(socket, :comment_text, "")}

          {:error, _changeset} ->
            {:noreply,
             put_flash(socket, :error, gettext("Could not post your comment. Please try again."))}
        end
    end
  end

  @impl true
  def handle_info(%{new_vote: _vote, type_: _type_}, socket) do
    post = socket.assigns.post && Posts.get_weekly_plan_post_for_plan(socket.assigns.plan.id)
    {:noreply, socket |> assign(:post, post) |> assign_engagement(post)}
  end

  @impl true
  def handle_info(%{new_comment: comment}, socket) do
    comments = socket.assigns.comments ++ [comment]
    {:noreply, assign(socket, :comments, Enum.uniq_by(comments, & &1.id))}
  end

  # ── View ────────────────────────────────────────────────────────────────────

  # The breadcrumb's "back" link — returns the viewer to wherever they opened the
  # plan from (carried in the `from` query param) instead of always Home. The
  # owner's profile tab is gated on it actually being the owner viewing.
  defp back_target(%{from: "profile", current_user: %{id: uid}, plan: %{user_id: uid}}),
    do: {~p"/profile?#{[tab: "meal_plans"]}", gettext("Your profile")}

  defp back_target(%{from: "home"}), do: {~p"/home", gettext("Home")}

  defp back_target(%{from: "browse"}),
    do: {~p"/browse?#{[mode: "meal_plans"]}", gettext("Meal Plans")}

  defp back_target(%{from: "meal_plans"}), do: {~p"/meal-plans", gettext("Meal Plans")}
  defp back_target(_), do: {~p"/meal-plans", gettext("Meal Plans")}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-ink text-parchment pb-16">
      <div class="container max-w-3xl mx-auto px-4 py-8">
        <nav class="text-xs text-parchment-dim mb-4" aria-label="Breadcrumb">
          <% {back_path, back_label} = back_target(assigns) %>
          <.link navigate={back_path} class="hover:text-parchment">{back_label}</.link>
          <span class="mx-1">›</span>
          <span class="text-parchment">{gettext("Meal plan")}</span>
        </nav>

        <header class="bg-ink-panel border border-ink-panel2 rounded-2xl p-6 mb-6">
          <%!-- The shareable card image (when the plan was published from the
                calendar share flow). --%>
          <img
            :if={@plan.og_image_url}
            src={@plan.og_image_url}
            alt={@plan.title}
            class="w-full rounded-xl border border-ink-panel2 mb-5"
          />

          <h1 class="text-2xl md:text-3xl font-display font-medium text-parchment">
            {@plan.title}
          </h1>

          <p :if={author_name(@plan)} class="text-sm text-parchment-dim mt-1">
            {gettext("Shared by")}
            <.link
              navigate={~p"/profile/#{@plan.user_id}"}
              class="text-paprika-soft font-semibold hover:underline"
            >
              {author_name(@plan)}
            </.link>
          </p>

          <p class="text-parchment-dim mt-3 leading-relaxed">{@plan.summary_text}</p>

          <div class="flex flex-wrap items-center gap-1.5 mt-4">
            <span class="text-[11px] px-2 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim">
              {gettext("7 days")}
            </span>
            <span
              :if={@plan.recipe_count > 0}
              class="text-[11px] px-2 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim"
            >
              {ngettext("%{count} recipe", "%{count} recipes", @plan.recipe_count)}
            </span>
            <span
              :if={@plan.goal_label}
              class="text-[11px] px-2 py-0.5 rounded-full bg-paprika/15 text-paprika-soft"
            >
              {@plan.goal_label}
            </span>
          </div>

          <!-- Truthful daily-average macros (same numbers as the calendar). -->
          <dl class="grid grid-cols-2 sm:grid-cols-4 gap-2 mt-5">
            <.macro_tile
              label={gettext("Calories/day")}
              value={"#{macro(@plan, "energy_kcal")} kcal"}
            />
            <.macro_tile label={gettext("Protein")} value={"#{macro(@plan, "protein_g")} g"} />
            <.macro_tile label={gettext("Carbs")} value={"#{macro(@plan, "carbs_g")} g"} />
            <.macro_tile label={gettext("Fat")} value={"#{macro(@plan, "fat_g")} g"} />
          </dl>

          <div class="flex flex-wrap items-center gap-2 mt-6" x-data="{}">
            <button
              :if={@current_user}
              type="button"
              phx-click="use_plan"
              class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink text-sm font-bold transition"
            >
              {gettext("Add to my calendar")}
            </button>
            <.link
              :if={!@current_user}
              navigate={~p"/users/log_in"}
              class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink text-sm font-bold transition"
            >
              {gettext("Log in to use this plan")}
            </.link>
            <a
              href={"https://www.facebook.com/sharer/sharer.php?u=" <> URI.encode_www_form(@share_url)}
              target="_blank"
              rel="noopener"
              class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-[#1877F2] hover:opacity-90 text-white text-sm font-semibold transition"
            >
              {gettext("Share on Facebook")}
            </a>
            <button
              type="button"
              x-on:click={"navigator.clipboard.writeText('#{@share_url}'); $el.innerText = '#{gettext("Copied!")}'"}
              class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-ink-panel2 hover:bg-ink text-parchment text-sm font-semibold transition"
            >
              {gettext("Copy link")}
            </button>
            <button
              :if={@post}
              type="button"
              phx-click="toggle_like"
              aria-label={gettext("Like")}
              class={[
                "inline-flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-semibold transition",
                if(@liked_by_me,
                  do: "bg-paprika/15 text-paprika-soft",
                  else: "bg-ink-panel2 hover:bg-ink text-parchment"
                )
              ]}
            >
              <svg
                class={["w-5 h-5", if(@liked_by_me, do: "text-red-500", else: "")]}
                fill={if @liked_by_me, do: "currentColor", else: "none"}
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"
                />
              </svg>
              <span class="[font-variant-numeric:tabular-nums]">{@like_count}</span>
            </button>
          </div>

          <%!-- Copy-ready social posts for external platforms: a short caption to
                pair with the shareable image, and a longer text-only post. --%>
          <div
            class="mt-5 border-t border-ink-panel2 pt-5"
            x-data={"{ open: false, tab: '#{if @plan.og_image_url, do: "image", else: "text"}' }"}
          >
            <button
              type="button"
              x-on:click="open = !open"
              class="inline-flex items-center gap-2 text-sm font-semibold text-paprika-soft hover:text-paprika transition"
            >
              <span>{gettext("Share as a post")}</span>
              <span x-text="open ? '▴' : '▾'" aria-hidden="true"></span>
            </button>

            <div x-show="open" x-cloak class="mt-4" style="display: none;">
              <div class="flex gap-2 mb-3">
                <button
                  :if={@plan.og_image_url}
                  type="button"
                  x-on:click="tab = 'image'"
                  x-bind:class="tab === 'image' ? 'bg-paprika/15 text-paprika-soft' : 'bg-ink-panel2 text-parchment-dim hover:text-parchment'"
                  class="px-3 py-1.5 rounded-lg text-xs font-semibold transition"
                >
                  {gettext("Image + caption")}
                </button>
                <button
                  type="button"
                  x-on:click="tab = 'text'"
                  x-bind:class="tab === 'text' ? 'bg-paprika/15 text-paprika-soft' : 'bg-ink-panel2 text-parchment-dim hover:text-parchment'"
                  class="px-3 py-1.5 rounded-lg text-xs font-semibold transition"
                >
                  {gettext("Text post")}
                </button>
              </div>

              <%!-- Image + caption: download the card, copy the caption, paste into
                    Instagram / Pinterest / Facebook. --%>
              <div :if={@plan.og_image_url} x-show="tab === 'image'">
                <p class="text-xs text-parchment-dim mb-2">
                  {gettext("Download the image, copy the caption, then post them together.")}
                </p>
                <textarea
                  id="plan-image-caption"
                  readonly
                  rows="4"
                  class="w-full rounded-lg bg-ink-panel2 border border-ink-panel2 text-parchment text-sm px-3 py-2 focus:outline-none focus:border-paprika-soft resize-none"
                >{@share_image_caption}</textarea>
                <div class="flex flex-wrap items-center gap-2 mt-2">
                  <a
                    href={@plan.og_image_url}
                    download
                    target="_blank"
                    rel="noopener"
                    class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-ink-panel2 hover:bg-ink text-parchment text-sm font-semibold transition"
                  >
                    {gettext("Download image")}
                  </a>
                  <button
                    type="button"
                    id="copy-image-caption"
                    phx-hook="Copy"
                    data-to="#plan-image-caption"
                    class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink text-sm font-bold transition"
                  >
                    <span>{gettext("Copy caption")}</span>
                  </button>
                </div>
              </div>

              <%!-- Text-only post: copy, or share straight to the native sheet
                    (X / Threads / Facebook status / WhatsApp). --%>
              <div x-show="tab === 'text'">
                <textarea
                  id="plan-text-post"
                  readonly
                  rows="10"
                  class="w-full rounded-lg bg-ink-panel2 border border-ink-panel2 text-parchment text-sm px-3 py-2 focus:outline-none focus:border-paprika-soft resize-none"
                >{@share_text_post}</textarea>
                <div class="flex flex-wrap items-center gap-2 mt-2">
                  <button
                    type="button"
                    id="copy-text-post"
                    phx-hook="Copy"
                    data-to="#plan-text-post"
                    class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink text-sm font-bold transition"
                  >
                    <span>{gettext("Copy")}</span>
                  </button>
                  <button
                    type="button"
                    id="share-text-post"
                    phx-hook="WebShare"
                    data-url={@share_url}
                    data-text={@share_text_post}
                    data-title={@plan.title}
                    class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-ink-panel2 hover:bg-ink text-parchment text-sm font-semibold transition"
                  >
                    <span>{gettext("Share…")}</span>
                  </button>
                </div>
              </div>
            </div>
          </div>
        </header>

        <!-- The 7-day plan -->
        <div class="grid gap-3 sm:grid-cols-2">
          <section
            :for={day <- @plan.days}
            class={[
              "rounded-xl border overflow-hidden flex flex-col",
              if(day["meals"] in [[], nil],
                do: "bg-ink-panel/40 border-ink-panel2/60",
                else: "bg-ink-panel border-ink-panel2"
              )
            ]}
          >
            <%!-- Day header strip: weekday + date, with a meal count on busy days. --%>
            <div class="flex items-baseline gap-2 px-4 py-2.5 border-b border-ink-panel2/70">
              <span class="text-sm font-display font-medium text-parchment">
                {day_weekday_label(day, @locale)}
              </span>
              <span :if={day_date_label(day, @locale)} class="text-[11px] text-parchment-dim">
                {day_date_label(day, @locale)}
              </span>
              <span
                :if={day["meals"] not in [[], nil]}
                class="ml-auto text-[10px] font-semibold text-paprika-soft bg-paprika/10 rounded-full px-2 py-0.5"
              >
                {ngettext("%{count} meal", "%{count} meals", length(day["meals"]))}
              </span>
            </div>

            <div class="p-4 flex-1">
              <div
                :if={day["meals"] in [[], nil]}
                class="h-full flex items-center text-parchment-dim/70 text-sm italic"
              >
                {gettext("No meals planned")}
              </div>

              <div :for={meal <- day["meals"] || []} class="mb-3 last:mb-0">
                <span
                  :if={meal["meal_type"]}
                  class="inline-flex items-center gap-1 text-[10px] font-semibold uppercase tracking-wide text-paprika-soft bg-paprika/10 rounded-full px-2 py-0.5 mb-1.5"
                >
                  <span aria-hidden="true">{meal_icon(meal["meal_type"])}</span>
                  {meal_label(meal["meal_type"])}
                </span>
                <ul class="space-y-1">
                  <li
                    :for={item <- meal["items"] || []}
                    class="flex items-start gap-2 text-sm text-parchment"
                  >
                    <span class="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-ink-panel2 border border-parchment-dim/40"></span>
                    <span class="leading-snug">
                      <.link
                        :if={item["kind"] == "recipe" and item["recipe_id"]}
                        navigate={~p"/browse/#{item["recipe_id"]}"}
                        class="text-basil hover:underline"
                      >
                        {item["title"]}
                      </.link>
                      <span :if={item["kind"] != "recipe" or is_nil(item["recipe_id"])}>
                        {localize_item_name(item, @ingredient_names_by_id, @ingredient_names)}
                        <span :if={item["quantity"]} class="text-parchment-dim text-xs">
                          · {format_qty(item["quantity"])} {localize_unit(item, @unit_names)}
                        </span>
                      </span>
                    </span>
                  </li>
                </ul>
              </div>
            </div>
          </section>
        </div>

        <!-- Weekly grocery list, grouped into shopping aisles -->
        <section
          :if={grocery_groups(@plan) != []}
          class="mt-6 bg-ink-panel border border-ink-panel2 rounded-2xl p-5"
        >
          <div class="flex items-center justify-between gap-3 mb-4">
            <h2 class="text-lg font-display font-medium text-parchment">
              {gettext("Weekly grocery list")}
            </h2>
            <span class="shrink-0 text-[11px] font-semibold px-2.5 py-1 rounded-full bg-paprika/15 text-paprika-soft">
              {ngettext("%{count} item", "%{count} items", grocery_total(@plan))}
            </span>
          </div>

          <%!-- Auto-fit grid: aisle cards grow to fill the available width (a
                lone aisle spans the whole row rather than sitting in a narrow
                1/3 column). Inside each card the items flow into as many
                `column-width`-sized columns as the card is wide, so a long list
                is never forced into a single tall column when there is room. --%>
          <div class="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(15rem,1fr))]">
            <div
              :for={group <- grocery_groups(@plan)}
              class="bg-ink-panel2 rounded-xl p-4 border border-ink-panel2"
            >
              <div class="flex items-center gap-2 mb-3">
                <span class="text-base leading-none" aria-hidden="true">
                  {aisle_icon(group["aisle"])}
                </span>
                <h3 class="text-sm font-semibold text-parchment">{aisle_label(group["aisle"])}</h3>
                <span class="ml-auto text-[11px] text-parchment-dim [font-variant-numeric:tabular-nums]">
                  {length(group["items"])}
                </span>
              </div>
              <ul class="[column-width:11rem] gap-x-4">
                <li
                  :for={item <- group["items"]}
                  class="flex items-start gap-2 text-sm text-parchment mb-1.5 break-inside-avoid"
                >
                  <span class="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-[2px] border border-parchment-dim/60"></span>
                  <span class="leading-snug">
                    {localize_grocery_item(item, @ingredient_names_by_id, @ingredient_names)}
                  </span>
                </li>
              </ul>
            </div>
          </div>
        </section>

        <!-- Comments — the plan's social thread. Likes + comments live here (on
              the feed post), never on the private calendar view. -->
        <section :if={@post} class="mt-6 bg-ink-panel border border-ink-panel2 rounded-2xl p-5">
          <h2 class="text-lg font-display font-medium text-parchment mb-4">
            {ngettext("%{count} comment", "%{count} comments", length(@comments))}
          </h2>

          <.form
            :if={@current_user}
            for={%{}}
            as={:comment}
            phx-submit="add_comment"
            class="flex items-start gap-3 mb-6"
          >
            <textarea
              name="comment[text]"
              rows="2"
              placeholder={gettext("Add a comment…")}
              class="flex-1 rounded-lg bg-ink-panel2 border border-ink-panel2 text-parchment text-sm px-3 py-2 placeholder:text-parchment-dim focus:outline-none focus:border-paprika-soft"
            ><%= @comment_text %></textarea>
            <button
              type="submit"
              class="shrink-0 px-4 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink text-sm font-bold transition"
            >
              {gettext("Post")}
            </button>
          </.form>

          <p :if={!@current_user} class="text-sm text-parchment-dim mb-6">
            <.link navigate={~p"/users/log_in"} class="text-paprika-soft hover:underline">
              {gettext("Log in")}
            </.link>
            {gettext("to join the conversation.")}
          </p>

          <div :if={@comments == []} class="text-sm text-parchment-dim italic">
            {gettext("No comments yet — be the first to share your thoughts.")}
          </div>

          <ul class="space-y-4">
            <li :for={comment <- @comments} class="flex gap-3">
              <div class="w-9 h-9 rounded-full bg-ink-panel2 flex items-center justify-center shrink-0 text-sm font-semibold text-parchment-dim">
                {comment_initial(comment)}
              </div>
              <div class="min-w-0">
                <p class="text-sm">
                  <span class="font-semibold text-parchment">{comment_author(comment)}</span>
                </p>
                <p class="text-sm text-parchment-dim whitespace-pre-wrap break-words">
                  {comment.text}
                </p>
              </div>
            </li>
          </ul>
        </section>

        <!-- Referral footer: every shared plan links back to the site. -->
        <div class="mt-10 pt-6 border-t border-ink-panel2 text-center">
          <.link
            navigate={~p"/"}
            class="inline-flex items-center gap-1.5 text-sm text-parchment-dim hover:text-parchment transition"
          >
            {gettext("Made with")}
            <span class="font-display font-medium text-parchment">
              m3<span class="text-paprika-soft">hungry</span>.com
            </span>
          </.link>
          <p class="text-xs text-parchment-dim mt-1">
            {gettext("Build and share your own weekly meal plans, free — with USDA nutrition.")}
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp macro_tile(assigns) do
    ~H"""
    <div class="bg-ink-panel2 rounded-lg px-3 py-2">
      <dt class="text-[11px] text-parchment-dim uppercase tracking-wide">{@label}</dt>
      <dd class="text-parchment font-semibold [font-variant-numeric:tabular-nums]">{@value}</dd>
    </div>
    """
  end

  defp author_name(%{user: %{name: name}}) when is_binary(name) and name != "", do: name
  defp author_name(_), do: nil

  defp comment_author(%{user: %{name: name}}) when is_binary(name) and name != "", do: name
  defp comment_author(_), do: "Anonymous"

  defp comment_initial(comment) do
    comment |> comment_author() |> String.first() |> to_string() |> String.upcase()
  end

  defp macro(plan, key) do
    case plan.macros[key] do
      n when is_float(n) -> n |> Float.round(1) |> trim_float()
      n when is_integer(n) -> n
      _ -> 0
    end
  end

  defp trim_float(f) do
    if f == Float.round(f), do: round(f), else: f
  end

  defp format_qty(q) when is_float(q), do: trim_float(q)
  defp format_qty(q), do: q

  # Grouped grocery list (aisle buckets). Falls back to the flat `grocery` list
  # for plans published before `grocery_groups` existed, rendering it as a single
  # "Other" group so older shared links keep working. Flat-list items are wrapped
  # in the current item map (no id) so the renderer sees one shape.
  defp grocery_groups(%{grocery_groups: [_ | _] = groups}), do: groups

  defp grocery_groups(%{grocery: [_ | _] = flat}) do
    items = Enum.map(flat, fn name -> %{"ingredient_id" => nil, "name" => name} end)
    [%{"aisle" => "other", "label" => "All items", "items" => items}]
  end

  defp grocery_groups(_plan), do: []

  # `{ingredient_id, name}` for a grocery item, tolerating both the current map
  # shape and the legacy plain-string shape (pre-id rows).
  defp grocery_item(%{"name" => name} = item), do: {item["ingredient_id"], name}
  defp grocery_item(name) when is_binary(name), do: {nil, name}

  defp grocery_total(plan) do
    plan |> grocery_groups() |> Enum.reduce(0, fn g, acc -> acc + length(g["items"]) end)
  end

  # Merge a per-code translation map across a locale's codes, with the canonical
  # (first/ISO) code winning on conflict — mirrors `History.merge_by_codes/2`.
  defp merge_by_codes(codes, fun) do
    codes
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn code, acc -> Map.merge(acc, fun.(code)) end)
  end

  # Every ingredient name shown on the page (grocery items + ingredient meals) —
  # the candidate set for the name-based translation fallback (free foods and
  # legacy rows that carry no id).
  defp page_ingredient_names(plan) do
    grocery =
      for group <- grocery_groups(plan), item <- group["items"], do: elem(grocery_item(item), 1)

    day_ingredients =
      for day <- plan.days,
          meal <- day["meals"] || [],
          item <- meal["items"] || [],
          item["kind"] != "recipe",
          is_binary(item["title"]),
          do: item["title"]

    (grocery ++ day_ingredients) |> Enum.uniq()
  end

  # The ingredient_id links carried by ingredient meals **and** grocery items —
  # the reliable key for localizing their names regardless of how the base name
  # was stored.
  defp page_ingredient_ids(plan) do
    day_ids =
      for day <- plan.days,
          meal <- day["meals"] || [],
          item <- meal["items"] || [],
          item["kind"] == "ingredient",
          id = item["ingredient_id"],
          not is_nil(id),
          do: id

    grocery_ids =
      for group <- grocery_groups(plan),
          item <- group["items"],
          id = elem(grocery_item(item), 0),
          not is_nil(id),
          do: id

    (day_ids ++ grocery_ids) |> Enum.uniq()
  end

  # The measurement_unit_id links carried by ingredient meals, for unit labels.
  defp page_unit_ids(plan) do
    for day <- plan.days,
        meal <- day["meals"] || [],
        item <- meal["items"] || [],
        id = item["measurement_unit_id"],
        not is_nil(id),
        uniq: true,
        do: id
  end

  # Localize a grocery item by its ingredient_id link (preferred — robust against
  # name drift), falling back to a name-based translation, then the stored base
  # name. Mirrors `localize_item_name/3` for the per-day ingredient meals so the
  # grocery list and the day items localize through the same id path.
  defp localize_grocery_item(item, by_id, by_name) do
    {id, name} = grocery_item(item)

    cond do
      not is_nil(id) and is_map_key(by_id, id) -> by_id[id]
      true -> Map.get(by_name, name, name)
    end
  end

  # Localize an ingredient meal's name by its ingredient_id link (preferred),
  # falling back to a name-based translation, then the stored base name — so
  # plans published before FK links existed still localize where names match.
  defp localize_item_name(item, by_id, by_name) do
    case item["ingredient_id"] do
      id when not is_nil(id) and is_map_key(by_id, id) -> by_id[id]
      _ -> Map.get(by_name, item["title"], item["title"])
    end
  end

  # Localize a unit by its measurement_unit_id link, falling back to the stored
  # English label.
  defp localize_unit(item, unit_names) do
    case item["measurement_unit_id"] do
      id when not is_nil(id) -> Map.get(unit_names, id, item["unit"])
      _ -> item["unit"]
    end
  end

  # Localized weekday name from the day's stored ISO date (so EL shows "Δευτέρα"
  # rather than the English label baked into the snapshot). Falls back to the
  # stored label, then a day index.
  defp day_weekday_label(%{"date" => iso} = day, locale) when is_binary(iso) do
    case Date.from_iso8601(iso) do
      {:ok, d} -> Locale.day_name(d, locale)
      _ -> day["label"] || default_day_label(day)
    end
  end

  defp day_weekday_label(day, _locale), do: day["label"] || default_day_label(day)

  defp default_day_label(day), do: gettext("Day %{n}", n: (day["index"] || 0) + 1)

  # Localized short date ("5 Οκτ" / "5 Oct") from the stored ISO date.
  defp day_date_label(%{"date" => iso}, locale) when is_binary(iso) do
    case Date.from_iso8601(iso) do
      {:ok, d} -> "#{d.day} #{Locale.month_short(d, locale)}"
      _ -> nil
    end
  end

  defp day_date_label(_, _locale), do: nil

  defp meal_label("breakfast"), do: gettext("Breakfast")
  defp meal_label("morning_snack"), do: gettext("Morning Snack")
  defp meal_label("lunch"), do: gettext("Lunch")
  defp meal_label("afternoon_snack"), do: gettext("Afternoon Snack")
  defp meal_label("dinner"), do: gettext("Dinner")
  defp meal_label(other), do: MealType.label(other)

  defp aisle_label("produce"), do: gettext("Produce")
  defp aisle_label("meat_seafood"), do: gettext("Meat & Seafood")
  defp aisle_label("dairy_eggs"), do: gettext("Dairy & Eggs")
  defp aisle_label("bakery_grains"), do: gettext("Bakery & Grains")
  defp aisle_label("pantry"), do: gettext("Pantry")
  defp aisle_label("spices"), do: gettext("Spices & Seasonings")
  defp aisle_label("beverages"), do: gettext("Beverages")
  defp aisle_label(_), do: gettext("Other")

  defp meal_icon("breakfast"), do: "🍳"
  defp meal_icon("morning_snack"), do: "🍎"
  defp meal_icon("lunch"), do: "🥗"
  defp meal_icon("afternoon_snack"), do: "🍪"
  defp meal_icon("dinner"), do: "🍽️"
  defp meal_icon(_), do: "🍴"

  defp aisle_icon("produce"), do: "🥬"
  defp aisle_icon("meat_seafood"), do: "🥩"
  defp aisle_icon("dairy_eggs"), do: "🧀"
  defp aisle_icon("bakery_grains"), do: "🍞"
  defp aisle_icon("pantry"), do: "🫙"
  defp aisle_icon("spices"), do: "🌿"
  defp aisle_icon("beverages"), do: "🥤"
  defp aisle_icon(_), do: "🛒"

  # ── SEO ─────────────────────────────────────────────────────────────────────

  defp assign_seo(socket, plan) do
    socket
    |> assign(:page_title, plan.title)
    |> assign(:page_description, String.slice(plan.summary_text || plan.title, 0, 155))
    |> assign(:canonical_path, "/meal-plans/#{plan.slug}")
    |> assign(:og_image, plan.og_image_url)
    |> assign(:structured_data, structured_data(plan))
  end

  # BreadcrumbList (Home › Meal Plans › title) + an ItemList of the plan's
  # recipes (each pointing at its own indexable page). No fabricated ratings or
  # a non-existent "MealPlan" schema type — only truthful nodes.
  defp structured_data(plan) do
    breadcrumb = %{
      "@type" => "BreadcrumbList",
      "itemListElement" => [
        %{"@type" => "ListItem", "position" => 1, "name" => "Home", "item" => @base_url <> "/"},
        %{
          "@type" => "ListItem",
          "position" => 2,
          "name" => "Meal Plans",
          "item" => @base_url <> "/meal-plans"
        },
        %{"@type" => "ListItem", "position" => 3, "name" => plan.title}
      ]
    }

    recipe_items =
      plan.days
      |> Enum.flat_map(fn day ->
        for meal <- day["meals"] || [],
            item <- meal["items"] || [],
            item["kind"] == "recipe",
            do: item
      end)
      |> Enum.uniq_by(& &1["recipe_id"])
      |> Enum.reject(&is_nil(&1["recipe_id"]))
      |> Enum.with_index(1)
      |> Enum.map(fn {item, pos} ->
        %{
          "@type" => "ListItem",
          "position" => pos,
          "url" => @base_url <> "/browse/" <> to_string(item["recipe_id"]),
          "name" => item["title"]
        }
      end)

    item_list = %{
      "@type" => "ItemList",
      "name" => plan.title,
      "numberOfItems" => length(recipe_items),
      "itemListElement" => recipe_items
    }

    if recipe_items == [], do: [breadcrumb], else: [breadcrumb, item_list]
  end
end
