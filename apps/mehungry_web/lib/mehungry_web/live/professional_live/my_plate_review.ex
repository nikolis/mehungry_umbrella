defmodule MehungryWeb.ProfessionalLive.MyPlateReview do
  @moduledoc """
  Admin-only, one-at-a-time review of the public-domain USDA MyPlate recipe
  corpus. For each slug it loads the matched/parsed recipe into the **same**
  `MehungryWeb.RecipeFormComponent` the Create Recipe page uses (editable) and
  shows the **raw MyPlate API JSON** beside it, so the admin can compare, fix,
  and Save — or Skip ("pass for now").

  Progress is persisted per slug via `Mehungry.FoodData.MyPlate.Imports`
  (`completed` on save, `skipped` on pass), so review resumes where it left off.

  Mounted under the `:default2` admin live_session (`/professional/myplate-review`),
  so it is admin-gated by `MehungryWeb.AdminAuthLive` — it is deliberately NOT the
  user-facing Create Recipe LiveView. The form **event handling** (validate / save
  / add+remove ingredient & step rows / image upload / ingredient picker) is copied
  from `MehungryWeb.CreateRecipeLive.Index` because `RecipeFormComponent` bubbles
  those events to its parent.
  """

  use MehungryWeb, :live_view

  require Logger

  alias Mehungry.Food
  alias Mehungry.Food.Recipe
  alias Mehungry.FoodData.MyPlate.Client, as: MyPlateClient
  alias Mehungry.FoodData.MyPlate.Imports, as: MyPlateImports
  alias Mehungry.FoodData.MyPlateImporter
  alias MehungryWeb.ProfessionalLive.ImportReviewComponents
  alias MehungryWeb.ProfessionalLive.ImportReviewSearch

  @empty_recipe %Recipe{steps: [], recipe_ingredients: [], language_name: "En"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "MyPlate import review")
     # The admin live_session has no RestoreLocale; default ingredient search to en.
     |> assign(:current_language, "en")
     |> assign(:ingredients, Food.list_ingredients())
     |> assign(:measurement_units, nil)
     |> assign(:image_upload, nil)
     |> assign(:mode, :list)
     |> assign(:search, "")
     |> assign(:rows, [])
     |> assign(:visible_rows, [])
     |> assign(:myplate_slugs, [])
     |> assign(:myplate_total, 0)
     |> assign(:myplate_slug, nil)
     |> assign(:myplate_raw, nil)
     |> assign(:myplate_index, nil)
     |> assign(:myplate_done, false)
     |> assign(:myplate_load_error, nil)
     |> assign(:myplate_rate_limited, nil)
     |> assign(:review_status, nil)
     |> assign(:spoonacular_unmatched, [])
     |> assign(:ingredient_overview, [])
     |> assign(:source_steps, [])
     |> assign(:recipe, @empty_recipe)
     |> assign(:f, to_form(Recipe.changeset(@empty_recipe, %{})))
     |> allow_upload(:image,
       accept: :any,
       max_entries: 1,
       max_file_size: 9_000_000,
       auto_upload: false,
       external: &presign_upload/2
     )}
  end

  # ── navigation / slug loading ──────────────────────────────────────────────

  @impl true
  def handle_params(%{"slug" => slug}, _uri, socket) do
    {:noreply,
     socket
     |> assign(:mode, :review)
     |> ensure_slugs_loaded()
     |> load_slug(slug)}
  end

  # No slug → the searchable recipe list (the primary way in).
  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:mode, :list)
     |> assign(:search, "")
     |> assign(:myplate_done, false)
     |> ensure_slugs_loaded()
     |> assign_slug_rows()}
  end

  # Build the searchable row list from the slug corpus + each slug's review
  # status. Titles are humanized from the slug (the full recipe — hence the real
  # title — is only fetched when the admin opens one, to respect the daily cap).
  defp assign_slug_rows(socket) do
    statuses = MyPlateImports.statuses_by_slug()

    rows =
      Enum.map(socket.assigns.myplate_slugs, fn slug ->
        title = humanize_slug(slug)

        %{
          slug: slug,
          title: title,
          status: Map.get(statuses, slug),
          search: title <> " " <> slug
        }
      end)

    socket
    |> assign(:rows, rows)
    |> assign(:visible_rows, ImportReviewSearch.filter(rows, socket.assigns.search, & &1.search))
  end

  defp humanize_slug(slug) do
    slug |> String.split("-") |> Enum.map_join(" ", &String.capitalize/1)
  end

  # Fetch the ordered slug corpus once per session, then cache it on the socket.
  # A load failure is recorded distinctly (myplate_load_error) so it is NOT
  # mistaken for "all reviewed".
  defp ensure_slugs_loaded(socket) do
    if socket.assigns.myplate_slugs != [] do
      assign(socket, :myplate_load_error, nil)
    else
      case MyPlateClient.impl().list_slugs() do
        {:ok, slugs} ->
          assign(socket, myplate_slugs: slugs, myplate_total: length(slugs), myplate_load_error: nil)

        {:error, reason} ->
          assign(socket, myplate_slugs: [], myplate_total: 0, myplate_load_error: inspect(reason))
      end
    end
  end

  # Load `requested` (or the first unreviewed slug) into the form, else flag the
  # genuine "all reviewed" state. A list-load error short-circuits (the template
  # shows a retry), so an empty list from a failed fetch is never shown as "done".
  defp load_slug(socket, requested) do
    slugs = socket.assigns.myplate_slugs
    slug = requested || first_unreviewed(slugs)

    cond do
      socket.assigns.myplate_load_error -> assign(socket, myplate_slug: nil, myplate_done: false)
      is_nil(slug) -> assign(socket, myplate_slug: nil, myplate_done: true)
      true -> fetch_slug(socket, slug)
    end
  end

  defp fetch_slug(socket, slug) do
    case MyPlateClient.impl().fetch_recipe(slug) do
      {:ok, data} ->
        {:ok, attrs, unmatched} =
          MyPlateImporter.build_recipe_attrs(data, socket.assigns.current_user.id)

        index = Enum.find_index(socket.assigns.myplate_slugs, &(&1 == slug))

        socket
        |> assign(:myplate_slug, slug)
        |> assign(:myplate_done, false)
        |> assign(:myplate_rate_limited, nil)
        |> assign(:myplate_raw, Jason.encode!(data, pretty: true))
        |> assign(:myplate_index, (index || 0) + 1)
        |> assign(:review_status, MyPlateImports.status_for(slug))
        |> assign(:spoonacular_unmatched, unmatched)
        |> assign(:ingredient_overview, ImportReviewComponents.build_overview(attrs, unmatched, socket.assigns.ingredients))
        |> assign(:source_steps, ImportReviewComponents.source_steps(attrs))
        |> init(@empty_recipe, attrs)

      {:error, {:rate_limited, seconds}} ->
        # The myplate.food API caps full-recipe fetches at 100/day per IP.
        socket
        |> assign(:myplate_slug, slug)
        |> assign(:myplate_done, false)
        |> assign(:myplate_raw, nil)
        |> assign(:myplate_rate_limited, seconds)

      {:error, reason} ->
        socket
        |> assign(:myplate_slug, slug)
        |> assign(:myplate_done, false)
        |> assign(:myplate_rate_limited, nil)
        |> assign(:myplate_raw, nil)
        |> put_flash(:error, "Could not load #{slug}: #{inspect(reason)}")
    end
  end

  defp first_unreviewed(slugs) do
    reviewed = MyPlateImports.reviewed_slugs()
    Enum.find(slugs, &(not MapSet.member?(reviewed, &1)))
  end

  @doc "Human wait until the daily cap resets, from a Retry-After in seconds."
  def rate_limit_wait(seconds) when is_integer(seconds) and seconds >= 3600,
    do: "~#{ceil(seconds / 3600)}h"

  def rate_limit_wait(seconds) when is_integer(seconds), do: "~#{max(ceil(seconds / 60), 1)}m"
  def rate_limit_wait(_), do: "a while"

  @doc "Tailwind classes for a recipe-list status badge (`completed`/`skipped`)."
  def status_badge_class("completed"), do: "bg-basil/20 text-basil border border-basil/30"
  def status_badge_class("skipped"), do: "bg-amber-500/20 text-amber-300 border border-amber-500/30"
  def status_badge_class(_), do: "bg-ink-panel2 text-parchment-dim border border-ink-panel2"

  # After save/skip, return to the searchable list (the primary selection surface)
  # so the admin picks the next recipe deliberately rather than being auto-advanced.
  defp advance(socket) do
    push_patch(socket, to: ~p"/professional/myplate-review")
  end

  # ── review actions ──────────────────────────────────────────────────────────

  # Retry loading the slug list after a transient API failure, then re-render the
  # surface we were on (the recipe list, or the open recipe in review mode).
  @impl true
  def handle_event("myplate_retry", _params, socket) do
    socket =
      socket
      |> assign(myplate_slugs: [], myplate_total: 0)
      |> ensure_slugs_loaded()

    socket =
      if socket.assigns.mode == :review and socket.assigns.myplate_slug do
        load_slug(socket, socket.assigns.myplate_slug)
      else
        assign_slug_rows(socket)
      end

    {:noreply, socket}
  end

  # Fuzzy-filter the recipe list as the admin types (list mode).
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply,
     socket
     |> assign(:search, query)
     |> assign(
       :visible_rows,
       ImportReviewSearch.filter(socket.assigns.rows, query, & &1.search)
     )}
  end

  @impl true
  def handle_event("myplate_skip", _params, socket) do
    MyPlateImports.mark_skipped(socket.assigns.myplate_slug)

    {:noreply,
     socket
     |> put_flash(:info, "Skipped — loading the next recipe.")
     |> advance()}
  end

  # ── form events (copied from CreateRecipeLive.Index; RecipeFormComponent
  #    bubbles these to its parent) ───────────────────────────────────────────

  @impl true
  def handle_event("validate", %{"recipe" => recipe_params}, socket) do
    recipe_params = Map.put(recipe_params, "user_id", socket.assigns.current_user.id)

    changeset =
      socket.assigns.recipe
      |> Food.validation_changeset(recipe_params)
      |> struct!(action: :validate)

    {:noreply, assign(socket, :f, to_form(changeset))}
  end

  def handle_event("save", %{"ingredient" => recipe_params}, socket) do
    handle_action(socket, recipe_params)
  end

  def handle_event("save", %{"recipe" => recipe_params}, socket) do
    handle_action(socket, recipe_params)
  end

  def handle_event("delete-image", _, socket) do
    %Recipe{} = current_recipe = socket.assigns.recipe
    recipe = %Recipe{current_recipe | image_url: nil}

    {:noreply,
     socket
     |> assign(:recipe, recipe)
     |> init(recipe)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  # "Clear form" in review mode reloads the current slug's matched data (discards
  # edits) rather than blanking the page.
  def handle_event("clear-form", _, socket) do
    {:noreply, load_slug(socket, socket.assigns.myplate_slug)}
  end

  def handle_event("other", _, socket), do: {:noreply, socket}

  # In-form add/remove of ingredient/step rows flows through the "save" submit
  # with an `_action`; a real save creates the recipe and advances.
  defp handle_action(socket, params) do
    case params["_action"] do
      "add_ingredient" -> rebuild_form(socket, add_row(params, "recipe_ingredients"))
      "remove_ingredient:" <> index -> rebuild_form(socket, drop_row(params, "recipe_ingredients", index))
      "add_step" -> rebuild_form(socket, add_row(params, "steps"))
      "remove_step:" <> index -> rebuild_form(socket, drop_row(params, "steps", index))
      _ -> save_recipe(socket, params)
    end
  end

  defp save_recipe(socket, recipe_params) do
    path =
      consume_uploaded_entries(socket, :image, fn %{public_url: public_url}, _entry ->
        {:ok, public_url}
      end)
      |> Enum.at(0)

    socket = assign(socket, :image_upload, path)

    recipe_params =
      socket
      |> get_params_with_image(recipe_params)
      |> Map.put("user_id", socket.assigns.current_user.id)
      |> filter_empty_steps()
      |> drop_sort_drop_params()

    case Food.create_recipe(recipe_params) do
      {:ok, %Recipe{} = recipe} ->
        MyPlateImports.mark_completed(socket.assigns.myplate_slug, recipe.id)

        Logger.info(
          "[myplate_review] saved slug=#{socket.assigns.myplate_slug} recipe_id=#{recipe.id}"
        )

        {:noreply,
         socket
         |> put_flash(:info, "Saved “#{recipe.title}”. Loading the next recipe.")
         |> advance()}

      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.warning(
          "[myplate_review] save failed slug=#{socket.assigns.myplate_slug} errors=#{inspect(changeset_error_map(changeset))}"
        )

        {:noreply,
         socket
         |> assign(:changeset, changeset)
         |> assign(:f, to_form(%{changeset | action: :insert}))
         |> put_flash(:error, save_error_flash(changeset))}
    end
  end

  # IngredientComponent reports a picked ingredient id back to the parent.
  @impl true
  def handle_info({:select_id, id, component_id}, socket) do
    send_update(MehungryWeb.IngredientComponent, id: component_id, new_ingredient_id: id)
    {:noreply, socket}
  end

  # ── form helpers (copied from CreateRecipeLive.Index) ────────────────────────

  defp init(socket, base, attrs \\ %{}) do
    changeset =
      Recipe.changeset(base, attrs)
      |> struct!(action: :validate)

    socket
    |> assign(:f, to_form(changeset))
    |> assign(:recipe, base)
  end

  defp rebuild_form(socket, params) do
    changeset =
      socket.assigns.recipe
      |> Food.validation_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :f, to_form(changeset))}
  end

  defp add_row(params, field) do
    Map.update(params, "#{field}_sort", ["new"], &(&1 ++ ["new"]))
  end

  defp drop_row(params, field, index) do
    Map.update(params, "#{field}_drop", [index], &(&1 ++ [index]))
  end

  defp get_params_with_image(socket, params) do
    if is_nil(socket.assigns.image_upload) do
      params
    else
      Map.put(params, "image_url", socket.assigns.image_upload)
    end
  end

  defp filter_empty_steps(recipe_params) do
    steps = Map.get(recipe_params, "steps", %{})

    filtered =
      steps
      |> Enum.reject(fn {_k, v} -> is_nil(v["description"]) or v["description"] == "" end)
      |> Map.new()

    Map.put(recipe_params, "steps", filtered)
  end

  defp drop_sort_drop_params(recipe_params) do
    Map.drop(recipe_params, [
      "recipe_ingredients_sort",
      "recipe_ingredients_drop",
      "steps_sort",
      "steps_drop"
    ])
  end

  defp save_error_flash(changeset) do
    case MehungryWeb.RecipeFormComponent.save_error_messages(changeset) do
      [] -> "Couldn't save the recipe — please review the form and try again."
      msgs -> "Couldn't save: " <> Enum.join(msgs, " · ")
    end
  end

  defp changeset_error_map(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp presign_upload(entry, %{assigns: %{uploads: uploads}} = socket) do
    meta =
      MehungryWeb.Uploads.meta(
        entry,
        MehungryWeb.Uploads.recipe_image_key(entry),
        uploads.image.max_file_size
      )

    {:ok, meta, socket}
  end
end
