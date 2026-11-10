defmodule MehungryWeb.ProfileLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Presence, :user_tracking

  use MehungryWeb.LiveHelpers, :hook_for_update_recipe_details_component

  alias MehungryWeb.RecipeComponents

  alias Mehungry.Accounts
  alias Mehungry.Users
  alias Mehungry.PublishedPlans
  alias MehungryWeb.ProfileLive.Show
  alias Mehungry.Food
  alias Mehungry.Posts
  alias Mehungry.Professionals
  alias Mehungry.Professionals.ProfessionalProfile
  alias Mehungry.History
  alias Mehungry.Progress
  alias Mehungry.Progress.Period
  alias MehungryWeb.MeasurementChart
  alias MehungryWeb.ProgressOverlayChart

  @impl true
  def mount(_params, session, socket) do
    current_user =
      case is_nil(session["user_token"]) do
        true ->
          nil

        false ->
          Accounts.get_user_by_session_token(session["user_token"])
      end

    {current_user_profile, current_user_follows, current_user_recipes} =
      Accounts.get_user_essentials(current_user)

    current_user_follows = Enum.map(current_user_follows, fn x -> x.follow_id end)

    {:ok,
     assign(socket, :content_state, :created)
     |> assign(:recipe, nil)
     |> assign(:user_recipes, [])
     |> assign(:user_ingredients, [])
     |> assign(:user_meal_plans, [])
     |> assign(:nutritionist_assignment, nil)
     |> assign(:progress_cards, [])
     |> assign(:series_specs, [])
     # nil (not an empty MapSet) = "no explicit choice yet" — sanitize_selection
     # then defaults the first chart to the first body series.
     |> assign(:selected_series, nil)
     |> assign(:overlay_chart_svg, nil)
     |> assign(:overlay_legend, [])
     |> assign(:progress_periods, [])
     |> assign(:active_period, nil)
     |> assign(:viewing_period, nil)
     |> assign(:period_entries, [])
     |> assign(:photo_markers, [])
     |> assign(:photo_axis, nil)
     |> assign(:comparison, nil)
     |> assign(:show_period_settings, false)
     |> assign(:entry_form_version, 0)
     |> assign(:entry_draft, %{})
     |> assign(:lightbox_photo, nil)
     |> assign(:current_user, current_user)
     |> assign(:user, nil)
     |> assign(:must_be_loged_in, nil)
     |> assign(:current_user_profile, current_user_profile)
     |> assign(:current_user_follows, current_user_follows)
     |> assign(:current_user_recipes, current_user_recipes)
     |> allow_upload(:progress_photo,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 4,
       max_file_size: 5_000_000,
       auto_upload: true,
       external: &presign_progress_photo/2
     )}
  end

  # Body photos are sensitive — they upload straight to the private bucket and
  # are only read back through the signed URLs Mehungry.Progress serves.
  defp presign_progress_photo(entry, socket) do
    key = MehungryWeb.Uploads.key_for("progress_photos", entry)
    {:ok, MehungryWeb.Uploads.meta(entry, key, 5_000_000, bucket: :private), socket}
  end

  # The lightbox assign: a resolved (signed) display URL + the photo's
  # share-link state, driving the share/unshare controls.
  defp lightbox(photo, date) do
    %{
      id: photo.id,
      url: Progress.photo_url(photo),
      date: date,
      shared: is_binary(photo.share_token),
      share_url: photo.share_token && url(~p"/shared/photos/#{photo.share_token}")
    }
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = assign(socket, :path, uri)
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @profile_tabs ~w(created saved meal_plans progress ingredients edit_profile connected_accounts)

  defp content_state_from_tab(tab, live_action) when tab in @profile_tabs do
    case {tab, live_action} do
      {tab, :show}
      when tab in [
             "edit_profile",
             "connected_accounts",
             "ingredients",
             "meal_plans",
             "progress"
           ] ->
        :created

      {tab, _live_action} ->
        String.to_existing_atom(tab)
    end
  end

  defp content_state_from_tab(_tab, _live_action), do: :created

  defp apply_action(socket, :index, params) do
    if is_nil(socket.assigns[:current_user]) do
      push_navigate(socket, to: "/users/log_in")
    else
      content_state = content_state_from_tab(params["tab"], :index)

      do_apply_action_index(socket, content_state)
      |> assign(:content_state, content_state)
    end
  end

  defp apply_action(socket, :show, %{"id" => id} = params) do
    maybe_track_user(%{}, socket)

    user = Accounts.get_user!(id)

    case public_professional_for(user.id) do
      %ProfessionalProfile{slug: slug} when is_binary(slug) ->
        # Nutritionists have a canonical public page. The RedirectProProfile plug
        # 301s direct hits/crawlers; this covers in-app client-side navigation.
        push_navigate(socket, to: ~p"/nutritionists/#{slug}")

      _ ->
        show_regular_profile(socket, user, params)
    end
  end

  defp apply_action(socket, :show_recipe, %{"recipe_id" => id}) do
    maybe_track_user(%{}, socket)

    recipe = Food.get_recipe!(id)

    if !is_nil(recipe) do
      Posts.subscribe_to_recipe(%{recipe_id: id})

      cancel_path =
        if not is_nil(socket.assigns.user) and not is_nil(socket.assigns.current_user) do
          ~p"/profile/#{socket.assigns.user.id}?#{[tab: to_string(socket.assigns.content_state)]}"
        else
          ~p"/profile?#{[tab: to_string(socket.assigns.content_state)]}"
        end

      # `current_user_{profile,follows,recipes}` are already assigned for this
      # lifecycle in mount/3, so we reuse them instead of re-running
      # get_user_essentials/1. This also fixes a latent bug: the old reload
      # re-assigned the **raw %Follow{} structs** to `current_user_follows`, but
      # the shared follow hook (LiveHelpers.toggle_user_follow / save_user_follow)
      # compares that list against integer follow-ids — mount maps it to ids, so
      # re-assigning raw structs here silently broke the recipe modal's follow
      # button. Reusing mount's id list keeps it correct.
      socket
      |> assign(:nutrients, recipe.nutrients)
      |> assign(:primary_size, recipe.primary_nutrients_size)
      |> assign(:page_title, recipe.title <> " from " <> recipe.user.email)
      |> assign(:recipe, recipe)
      |> assign(:cancel_path, cancel_path)
    else
      socket |> put_flash(:error, "Recipe not found") |> push_navigate(to: "/home")
    end
  end

  defp apply_action(socket, :edit, _params) do
    if is_nil(socket.assigns[:current_user]) do
      push_navigate(socket, to: "/users/log_in")
    else
      do_apply_action_edit(socket)
    end
  end

  defp show_regular_profile(socket, user, params) do
    categories = Food.list_categories()
    category_ids = Enum.map(categories, fn x -> x.id end)
    food_restrictions = Food.list_food_restriction_types()
    food_restriction_ids = Enum.map(food_restrictions, fn x -> x.id end)

    # Logged-out visitors have no current_user_profile; fall back to a blank one
    # so viewing another user's profile (e.g. a public nutritionist) doesn't crash.
    changeset =
      Accounts.change_user_profile(
        socket.assigns.current_user_profile || %Mehungry.Accounts.UserProfile{},
        %{}
      )

    socket =
      socket
      |> assign(:categories, categories)
      |> assign(:category_ids, category_ids)
      |> assign(:food_restriction_ids, food_restriction_ids)
      |> assign(:food_restrictions, food_restrictions)
      |> assign(:id, "form-#{System.unique_integer()}")
      |> assign(:form, to_form(changeset))

    {user_saved_recipes, user_created_recipes, user_profile} =
      case is_nil(user) do
        true ->
          {[], [], []}

        false ->
          {Users.list_user_saved_recipes(user), Users.list_user_created_recipes(user),
           Accounts.get_user_profile_by_user_id(user.id)}
      end

    user_recipes = Enum.map(user_saved_recipes, fn x -> x.recipe_id end)

    socket
    |> assign(:page_title, "Profile")
    |> assign(:user, user)
    |> assign(:page_title, "Profile " <> user.email)
    |> assign(:user_created_recipes, user_created_recipes)
    |> assign(:user_saved_recipes, user_saved_recipes)
    |> assign(:user_profile, user_profile)
    |> assign(:user_recipes, user_recipes)
    # Both lists are fully loaded for a public profile, so count from them.
    |> assign(:created_count, length(user_created_recipes))
    |> assign(:saved_count, length(user_saved_recipes))
    |> assign(:meal_plans_count, 0)
    |> assign(:content_state, content_state_from_tab(params["tab"], :show))
  end

  defp do_apply_action_edit(socket) do
    maybe_track_user(%{}, socket)
    categories = Food.list_categories()
    category_ids = Enum.map(categories, fn x -> x.id end)
    food_restrictions = Food.list_food_restriction_types()
    food_restriction_ids = Enum.map(food_restrictions, fn x -> x.id end)
    user_profile = Accounts.get_user_profile_by_user_id(socket.assigns.current_user.id)

    #    user_profile = socket.assigns.user_profile
    changeset = Accounts.change_user_profile(user_profile, %{})

    socket
    |> assign(:page_title, "Edit Profile Details")
    |> assign(:categories, categories)
    |> assign(:current_user_profile, user_profile)
    |> assign(:user_profile, user_profile)
    |> assign(:category_ids, category_ids)
    |> assign(:food_restriction_ids, food_restriction_ids)
    |> assign(:food_restrictions, food_restrictions)
    |> assign(:form, to_form(changeset))
    |> assign(:id, "form-#{System.unique_integer()}")
  end

  defp do_apply_action_index(socket, content_state) do
    categories = Food.list_categories()
    category_ids = Enum.map(categories, fn x -> x.id end)
    food_restrictions = Food.list_food_restriction_types()
    food_restriction_ids = Enum.map(food_restrictions, fn x -> x.id end)

    changeset = Accounts.change_user_profile(socket.assigns.current_user_profile, %{})
    maybe_track_user(%{}, socket)

    socket =
      socket
      |> assign(:page_title, "Edit Profile Details")
      |> assign(:categories, categories)
      |> assign(:category_ids, category_ids)
      |> assign(:food_restriction_ids, food_restriction_ids)
      |> assign(:food_restrictions, food_restrictions)
      |> assign(:form, to_form(changeset))
      |> assign(:id, "form-#{System.unique_integer()}")

    current_user = socket.assigns.current_user

    # Only the active tab's recipe list is rendered, so load just that one. The
    # other assign stays [] and is filled in when the user switches tabs.
    {user_saved_recipes, user_created_recipes} =
      case {content_state, is_nil(current_user)} do
        {_content_state, true} -> {[], []}
        {:created, false} -> {[], load_created_recipes(current_user)}
        {:saved, false} -> {load_saved_recipes(current_user), []}
        {_content_state, false} -> {[], []}
      end

    # The user's ingredients are only rendered by the "ingredients" tab — skip
    # the query entirely on the other tabs. mount/3 seeds it to [], so it stays
    # empty here when another tab is active.
    user_ingredients =
      case content_state do
        :ingredients -> Food.list_user_ingredients(socket.assigns.current_user)
        _ -> []
      end

    user_meal_plans =
      case {content_state, is_nil(current_user)} do
        {:meal_plans, false} ->
          PublishedPlans.list_plans_for_user(current_user.id)

        _ ->
          []
      end

    # Only the Connections panel renders the nutritionist card, so fetch the
    # client's assignment just for that tab (nil elsewhere).
    nutritionist_assignment =
      case {content_state, is_nil(current_user)} do
        {:connected_accounts, false} ->
          Professionals.get_assignment_for_client(current_user.id)

        _ ->
          nil
      end

    # Tab badges must show real totals even for tabs whose lists aren't loaded
    # (only the active tab's list is fetched above). Cheap COUNT queries, always.
    socket
    |> assign(:page_title, gettext("Profile"))
    |> assign(:user_created_recipes, user_created_recipes)
    |> assign(:user_saved_recipes, user_saved_recipes)
    |> assign(:user_ingredients, user_ingredients)
    |> assign(:user_meal_plans, user_meal_plans)
    |> assign(:nutritionist_assignment, nutritionist_assignment)
    |> assign(:created_count, Food.count_user_created_recipes(current_user.id) || 0)
    |> assign(:saved_count, Accounts.count_user_saved_recipes(current_user.id) || 0)
    |> assign(:meal_plans_count, PublishedPlans.count_plans_for_user(current_user.id))
    |> maybe_load_progress(content_state)
  end

  # ── Progress journal (owner-only tab) ────────────────────────────────────────
  #
  # The user's own period-based progress journal (Mehungry.Progress). Loaded
  # only for the Progress tab, keyed strictly on current_user.id. The first
  # visit bootstraps the journal (ensure_journal/1 opens a self period — or a
  # nutritionist-aligned one when the user already has a nutritionist).
  defp maybe_load_progress(socket, :progress) do
    user = socket.assigns.current_user
    {:ok, active} = Progress.ensure_journal(user.id)

    socket
    |> assign(:progress_periods, Progress.list_periods(user.id))
    |> assign(:active_period, active)
    |> assign_progress_view(active)
  end

  defp maybe_load_progress(socket, _content_state), do: socket

  # Point the whole progress tab (diary, chart, photos, comparison) at one
  # period — the active one by default, or a past period from the history list.
  defp assign_progress_view(socket, nil) do
    socket
    |> assign(:viewing_period, nil)
    |> assign(:period_entries, [])
    |> assign(:photo_markers, [])
    |> assign(:photo_axis, nil)
    |> assign(:comparison, nil)
    |> assign(:progress_cards, [])
    |> assign(:series_specs, [])
    |> assign(:selected_series, nil)
    |> assign(:overlay_chart_svg, nil)
    |> assign(:overlay_legend, [])
  end

  defp assign_progress_view(socket, %Period{} = period) do
    user = socket.assigns.current_user
    history = Progress.measurement_history_for_period(period)
    nutrition = load_nutrition_history(user.id, period, history)
    specs = ProgressOverlayChart.series_specs(history, nutrition)
    selected = ProgressOverlayChart.sanitize_selection(socket.assigns[:selected_series], specs)
    bounds = period_axis_bounds(period)

    socket
    |> assign(:viewing_period, period)
    # Diary reads newest-first; the chart gets the ascending history.
    |> assign(:period_entries, user.id |> Progress.list_entries(period.id) |> Enum.reverse())
    |> assign(:photo_markers, Progress.photo_markers(period))
    |> assign(:photo_axis, ProgressOverlayChart.axis(specs, selected, bounds))
    |> assign(:comparison, Progress.comparison(period))
    |> assign(:progress_cards, MeasurementChart.cards(history))
    |> assign(:series_specs, specs)
    |> assign(:selected_series, selected)
    |> assign(:overlay_chart_svg, ProgressOverlayChart.overlay_svg(specs, selected, bounds))
    |> assign(:overlay_legend, ProgressOverlayChart.legend_entries(specs, selected))
  end

  # The date span to pull nutrition-intake series for: the viewed period's own
  # range — meals logged before the period belong to an earlier chapter and
  # must not plot on its diagram. Periods without a lower bound fall back to a
  # trailing 90-day window, which also caps the fetch cost.
  defp load_nutrition_history(user_id, %Period{} = period, _history) do
    today = Date.utc_today()
    range_end = [period.ended_on, today] |> Enum.reject(&is_nil/1) |> Enum.min(Date)
    range_start = period.started_on || Date.add(range_end, -90)

    History.daily_nutrition_history(user_id, range_start, range_end)
  end

  # The viewed period's own date range, used to widen the chart's date axis so
  # the diagram spans the whole period even where no data lands (an active
  # period always reaches today).
  defp period_axis_bounds(%Period{} = period) do
    {period.started_on, period.ended_on || Date.utc_today()}
  end

  # A pro user has a canonical public page; used by apply_action(:show) to
  # redirect /profile/:id → /nutritionists/:slug (see RedirectProProfile plug).
  defp public_professional_for(user_id) do
    case Professionals.get_professional_profile(user_id) do
      %ProfessionalProfile{is_public: true} = profile -> profile
      _ -> nil
    end
  end

  defp load_created_recipes(user) do
    Users.list_user_created_recipes(user)
  end

  defp load_saved_recipes(user) do
    Users.list_user_saved_recipes(user)
  end

  @impl true
  def handle_info({MehungryWeb.Onboarding.FormComponent, "profile-saved"}, socket) do
    current_user_profile =
      Accounts.get_user_profile_by_user_id(socket.assigns.current_user.id)

    {:noreply,
     socket
     |> assign(:current_user_profile, current_user_profile)}
  end

  def handle_info(
        {MehungryWeb.ProfileLive.Form, {:saved, %Mehungry.Accounts.UserProfile{} = profile}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:current_user_profile, profile)
     |> put_flash(:info, "Upadated successfully")}
  end

  def handle_info({MehungryWeb.ProfileLive.Form, {:error, message}}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  def get_active(state, param) do
    if state == param do
      " bg-ink-panel text-paprika border-b-2 border-paprika "
    else
      " text-parchment-dim hover:text-parchment hover:bg-ink-panel/50"
    end
  end

  def tab_path(%{live_action: :show, user: user}, tab), do: ~p"/profile/#{user.id}?#{[tab: tab]}"
  def tab_path(%{live_action: :index}, tab), do: ~p"/profile?#{[tab: tab]}"

  # Heading for a "manage account" panel shown in place of the content tab bar.
  def panel_title(:edit_profile), do: "Edit profile"
  def panel_title(:connected_accounts), do: "Connections"
  def panel_title(:ingredients), do: "My ingredients"
  def panel_title(_), do: "Your recipes"

  # A compact daily-average macro line for a published plan card, e.g.
  # "1800 kcal · 90 g protein". nil (chip hidden) when the snapshot has no energy.
  defp macro_label(macros) when is_map(macros) do
    kcal = macros["energy_kcal"] || 0
    protein = round(macros["protein_g"] || 0)

    if kcal > 0, do: "#{round(kcal)} kcal · #{protein} g protein", else: nil
  end

  defp macro_label(_), do: nil

  defp plural(1, word), do: word
  defp plural(_, word), do: word <> "s"

  def handle_event("toggle_series", %{"series" => key}, socket) do
    specs = socket.assigns.series_specs

    # phx-value is user-controlled — only toggle keys that exist as specs.
    if Enum.any?(specs, &(&1.key == key)) do
      sel = socket.assigns.selected_series

      sel =
        if MapSet.member?(sel, key), do: MapSet.delete(sel, key), else: MapSet.put(sel, key)

      bounds = period_axis_bounds(socket.assigns.viewing_period)

      {:noreply,
       socket
       |> assign(:selected_series, sel)
       |> assign(:photo_axis, ProgressOverlayChart.axis(specs, sel, bounds))
       |> assign(:overlay_chart_svg, ProgressOverlayChart.overlay_svg(specs, sel, bounds))
       |> assign(:overlay_legend, ProgressOverlayChart.legend_entries(specs, sel))}
    else
      {:noreply, socket}
    end
  end

  # ── Progress journal events ─────────────────────────────────────────────────

  def handle_event("select_period", %{"id" => id}, socket) do
    case Progress.get_period(socket.assigns.current_user.id, id) do
      nil -> {:noreply, socket}
      period -> {:noreply, assign_progress_view(socket, period)}
    end
  end

  def handle_event("validate_entry", params, socket) do
    # Uploads are auto_upload/external, so picking a photo re-renders the form
    # mid-edit — the draft keeps the typed values on screen through those
    # patches (unbound inputs would reset to blank and the entry would save
    # empty next to its photo).
    {:noreply, assign(socket, :entry_draft, Map.get(params, "entry", socket.assigns.entry_draft))}
  end

  def handle_event("log_entry", %{"entry" => entry_params}, socket) do
    user = socket.assigns.current_user
    period = socket.assigns.viewing_period

    case Progress.log_entry(user.id, period.id, entry_params) do
      {:ok, entry} ->
        consume_uploaded_entries(socket, :progress_photo, fn meta, _entry ->
          # Private-bucket object: persist only the storage key — reads are
          # signed at read time (Progress.photo_url/1); there is no public URL.
          Progress.attach_photo(user.id, entry.id, %{"storage_key" => meta[:key]})

          {:ok, meta[:key]}
        end)

        {:noreply,
         socket
         |> update(:entry_form_version, &(&1 + 1))
         |> assign(:entry_draft, %{})
         |> refresh_journal()
         |> put_flash(:info, gettext("Entry saved."))}

      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         put_flash(socket, :error, gettext("Could not save that entry — check the values."))}

      {:error, :not_self_period} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Your nutritionist tracks this period — logging is paused.")
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save that entry."))}
    end
  end

  def handle_event("delete_entry", %{"id" => id}, socket) do
    case Progress.delete_entry(socket.assigns.current_user.id, id) do
      {:ok, _} ->
        {:noreply, socket |> refresh_journal() |> put_flash(:info, gettext("Entry deleted."))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_photo", %{"id" => id}, socket) do
    case Progress.delete_photo(socket.assigns.current_user.id, id) do
      {:ok, _} ->
        {:noreply, socket |> refresh_journal() |> put_flash(:info, gettext("Photo deleted."))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_photo_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :progress_photo, ref)}
  end

  def handle_event("save_period_settings", %{"period" => period_params}, socket) do
    user = socket.assigns.current_user
    period = socket.assigns.viewing_period
    # Unchecked checkbox groups submit nothing — default to "track weight".
    period_params = Map.put_new(period_params, "tracked_metrics", ["weight_kg"])

    case Progress.configure_period(user.id, period.id, period_params) do
      {:ok, _period} ->
        {:noreply,
         socket
         |> assign(:show_period_settings, false)
         |> refresh_journal()
         |> put_flash(:info, gettext("Goals saved."))}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save — check the values."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save those settings."))}
    end
  end

  def handle_event("toggle_period_settings", _params, socket) do
    {:noreply, update(socket, :show_period_settings, &(!&1))}
  end

  def handle_event("reset_period", _params, socket) do
    case Progress.reset_period(socket.assigns.current_user.id) do
      {:ok, %{opened: opened}} ->
        {:noreply,
         socket
         |> assign(:selected_series, nil)
         |> refresh_journal(opened)
         |> put_flash(
           :info,
           gettext("Fresh start! Your previous progress is saved under past periods.")
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not reset right now."))}
    end
  end

  def handle_event("toggle_share", _params, socket) do
    user = socket.assigns.current_user
    period = socket.assigns.viewing_period

    result =
      if period.shared_with_nutritionist,
        do: Progress.unshare_period(user.id, period.id),
        else: Progress.share_period(user.id, period.id)

    case result do
      {:ok, updated} ->
        flash =
          if updated.shared_with_nutritionist,
            do: gettext("This period is now visible to your nutritionist."),
            else: gettext("This period is no longer shared.")

        {:noreply, socket |> refresh_journal(updated) |> put_flash(:info, flash)}

      {:error, :no_nutritionist} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have a nutritionist to share with yet."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update sharing."))}
    end
  end

  def handle_event("open_photo", %{"id" => id} = params, socket) do
    case Progress.get_photo(socket.assigns.current_user.id, id) do
      nil -> {:noreply, socket}
      photo -> {:noreply, assign(socket, :lightbox_photo, lightbox(photo, params["date"]))}
    end
  end

  def handle_event("close_photo", _params, socket) do
    {:noreply, assign(socket, :lightbox_photo, nil)}
  end

  def handle_event("share_photo_link", %{"id" => id}, socket) do
    case Progress.share_photo(socket.assigns.current_user.id, id) do
      {:ok, photo} ->
        {:noreply,
         socket
         |> assign(:lightbox_photo, lightbox(photo, socket.assigns.lightbox_photo[:date]))
         |> put_flash(
           :info,
           gettext("Share link created — anyone with the link can view this photo.")
         )}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not create the share link."))}
    end
  end

  def handle_event("unshare_photo_link", %{"id" => id}, socket) do
    case Progress.unshare_photo(socket.assigns.current_user.id, id) do
      {:ok, photo} ->
        {:noreply,
         socket
         |> assign(:lightbox_photo, lightbox(photo, socket.assigns.lightbox_photo[:date]))
         |> put_flash(:info, gettext("Share link revoked."))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not revoke the share link."))}
    end
  end

  def handle_event("delete_my_ingredient", %{"id" => id}, socket) do
    # Re-fetch through the owner-scoped getter so a forged id can't delete
    # someone else's ingredient.
    ingredient = Food.get_user_ingredient!(socket.assigns.current_user, id)
    {:ok, _} = Food.delete_ingredient(ingredient)

    {:noreply,
     socket
     |> assign(:user_ingredients, Food.list_user_ingredients(socket.assigns.current_user))
     |> put_flash(:info, "Ingredient deleted")}
  end

  # Owner-only: re-queue AI cover-image generation (force overwrite) for every
  # recipe the owner has created. Gated on the owner email so no other user can
  # trigger a costly image-generation fan-out.
  def handle_event("regenerate_recipe_images", _params, socket) do
    user = socket.assigns.current_user

    if user && user.email == "nikolisgal@gmail.com" do
      recipes = Users.list_user_created_recipes(user)

      Enum.each(recipes, fn recipe ->
        %{recipe_id: recipe.id, force: true}
        |> Mehungry.RecipeImageWorker.new()
        |> Oban.insert()
      end)

      {:noreply,
       put_flash(
         socket,
         :info,
         "Queued image regeneration for #{length(recipes)} recipe(s)."
       )}
    else
      {:noreply, put_flash(socket, :error, "Not allowed.")}
    end
  end

  # Owner-only: re-queue AI cover-image generation for a single recipe, forcing
  # the *alternative* provider (not the configured default) so a bad cover can be
  # re-rolled on the other model. Gated on the owner email like the bulk action.
  def handle_event("regenerate_recipe_image", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    if user && user.email == "nikolisgal@gmail.com" do
      provider = Mehungry.Settings.alternate_image_provider()

      %{recipe_id: String.to_integer(id), force: true, provider: Atom.to_string(provider)}
      |> Mehungry.RecipeImageWorker.new()
      |> Oban.insert()

      {:noreply, put_flash(socket, :info, "Queued image regeneration via #{provider}.")}
    else
      {:noreply, put_flash(socket, :error, "Not allowed.")}
    end
  end

  def handle_event("edit-recipe", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> push_navigate(to: "/create_recipe/#{id}")}
  end

  def handle_event("keep_browsing", _thing, socket) do
    {:noreply, assign(socket, :must_be_loged_in, nil)}
  end

  def handle_event("delete-meal-plan", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    # Owner-scoped fetch so a forged id can't unpublish someone else's plan.
    plan = PublishedPlans.get_user_plan!(user.id, String.to_integer(id))
    {:ok, _} = PublishedPlans.delete_plan(plan)

    {:noreply,
     socket
     |> assign(:user_meal_plans, PublishedPlans.list_plans_for_user(user.id))
     |> put_flash(:info, "Meal plan removed")}
  end

  def handle_event("unsave-recipe", %{"id" => id}, socket) do
    Users.remove_user_saved_recipe(socket.assigns.current_user.id, String.to_integer(id))
    user_saved_recipes = Users.list_user_saved_recipes(socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:user_saved_recipes, user_saved_recipes)}
  end

  def handle_event("delete", %{"id" => _id}, socket) do
    # measurement_unit = food.get_measurement_unit!(id)
    # {:ok, _} = food.delete_measurement_unit(measurement_unit)

    # assign(socket, :measurement_units, list_measurement_units())}
    {:noreply, socket}
  end

  def handle_event("delete_recipe", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    # Owner-scoped delete so a forged id can't remove someone else's recipe.
    case Food.delete_user_recipe(user, id) do
      {:ok, _recipe} ->
        {:noreply,
         socket
         |> assign(:user_created_recipes, Users.list_user_created_recipes(user))
         |> assign(:created_count, Food.count_user_created_recipes(user.id) || 0)
         |> put_flash(:info, "Recipe deleted")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Recipe not found")}
    end
  end

  def handle_event("unlink_nutritionist", _params, socket) do
    case Professionals.unassign_nutritionist(socket.assigns.current_user.id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:nutritionist_assignment, nil)
         |> put_flash(:info, "Nutritionist removed.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "You don't have a nutritionist linked.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove nutritionist.")}
    end
  end

  def handle_event("disconnect_social", %{"provider" => provider}, socket) do
    user = socket.assigns.current_user
    token_key = "#{provider}_token"
    Accounts.update_user_tokens(user, %{token_key => %{}})
    updated_user = Accounts.get_user!(user.id)

    {:noreply,
     socket
     |> assign(:current_user, updated_user)
     |> put_flash(:info, "#{String.capitalize(provider)} account disconnected.")}
  end

  # Reload the journal after a mutation, keeping the currently viewed period
  # (or pointing at `period` when given — e.g. right after share/reset).
  defp refresh_journal(socket, period \\ nil) do
    user = socket.assigns.current_user
    viewing = period || socket.assigns.viewing_period

    viewing =
      (viewing && Progress.get_period(user.id, viewing.id)) || Progress.active_period(user.id)

    socket
    |> assign(:progress_periods, Progress.list_periods(user.id))
    |> assign(:active_period, Progress.active_period(user.id))
    |> assign_progress_view(viewing)
  end

  def get_profile_content(%{content_state: :created} = assigns) do
    ~H"""
    <div
      :if={@current_user && @current_user.email == "nikolisgal@gmail.com" && @live_action == :index}
      class="px-4 mb-4"
    >
      <button
        phx-click="regenerate_recipe_images"
        data-confirm="Regenerate AI cover images for ALL your created recipes? This runs in the background and overwrites existing images."
        class="px-4 py-2 rounded-full bg-paprika hover:bg-paprika-soft text-ink font-bold text-sm transition-colors"
      >
        Regenerate recipe images
      </button>
    </div>
    <div class="pb-20 w-full grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6  px-4">
      <%= for recipe <- @user_created_recipes do %>
        <RecipeComponents.recipe_card
          recipe={recipe}
          type={if @live_action == :show, do: "browse", else: "created"}
          return_to="profile"
          user_recipes={@user_recipes}
          allow_image_regen={
            @live_action == :index && @current_user && @current_user.email == "nikolisgal@gmail.com"
          }
          path_to_details={"/profile/show_recipe/#{recipe.id}"}
          id={"recipe" <> Integer.to_string(recipe.id)}
        />
      <% end %>
    </div>
    """
  end

  def get_profile_content(%{content_state: :saved} = assigns) do
    ~H"""
    <div class="pb-20 w-full grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6 px-4">
      <%= for user_recipe <- @user_saved_recipes do %>
        <RecipeComponents.recipe_card
          recipe={user_recipe.recipe}
          type={if @live_action == :show, do: "browse", else: "saved"}
          return_to="profile"
          user_recipes={@user_recipes}
          path_to_details={"/profile/show_recipe/#{user_recipe.recipe.id}"}
          id={"recipe" <> Integer.to_string(user_recipe.recipe.id)}
        />
      <% end %>
    </div>
    """
  end

  def get_profile_content(%{content_state: :meal_plans} = assigns) do
    ~H"""
    <div class="pb-20 w-full px-4">
      <div :if={@user_meal_plans == []} class="text-center text-parchment-dim py-16">
        You haven't posted any meal plans yet. Plan a week on your calendar, then
        tap "Post this week" to share it.
        <div class="mt-3">
          <.link navigate={~p"/calendar"} class="text-basil hover:underline">Go to calendar →</.link>
        </div>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div
          :for={plan <- @user_meal_plans}
          class="group relative flex flex-col bg-ink-panel border border-ink-panel2 rounded-xl overflow-hidden hover:border-basil/50 transition"
        >
          <.link navigate={~p"/meal-plans/#{plan.slug}?#{[from: "profile"]}"} class="block p-4 flex-1">
            <%!-- The shareable card graphic generated when the plan was published. --%>
            <img
              :if={plan.og_image_url}
              src={plan.og_image_url}
              alt={plan.title}
              loading="lazy"
              class="w-full rounded-lg border border-ink-panel2 mb-3"
            />
            <div class="flex items-start justify-between gap-2">
              <div class="min-w-0 flex-1">
                <div class="font-semibold text-parchment truncate group-hover:text-basil transition">
                  {plan.title}
                </div>
                <div class="text-parchment-dim text-sm mt-0.5">
                  Week of {Calendar.strftime(plan.week_start, "%b %-d, %Y")}
                </div>
              </div>
              <span class={[
                "text-[11px] px-2 py-0.5 rounded-full shrink-0",
                if(plan.visibility == "public",
                  do: "bg-basil/15 text-basil",
                  else: "bg-ink-panel2 text-parchment-dim"
                )
              ]}>
                {if plan.visibility == "public", do: "Public", else: "Private"}
              </span>
            </div>

            <div class="flex flex-wrap items-center gap-1.5 mt-3">
              <span class="text-[11px] px-2 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim">
                {plan.recipe_count} {plural(plan.recipe_count, "recipe")}
              </span>
              <span
                :if={macro_label(plan.macros)}
                class="text-[11px] px-2 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim"
              >
                {macro_label(plan.macros)}
              </span>
            </div>
          </.link>

          <button
            phx-click="delete-meal-plan"
            phx-value-id={plan.id}
            data-confirm="Remove this meal plan? This unpublishes its public page."
            class="absolute top-2 right-2 px-2 py-1 rounded-lg text-xs bg-ink/70 text-parchment-dim hover:text-paprika transition opacity-0 group-hover:opacity-100 focus:opacity-100"
          >
            Remove
          </button>
        </div>
      </div>
    </div>
    """
  end

  def get_profile_content(%{content_state: :progress} = assigns) do
    ~H"""
    <div class="pb-20 w-full max-w-3xl mx-auto px-4 space-y-4">
      <%!-- Photo lightbox --%>
      <div
        :if={@lightbox_photo}
        class="fixed inset-0 z-50 bg-ink/90 flex items-center justify-center p-4"
        phx-click="close_photo"
      >
        <figure class="max-w-lg w-full" onclick="event.stopPropagation()">
          <img src={@lightbox_photo.url} class="w-full rounded-xl" alt={gettext("progress photo")} />
          <figcaption :if={@lightbox_photo.date} class="text-center text-parchment-dim text-sm mt-2">
            {@lightbox_photo.date}
          </figcaption>
          <%!-- Opt-in public sharing: photos are private by default; the link is revocable. --%>
          <div class="mt-3 text-center">
            <div :if={!@lightbox_photo.shared}>
              <button
                type="button"
                phx-click="share_photo_link"
                phx-value-id={@lightbox_photo.id}
                class="px-3 py-1.5 rounded-lg bg-ink-panel text-parchment text-sm hover:text-basil transition"
              >
                {gettext("Create share link")}
              </button>
            </div>
            <div :if={@lightbox_photo.shared} class="space-y-2">
              <input
                type="text"
                readonly
                value={@lightbox_photo.share_url}
                onclick="event.stopPropagation(); this.select()"
                class="w-full bg-ink-panel text-parchment-dim text-xs rounded-lg px-2 py-1.5 border border-ink-panel2"
              />
              <button
                type="button"
                phx-click="unshare_photo_link"
                phx-value-id={@lightbox_photo.id}
                class="px-3 py-1.5 rounded-lg bg-ink-panel text-parchment text-sm hover:text-paprika transition"
              >
                {gettext("Stop sharing")}
              </button>
            </div>
          </div>
        </figure>
      </div>

      <%!-- Nutritionist-aligned notice: the active period is tracked for you --%>
      <div
        :if={
          @viewing_period && @viewing_period.kind == "nutritionist_aligned" &&
            is_nil(@viewing_period.ended_on)
        }
        class="bg-basil/10 border border-basil/40 rounded-xl p-4 text-sm text-parchment flex gap-3"
      >
        <.icon name="hero-information-circle" class="w-5 h-5 text-basil shrink-0 mt-0.5" />
        <div>
          {gettext(
            "Your nutritionist now tracks your progress — measurements from your visits chart here automatically, and self-logging is paused."
          )}
          <span class="text-parchment-dim">
            {gettext("Your earlier self-logged progress is saved below under past periods.")}
          </span>
        </div>
      </div>

      <%!-- Viewing a past period --%>
      <div
        :if={@viewing_period && @viewing_period.ended_on}
        class="bg-ink-panel border border-ink-panel2 rounded-xl px-4 py-3 text-sm text-parchment-dim flex items-center justify-between gap-3"
      >
        <span>
          {gettext("Viewing a past period:")}
          <span class="text-parchment font-semibold">{period_range_label(@viewing_period)}</span>
        </span>
        <button
          :if={@active_period}
          type="button"
          phx-click="select_period"
          phx-value-id={@active_period.id}
          class="text-basil hover:underline shrink-0"
        >
          {gettext("Back to current")} →
        </button>
      </div>

      <%!-- Main period card: header + comparison + dashboard + photo strip --%>
      <div :if={@viewing_period} class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
        <div class="flex items-start justify-between mb-1 gap-4 flex-wrap">
          <div>
            <h2 class="text-parchment font-display font-semibold">
              {@viewing_period.title || gettext("My progress")}
            </h2>
            <div class="flex items-center gap-2 mt-1 text-xs">
              <span class="text-parchment-dim tabular-nums">{period_range_label(@viewing_period)}</span>
              <span class={[
                "px-2 py-0.5 rounded-full",
                if(@viewing_period.kind == "self",
                  do: "bg-paprika/15 text-paprika",
                  else: "bg-basil/15 text-basil"
                )
              ]}>
                {period_kind_label(@viewing_period)}
              </span>
            </div>
          </div>

          <div class="flex items-center gap-2 shrink-0">
            <button
              type="button"
              phx-click="toggle_share"
              class={[
                "px-3 py-1.5 rounded-full text-xs font-semibold border transition",
                if(@viewing_period.shared_with_nutritionist,
                  do: "bg-basil/15 border-basil/40 text-basil",
                  else:
                    "border-ink-panel2 text-parchment-dim hover:text-parchment hover:border-parchment-dim"
                )
              ]}
            >
              <%= if @viewing_period.shared_with_nutritionist do %>
                {gettext("Shared with nutritionist")} ✓
              <% else %>
                {gettext("Share with nutritionist")}
              <% end %>
            </button>
            <button
              :if={self_logging?(@viewing_period)}
              type="button"
              phx-click="reset_period"
              data-confirm={
                gettext(
                  "Start over from 0? Your current progress stays saved as a past period, and a fresh one begins today."
                )
              }
              class="px-3 py-1.5 rounded-full text-xs font-semibold border border-ink-panel2 text-parchment-dim hover:text-paprika hover:border-paprika transition"
            >
              {gettext("Start over")}
            </button>
          </div>
        </div>

        <%!-- Goal chips for the tracked metrics --%>
        <div :if={@viewing_period.goals != %{}} class="flex gap-2 flex-wrap mt-2 mb-1">
          <span
            :for={{metric, target} <- @viewing_period.goals}
            class="text-[11px] px-2 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim tabular-nums"
          >
            {gettext("Goal")}: {MeasurementChart.metric_label(metric)} {target} {MeasurementChart.metric_unit(
              metric
            )}
          </span>
        </div>

        <div class="mt-4">
          <%= if @series_specs != [] do %>
            <div class="w-full">{@overlay_chart_svg}</div>
            <p :if={is_nil(@overlay_chart_svg)} class="text-parchment-dim text-sm">
              {gettext("Pick a metric below to chart it.")}
            </p>
            <MeasurementChart.photo_strip
              :if={@photo_axis && @overlay_chart_svg}
              markers={@photo_markers}
              min_date={elem(@photo_axis, 0)}
              max_date={elem(@photo_axis, 1)}
            />
            <ProgressOverlayChart.overlay_legend legend={@overlay_legend} />
            <span class="block text-parchment-dim text-xs mt-4 mb-2">
              {gettext(
                "Tap metrics to overlay them — each line is scaled to its own range; latest values show in the legend."
              )}
            </span>
            <ProgressOverlayChart.series_toggles
              cards={@progress_cards}
              nutrition_specs={Enum.filter(@series_specs, &(&1.kind == :nutrition))}
              selected={@selected_series}
            />
            <div class="mt-5">
              <MeasurementChart.before_now comparison={@comparison} />
            </div>
          <% else %>
            <MeasurementChart.before_now comparison={@comparison} />
            <p class="text-parchment-dim text-sm">
              <%= if self_logging?(@viewing_period) do %>
                {gettext(
                  "No measurements yet — log your first entry below. Once you've logged a metric twice, your trend charts here."
                )}
              <% else %>
                {gettext(
                  "Your nutritionist hasn't recorded measurements yet. Once you've had at least two measured visits, your progress will chart here."
                )}
              <% end %>
            </p>
          <% end %>
        </div>
      </div>

      <%!-- Goals & tracking settings (self periods only) --%>
      <div
        :if={self_logging?(@viewing_period)}
        class="bg-ink-panel border border-ink-panel2 rounded-xl p-5"
      >
        <button
          type="button"
          phx-click="toggle_period_settings"
          class="w-full flex items-center justify-between text-left"
        >
          <h3 class="text-parchment font-display font-medium">
            {gettext("Goals & tracked metrics")}
          </h3>
          <.icon
            name={if @show_period_settings, do: "hero-chevron-up", else: "hero-chevron-down"}
            class="w-4 h-4 text-parchment-dim"
          />
        </button>

        <form :if={@show_period_settings} phx-submit="save_period_settings" class="mt-4 space-y-4">
          <div>
            <span class="block text-parchment-dim text-xs uppercase tracking-wide font-semibold mb-2">
              {gettext("Metrics you want to track")}
            </span>
            <div class="grid grid-cols-2 gap-2">
              <label
                :for={metric <- Period.selectable_metrics()}
                class="flex items-center gap-2 text-sm text-parchment bg-ink-panel2 rounded-lg px-3 py-2 cursor-pointer"
              >
                <input
                  type="checkbox"
                  name="period[tracked_metrics][]"
                  value={metric}
                  checked={metric in @viewing_period.tracked_metrics}
                  class="rounded border-ink-panel2 text-paprika focus:ring-paprika bg-ink"
                />
                {MeasurementChart.metric_label(metric)}
                <span :if={MeasurementChart.metric_unit(metric)} class="text-parchment-dim text-xs">
                  ({MeasurementChart.metric_unit(metric)})
                </span>
              </label>
            </div>
            <p class="text-parchment-dim text-xs mt-2">
              {gettext(
                "BMI and BMR are worked out automatically when your height (and age) are set below."
              )}
            </p>
          </div>

          <div>
            <span class="block text-parchment-dim text-xs uppercase tracking-wide font-semibold mb-2">
              {gettext("Goals (optional)")}
            </span>
            <div class="grid grid-cols-2 gap-2">
              <label :for={metric <- Period.selectable_metrics()} class="block">
                <span class="text-parchment-dim text-xs">
                  {MeasurementChart.metric_label(metric)}
                  <span :if={MeasurementChart.metric_unit(metric)}>
                    ({MeasurementChart.metric_unit(metric)})
                  </span>
                </span>
                <input
                  type="number"
                  step="0.1"
                  min="0"
                  name={"period[goals][#{metric}]"}
                  value={@viewing_period.goals[metric]}
                  class="mt-1 w-full bg-ink-panel2 border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm focus:border-paprika focus:ring-0"
                />
              </label>
            </div>
          </div>

          <div>
            <span class="block text-parchment-dim text-xs uppercase tracking-wide font-semibold mb-2">
              {gettext("About you (used to derive BMI & BMR)")}
            </span>
            <div class="grid grid-cols-3 gap-2">
              <label class="block">
                <span class="text-parchment-dim text-xs">{gettext("Height (m)")}</span>
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  name="period[height_m]"
                  value={@viewing_period.height_m}
                  placeholder="1.75"
                  class="mt-1 w-full bg-ink-panel2 border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm focus:border-paprika focus:ring-0"
                />
              </label>
              <label class="block">
                <span class="text-parchment-dim text-xs">{gettext("Sex")}</span>
                <select
                  name="period[sex]"
                  class="mt-1 w-full bg-ink-panel2 border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm focus:border-paprika focus:ring-0"
                >
                  <option value="">{gettext("—")}</option>
                  <option value="male" selected={@viewing_period.sex == "male"}>
                    {gettext("Male")}
                  </option>
                  <option value="female" selected={@viewing_period.sex == "female"}>
                    {gettext("Female")}
                  </option>
                </select>
              </label>
              <label class="block">
                <span class="text-parchment-dim text-xs">{gettext("Age")}</span>
                <input
                  type="number"
                  step="1"
                  min="1"
                  max="129"
                  name="period[age]"
                  value={@viewing_period.age}
                  class="mt-1 w-full bg-ink-panel2 border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm focus:border-paprika focus:ring-0"
                />
              </label>
            </div>
          </div>

          <button
            type="submit"
            class="px-4 py-2 rounded-full bg-paprika hover:bg-paprika-soft text-ink font-bold text-sm transition-colors"
          >
            {gettext("Save goals")}
          </button>
        </form>
      </div>

      <%!-- Diary: log form (active self periods) + entries --%>
      <div :if={@viewing_period} class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
        <h3 class="text-parchment font-display font-medium mb-4">{gettext("Diary")}</h3>

        <form
          :if={self_logging?(@viewing_period) && is_nil(@viewing_period.ended_on)}
          id={"log-entry-form-#{@viewing_period.id}-#{@entry_form_version}"}
          phx-submit="log_entry"
          phx-change="validate_entry"
          class="border border-ink-panel2 rounded-xl p-4 mb-5 space-y-3"
        >
          <div class="flex items-end gap-2 flex-wrap">
            <label class="block">
              <span class="text-parchment-dim text-xs">{gettext("Date")}</span>
              <input
                type="date"
                name="entry[entry_date]"
                value={@entry_draft["entry_date"] || Date.to_iso8601(Date.utc_today())}
                max={Date.to_iso8601(Date.utc_today())}
                class="mt-1 bg-ink-panel2 border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm focus:border-paprika focus:ring-0"
              />
            </label>
            <label :for={metric <- @viewing_period.tracked_metrics} class="block w-24">
              <span class="text-parchment-dim text-xs">
                {MeasurementChart.metric_label(metric)}
              </span>
              <input
                type="number"
                step="0.1"
                min="0"
                name={"entry[#{metric}]"}
                value={@entry_draft[metric]}
                placeholder={MeasurementChart.metric_unit(metric)}
                class="mt-1 w-full bg-ink-panel2 border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm focus:border-paprika focus:ring-0"
              />
            </label>
          </div>

          <textarea
            name="entry[note]"
            rows="2"
            placeholder={gettext("How did it go? (optional note)")}
            class="w-full bg-ink-panel2 border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm focus:border-paprika focus:ring-0"
          >{@entry_draft["note"]}</textarea>

          <div>
            <label class="inline-flex items-center gap-2 text-sm text-parchment-dim cursor-pointer hover:text-parchment transition">
              <.icon name="hero-camera" class="w-4 h-4" />
              {gettext("Add progress photos")}
              <.live_file_input upload={@uploads.progress_photo} class="sr-only" />
            </label>

            <div :if={@uploads.progress_photo.entries != []} class="flex gap-2 flex-wrap mt-2">
              <div :for={entry <- @uploads.progress_photo.entries} class="relative">
                <.live_img_preview
                  entry={entry}
                  class="w-16 h-16 object-cover rounded-lg border border-ink-panel2"
                />
                <button
                  type="button"
                  phx-click="cancel_photo_upload"
                  phx-value-ref={entry.ref}
                  aria-label={gettext("Cancel upload")}
                  class="absolute -top-1.5 -right-1.5 w-5 h-5 rounded-full bg-ink text-parchment-dim hover:text-paprika text-xs leading-none"
                >
                  ✕
                </button>
                <p
                  :for={err <- upload_errors(@uploads.progress_photo, entry)}
                  class="text-red-400 text-xs mt-1"
                >
                  {upload_error_label(err)}
                </p>
              </div>
            </div>
            <p :for={err <- upload_errors(@uploads.progress_photo)} class="text-red-400 text-xs mt-1">
              {upload_error_label(err)}
            </p>
          </div>

          <button
            type="submit"
            class="px-4 py-2 rounded-full bg-paprika hover:bg-paprika-soft text-ink font-bold text-sm transition-colors"
          >
            {gettext("Log entry")}
          </button>
        </form>

        <%= if @period_entries == [] do %>
          <p :if={!self_logging?(@viewing_period)} class="text-parchment-dim text-sm">
            {gettext("Nothing logged in this period.")}
          </p>
        <% else %>
          <ol class="space-y-3">
            <li
              :for={entry <- @period_entries}
              class="border border-ink-panel2 rounded-xl p-4 flex gap-4 items-start"
            >
              <div class="min-w-0 flex-1">
                <div class="flex items-baseline gap-3 flex-wrap">
                  <span class="text-parchment font-semibold text-sm tabular-nums">
                    {Calendar.strftime(entry.entry_date, "%b %d, %Y")}
                  </span>
                  <span
                    :for={{label, value} <- entry_metric_values(entry)}
                    class="text-parchment-dim text-xs tabular-nums"
                  >
                    {label}: <span class="text-parchment">{value}</span>
                  </span>
                </div>
                <p :if={entry.note} class="text-parchment-dim text-sm mt-1.5 whitespace-pre-line">
                  {entry.note}
                </p>
                <div :if={entry.photos != []} class="flex gap-2 flex-wrap mt-2">
                  <div :for={photo <- entry.photos} class="relative group">
                    <button
                      type="button"
                      phx-click="open_photo"
                      phx-value-id={photo.id}
                      phx-value-date={Date.to_iso8601(entry.entry_date)}
                    >
                      <img
                        src={photo.url}
                        loading="lazy"
                        class="w-16 h-16 object-cover rounded-lg border border-ink-panel2 hover:border-paprika transition"
                        alt={gettext("progress photo")}
                      />
                    </button>
                    <button
                      :if={self_logging?(@viewing_period)}
                      type="button"
                      phx-click="delete_photo"
                      phx-value-id={photo.id}
                      data-confirm={gettext("Delete this photo?")}
                      aria-label={gettext("Delete photo")}
                      class="absolute -top-1.5 -right-1.5 w-5 h-5 rounded-full bg-ink text-parchment-dim hover:text-paprika text-xs leading-none opacity-0 group-hover:opacity-100 focus:opacity-100 transition"
                    >
                      ✕
                    </button>
                  </div>
                </div>
              </div>
              <button
                :if={self_logging?(@viewing_period)}
                type="button"
                phx-click="delete_entry"
                phx-value-id={entry.id}
                data-confirm={gettext("Delete this entry? Its photos are removed too.")}
                class="text-parchment-dim hover:text-paprika text-xs shrink-0 transition"
              >
                {gettext("Delete")}
              </button>
            </li>
          </ol>
        <% end %>
      </div>

      <%!-- Past periods --%>
      <div
        :if={length(@progress_periods) > 1}
        class="bg-ink-panel border border-ink-panel2 rounded-xl p-5"
      >
        <h3 class="text-parchment font-display font-medium mb-3">{gettext("Progress history")}</h3>
        <ul class="space-y-2">
          <li :for={period <- @progress_periods}>
            <button
              type="button"
              phx-click="select_period"
              phx-value-id={period.id}
              class={[
                "w-full flex items-center justify-between gap-3 rounded-lg px-3 py-2.5 border text-left transition",
                if(@viewing_period && period.id == @viewing_period.id,
                  do: "border-paprika bg-[#2e2112]",
                  else: "border-ink-panel2 hover:border-paprika-soft"
                )
              ]}
            >
              <span class="text-parchment text-sm tabular-nums">
                {period_range_label(period)}
                <span :if={period.title} class="text-parchment-dim">· {period.title}</span>
              </span>
              <span class="flex items-center gap-2 shrink-0">
                <span
                  :if={period.shared_with_nutritionist}
                  title={gettext("Shared with nutritionist")}
                >
                  <.icon name="hero-eye" class="w-3.5 h-3.5 text-basil" />
                </span>
                <span class={[
                  "text-[11px] px-2 py-0.5 rounded-full",
                  if(period.kind == "self",
                    do: "bg-paprika/15 text-paprika",
                    else: "bg-basil/15 text-basil"
                  )
                ]}>
                  {period_kind_label(period)}
                </span>
              </span>
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  def get_profile_content(%{content_state: :ingredients} = assigns) do
    ~H"""
    <div class="pb-20 w-full max-w-3xl mx-auto px-4">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-display font-medium text-parchment">My Ingredients</h3>
        <.link
          navigate={~p"/my_ingredients/new"}
          class="px-4 py-2 rounded-full bg-paprika hover:bg-paprika-soft text-ink font-bold text-sm transition-colors"
        >
          + Create ingredient
        </.link>
      </div>

      <%= if @user_ingredients == [] do %>
        <div class="text-parchment-dim text-sm border border-ink-panel2 bg-ink-panel rounded-xl p-6 text-center">
          You haven't created any ingredients yet. Create one to use it in your
          recipes, meal plans, and shopping basket.
        </div>
      <% else %>
        <div class="space-y-3">
          <div
            :for={ingredient <- @user_ingredients}
            class="flex items-center justify-between border border-ink-panel2 bg-ink-panel rounded-xl p-4"
          >
            <div class="min-w-0">
              <div class="text-parchment font-medium truncate">{ingredient.name}</div>
              <div class="text-parchment-dim text-xs">
                {length(ingredient.ingredient_nutrients)} nutrients
              </div>
            </div>
            <div class="flex items-center gap-3 shrink-0">
              <.link
                navigate={~p"/my_ingredients/#{ingredient.id}/edit"}
                class="text-parchment-dim hover:text-parchment text-sm"
              >
                Edit
              </.link>
              <button
                type="button"
                phx-click="delete_my_ingredient"
                phx-value-id={ingredient.id}
                data-confirm="Delete this ingredient? This cannot be undone."
                class="text-parchment-dim hover:text-red-400 text-sm transition-colors"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  def get_profile_content(%{content_state: :edit_profile} = assigns) do
    ~H"""
    <.live_component
      module={MehungryWeb.ProfileLive.Form}
      categories={@categories}
      category_ids={@category_ids}
      food_restriction_ids={@food_restriction_ids}
      food_restrictions={@food_restrictions}
      id="profile_edit_form"
      user_profile={@current_user_profile}
      live_action={@live_action}
      current_user={@current_user}
      title={@page_title}
      action={@live_action}
      form={@form}
    />
    """
  end

  def get_profile_content(%{content_state: :connected_accounts} = assigns) do
    facebook_connected =
      not is_nil(assigns.current_user) and
        map_size(Map.get(assigns.current_user, :facebook_token, %{})) > 0

    facebook_is_primary_login =
      facebook_connected and is_nil(assigns.current_user.hashed_password)

    pinterest_connected =
      not is_nil(assigns.current_user) and
        map_size(Map.get(assigns.current_user, :pinterest_token, %{})) > 0

    assigns =
      assigns
      |> assign(:facebook_connected, facebook_connected)
      |> assign(:facebook_is_primary_login, facebook_is_primary_login)
      |> assign(:pinterest_connected, pinterest_connected)

    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-6 flex flex-col gap-4 mb-10">
      <%= if @nutritionist_assignment do %>
        <% professional = @nutritionist_assignment.professional %>
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 flex items-center justify-between gap-4">
          <div class="flex items-center gap-4 min-w-0">
            <%= if professional.profile_pic do %>
              <img
                src={professional.profile_pic}
                class="w-12 h-12 rounded-full object-cover flex-shrink-0"
              />
            <% else %>
              <div class="w-12 h-12 rounded-full bg-basil flex items-center justify-center text-ink font-bold flex-shrink-0">
                {String.first(professional.name || professional.email || "?")}
              </div>
            <% end %>
            <div class="min-w-0">
              <p class="text-parchment font-semibold truncate">
                {professional.name || professional.email}
              </p>
              <p class="text-parchment-dim text-sm">Your nutritionist</p>
            </div>
          </div>
          <button
            phx-click="unlink_nutritionist"
            data-confirm="Remove your nutritionist? They will no longer be linked to your account. You can be re-invited later."
            class="flex-shrink-0 px-3 py-1.5 rounded-lg bg-ink-panel2 hover:bg-ink-panel text-parchment-dim text-xs font-medium transition"
          >
            Remove
          </button>
        </div>
      <% end %>
      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 flex items-center justify-between gap-4">
        <div class="flex items-center gap-4">
          <div class="w-12 h-12 rounded-full bg-blue-600 flex items-center justify-center flex-shrink-0">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="white" class="w-6 h-6">
              <path d="M22 12c0-5.523-4.477-10-10-10S2 6.477 2 12c0 4.991 3.657 9.128 8.438 9.878V14.89h-2.54V12h2.54V9.797c0-2.506 1.492-3.89 3.777-3.89 1.094 0 2.238.195 2.238.195v2.46h-1.26c-1.243 0-1.63.771-1.63 1.562V12h2.773l-.443 2.89h-2.33v6.988C18.343 21.128 22 16.991 22 12z" />
            </svg>
          </div>
          <div>
            <p class="text-parchment font-semibold">Facebook</p>
            <p class="text-parchment-dim text-sm">
              {if @facebook_connected,
                do: "Connected — you can publish recipes to your Facebook pages",
                else: "Connect your account to publish recipes to your Facebook pages"}
            </p>
          </div>
        </div>
        <%= if @facebook_connected do %>
          <div class="flex flex-col items-end gap-1.5 flex-shrink-0">
            <span class="flex items-center gap-1.5 text-green-400 text-sm font-medium">
              <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                <path
                  fill-rule="evenodd"
                  d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                  clip-rule="evenodd"
                />
              </svg>
              {if @facebook_is_primary_login, do: "Primary login", else: "Connected"}
            </span>
            <%= if not @facebook_is_primary_login do %>
              <button
                phx-click="disconnect_social"
                phx-value-provider="facebook"
                data-confirm="Disconnect your Facebook account?"
                class="px-3 py-1.5 rounded-lg bg-ink-panel2 hover:bg-ink-panel text-parchment-dim text-xs font-medium transition"
              >
                Disconnect
              </button>
            <% end %>
          </div>
        <% else %>
          <a
            href="/auth/facebook"
            class="flex-shrink-0 px-4 py-2 rounded-lg bg-blue-600 hover:bg-blue-500 text-white text-sm font-medium transition"
          >
            Connect
          </a>
        <% end %>
      </div>

      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 flex items-center justify-between gap-4">
        <div class="flex items-center gap-4">
          <div class="w-12 h-12 rounded-xl bg-red-600 flex items-center justify-center flex-shrink-0">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="white" class="w-6 h-6">
              <path d="M12 0C5.373 0 0 5.373 0 12c0 5.084 3.163 9.426 7.627 11.174-.105-.949-.2-2.405.042-3.441.218-.937 1.407-5.965 1.407-5.965s-.359-.719-.359-1.782c0-1.668.967-2.914 2.171-2.914 1.023 0 1.518.769 1.518 1.69 0 1.029-.655 2.568-.994 3.995-.283 1.194.599 2.169 1.777 2.169 2.133 0 3.772-2.249 3.772-5.495 0-2.873-2.064-4.882-5.012-4.882-3.414 0-5.418 2.561-5.418 5.207 0 1.031.397 2.138.893 2.738a.36.36 0 0 1 .083.345l-.333 1.36c-.053.22-.174.267-.402.161-1.499-.698-2.436-2.889-2.436-4.649 0-3.785 2.75-7.262 7.929-7.262 4.163 0 7.398 2.967 7.398 6.931 0 4.136-2.607 7.464-6.227 7.464-1.216 0-2.359-.632-2.75-1.378l-.748 2.853c-.271 1.043-1.002 2.35-1.492 3.146C9.57 23.812 10.763 24 12 24c6.627 0 12-5.373 12-12S18.627 0 12 0z" />
            </svg>
          </div>
          <div>
            <p class="text-parchment font-semibold">Pinterest</p>
            <p class="text-parchment-dim text-sm">
              {if @pinterest_connected,
                do: "Connected — you can pin recipes directly to your boards",
                else: "Connect your account to pin recipes to your Pinterest boards"}
            </p>
          </div>
        </div>
        <%= if @pinterest_connected do %>
          <div class="flex flex-col items-end gap-1.5 flex-shrink-0">
            <span class="flex items-center gap-1.5 text-green-400 text-sm font-medium">
              <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                <path
                  fill-rule="evenodd"
                  d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                  clip-rule="evenodd"
                />
              </svg>
              Connected
            </span>
            <button
              phx-click="disconnect_social"
              phx-value-provider="pinterest"
              data-confirm="Disconnect your Pinterest account?"
              class="px-3 py-1.5 rounded-lg bg-ink-panel2 hover:bg-ink-panel text-parchment-dim text-xs font-medium transition"
            >
              Disconnect
            </button>
          </div>
        <% else %>
          <a
            href="/auth/pinterest"
            class="flex-shrink-0 px-4 py-2 rounded-lg bg-red-600 hover:bg-red-500 text-white text-sm font-medium transition"
          >
            Connect
          </a>
        <% end %>
      </div>
    </div>
    """
  end

  def get_profile_content(assigns), do: ~H""

  # ── Progress tab helpers ─────────────────────────────────────────────────────

  defp self_logging?(%Period{kind: "self"}), do: true
  defp self_logging?(_), do: false

  def period_range_label(%Period{started_on: s, ended_on: nil}),
    do: gettext("%{start} – ongoing", start: Calendar.strftime(s, "%b %d, %Y"))

  def period_range_label(%Period{started_on: s, ended_on: e}),
    do: "#{Calendar.strftime(s, "%b %d, %Y")} – #{Calendar.strftime(e, "%b %d, %Y")}"

  def period_kind_label(%Period{kind: "nutritionist_aligned"}), do: gettext("with nutritionist")
  def period_kind_label(_), do: gettext("self-tracked")

  # The measurements an entry carries, as display pairs (derived BMI/BMR included).
  defp entry_metric_values(entry) do
    Enum.flat_map(MeasurementChart.metric_keys(), fn key ->
      case Map.get(entry, String.to_existing_atom(key)) do
        nil ->
          []

        value ->
          unit = MeasurementChart.metric_unit(key)
          [{MeasurementChart.metric_label(key), "#{value}#{if unit, do: " #{unit}", else: ""}"}]
      end
    end)
  end

  defp upload_error_label(:too_large), do: gettext("That image is too large (max 5 MB).")
  defp upload_error_label(:too_many_files), do: gettext("Up to 4 photos per entry.")
  defp upload_error_label(:not_accepted), do: gettext("Only JPG, PNG or WebP images.")
  defp upload_error_label(_), do: gettext("Upload failed — try again.")
end
