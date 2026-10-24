defmodule MehungryWeb.ProfessionalLive.UniToolsReview do
  @moduledoc """
  Admin-only, one-at-a-time review of the **UniTools World Recipes** dataset
  (`Mehungry.FoodData.UniTools.Catalog`), licensed CC BY-SA 4.0.

  Two modes:

    * **picker** (`/professional/unitools-review`) — lists the catalogued
      datasets with how many recipes have been saved/skipped so far, and a
      Start/Resume link into each.
    * **review** (`/professional/unitools-review/:dataset_id[/:index]`) — for each
      recipe it loads the matched/parsed data into the **same**
      `MehungryWeb.RecipeFormComponent` the Create Recipe page uses (editable)
      beside the **verbatim dataset JSON**, so the admin can compare, fix, and
      Save — or Skip ("pass for now").

  Progress is persisted per recipe ref via `Mehungry.FoodData.UniTools.Imports`
  (`completed` on save, `skipped` on pass), so review resumes where it left off.

  Mounted under the `:default2` admin live_session, so it is admin-gated by
  `MehungryWeb.AdminAuthLive`. Mirrors `MehungryWeb.ProfessionalLive.GutenbergReview`;
  the difference is UniTools carries a reuse obligation, so `license` joins
  source/author/original_url in the provenance re-injected at save.
  """

  use MehungryWeb, :live_view

  require Logger

  alias Mehungry.Food
  alias Mehungry.Food.Recipe
  alias Mehungry.FoodData.UniTools.{Catalog, Decoder, Imports}
  alias Mehungry.FoodData.UniTools.Client, as: UniToolsClient
  alias Mehungry.FoodData.UniToolsImporter
  alias MehungryWeb.ProfessionalLive.ImportReviewComponents
  alias MehungryWeb.ProfessionalLive.ImportReviewSearch

  @empty_recipe %Recipe{steps: [], recipe_ingredients: [], language_name: "En"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "UniTools import review")
     # The admin live_session has no RestoreLocale; default ingredient search to en.
     |> assign(:current_language, "en")
     |> assign(:ingredients, Food.list_ingredients())
     |> assign(:measurement_units, nil)
     |> assign(:image_upload, nil)
     |> assign(:mode, :picker)
     |> assign(:search, "")
     |> assign(:rows, [])
     |> assign(:visible_rows, [])
     |> assign(:datasets, [])
     |> assign(:dataset, nil)
     |> assign(:meta, %{})
     |> assign(:parsed_dataset_id, nil)
     |> assign(:recipes, [])
     |> assign(:recipe_index, nil)
     |> assign(:recipe_total, 0)
     |> assign(:recipe_raw, nil)
     |> assign(:ingredient_overview, [])
     |> assign(:source_steps, [])
     |> assign(:done, false)
     |> assign(:load_error, nil)
     |> assign(:review_status, nil)
     # Imports are staged private; the admin ticks "Publish now" per recipe once
     # it's curated. Provenance (source/author/original_url/license) is re-injected
     # at save because the shared RecipeFormComponent doesn't submit those fields.
     |> assign(:publish_on_save, false)
     |> assign(:provenance, %{})
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

  # ── navigation ───────────────────────────────────────────────────────────────

  @impl true
  def handle_params(%{"dataset_id" => dataset_id, "index" => index}, _uri, socket) do
    {:noreply,
     socket
     |> assign(:mode, :review)
     |> ensure_dataset_loaded(dataset_id)
     |> load_recipe(index)}
  end

  # A dataset with no index → the searchable recipe list (the primary way in).
  def handle_params(%{"dataset_id" => dataset_id}, _uri, socket) do
    {:noreply,
     socket
     |> assign(:mode, :list)
     |> assign(:search, "")
     |> ensure_dataset_loaded(dataset_id)
     |> assign_recipe_rows()}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:mode, :picker)
     |> assign(:datasets, Catalog.datasets())
     |> assign(:dataset_progress, Imports.counts_by_dataset())}
  end

  # Build the searchable row list from the cached recipes + their review status.
  # A load error short-circuits (the template shows the retry panel).
  defp assign_recipe_rows(%{assigns: %{load_error: err}} = socket) when not is_nil(err),
    do: assign(socket, rows: [], visible_rows: [])

  defp assign_recipe_rows(socket) do
    statuses = Imports.statuses_for(socket.assigns.dataset.id)

    rows =
      Enum.map(socket.assigns.recipes, fn recipe ->
        title = recipe_title(recipe)

        %{
          index: recipe.index,
          title: title,
          status: Map.get(statuses, recipe.index),
          search:
            [title, recipe.cuisine, recipe.country] |> Enum.reject(&is_nil/1) |> Enum.join(" ")
        }
      end)

    socket
    |> assign(:rows, rows)
    |> assign(:visible_rows, ImportReviewSearch.filter(rows, socket.assigns.search, & &1.search))
  end

  defp recipe_title(%{title: title, index: index}) do
    case String.trim(to_string(title)) do
      "" -> "Untitled recipe ##{index}"
      trimmed -> trimmed
    end
  end

  # Load + decode the dataset once, then cache the decoded recipe list + meta on
  # the socket so patching between recipes doesn't re-read/re-parse the ~2.6 MB
  # file. A load failure is recorded distinctly (never mistaken for "all reviewed").
  defp ensure_dataset_loaded(socket, dataset_id) do
    cond do
      is_nil(Catalog.get(dataset_id)) ->
        assign(socket, dataset: nil, load_error: "Unknown dataset “#{dataset_id}”.")

      socket.assigns.parsed_dataset_id == dataset_id and socket.assigns.recipes != [] ->
        assign(socket, load_error: nil)

      true ->
        dataset = Catalog.get(dataset_id)

        case UniToolsClient.impl().load_dataset(dataset_id) do
          {:ok, data} ->
            %{meta: meta, recipes: recipes} = Decoder.decode(data)

            socket
            |> assign(:dataset, dataset)
            |> assign(:meta, meta)
            |> assign(:parsed_dataset_id, dataset_id)
            |> assign(:recipes, recipes)
            |> assign(:recipe_total, length(recipes))
            |> assign(:load_error, nil)

          {:error, reason} ->
            socket
            |> assign(:dataset, dataset)
            |> assign(:recipes, [])
            |> assign(:load_error, inspect(reason))
        end
    end
  end

  # Load `requested` (or the first unreviewed recipe) into the form, else flag the
  # genuine "all reviewed" state. A load error short-circuits (the template shows
  # a retry) so an empty list from a failed load is never shown as "done".
  defp load_recipe(%{assigns: %{load_error: err}} = socket, _requested) when not is_nil(err),
    do: assign(socket, done: false, recipe_index: nil)

  defp load_recipe(socket, requested) do
    index = parse_index(requested) || first_unreviewed(socket)

    case index && Enum.find(socket.assigns.recipes, &(&1.index == index)) do
      nil ->
        assign(socket, done: true, recipe_index: nil, recipe_raw: nil)

      recipe ->
        {:ok, attrs, unmatched} =
          UniToolsImporter.build_recipe_attrs(
            recipe,
            socket.assigns.meta,
            socket.assigns.current_user.id
          )

        ref = Imports.ref(socket.assigns.dataset.id, recipe.index)

        socket
        |> assign(:done, false)
        |> assign(:recipe_index, recipe.index)
        |> assign(:recipe_raw, recipe.raw)
        |> assign(:ingredient_overview, ImportReviewComponents.build_overview(attrs, unmatched, socket.assigns.ingredients))
        |> assign(:source_steps, ImportReviewComponents.source_steps(attrs))
        |> assign(:review_status, Imports.status_for(ref))
        # Each recipe starts staged-private; the admin opts in to publishing.
        |> assign(:publish_on_save, false)
        # Fields the shared form won't submit, re-applied at save time.
        |> assign(:provenance, %{
          "source" => attrs.source,
          "author" => attrs.author,
          "original_url" => attrs.original_url,
          "license" => attrs.license
        })
        |> init(@empty_recipe, attrs)
    end
  end

  defp parse_index(nil), do: nil

  defp parse_index(str) do
    case Integer.parse(to_string(str)) do
      {n, _} when n > 0 -> n
      _ -> nil
    end
  end

  defp first_unreviewed(socket) do
    reviewed = Imports.reviewed_refs(socket.assigns.dataset.id)

    Enum.find_value(socket.assigns.recipes, fn recipe ->
      ref = Imports.ref(socket.assigns.dataset.id, recipe.index)
      if not MapSet.member?(reviewed, ref), do: recipe.index
    end)
  end

  # Patch to the next unreviewed recipe of the current dataset (no index → the
  # LiveView resolves the first unreviewed, or shows "all done").
  defp advance(socket) do
    push_patch(socket, to: ~p"/professional/unitools-review/#{socket.assigns.dataset.id}")
  end

  defp current_ref(socket),
    do: Imports.ref(socket.assigns.dataset.id, socket.assigns.recipe_index)

  # ── review actions ────────────────────────────────────────────────────────────

  # Retry loading the dataset after a transient failure.
  @impl true
  def handle_event("unitools_retry", _params, socket) do
    dataset_id = socket.assigns.dataset && socket.assigns.dataset.id

    {:noreply,
     socket
     |> assign(parsed_dataset_id: nil, recipes: [])
     |> ensure_dataset_loaded(dataset_id)
     |> load_recipe(nil)}
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

  # Toggle whether the next Save publishes the recipe (public) or keeps it staged
  # private. Defaults to private — imports are curated before going public.
  def handle_event("toggle_publish", _params, socket) do
    {:noreply, assign(socket, :publish_on_save, not socket.assigns.publish_on_save)}
  end

  def handle_event("unitools_skip", _params, socket) do
    Imports.mark_skipped(current_ref(socket))

    {:noreply,
     socket
     |> put_flash(:info, "Skipped — loading the next recipe.")
     |> advance()}
  end

  # ── form events (RecipeFormComponent bubbles these to its parent) ─────────────

  def handle_event("validate", %{"recipe" => recipe_params}, socket) do
    recipe_params = Map.put(recipe_params, "user_id", socket.assigns.current_user.id)

    changeset =
      socket.assigns.recipe
      |> Food.validation_changeset(recipe_params)
      |> struct!(action: :validate)

    {:noreply, assign(socket, :f, to_form(changeset))}
  end

  def handle_event("save", %{"ingredient" => recipe_params}, socket),
    do: handle_action(socket, recipe_params)

  def handle_event("save", %{"recipe" => recipe_params}, socket),
    do: handle_action(socket, recipe_params)

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

  # "Clear form" reloads the current recipe's matched data (discards edits).
  def handle_event("clear-form", _, socket) do
    {:noreply, load_recipe(socket, socket.assigns.recipe_index)}
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
      # Re-inject provenance + visibility: the shared form doesn't render these,
      # so without this the recipe would save public, untagged, and unlicensed
      # (breaking the "staged private" guarantee, group management by source, and
      # the CC BY-SA 4.0 ShareAlike obligation).
      |> Map.merge(socket.assigns.provenance)
      |> Map.put("private", not socket.assigns.publish_on_save)
      |> filter_empty_steps()
      |> drop_sort_drop_params()

    case Food.create_recipe(recipe_params) do
      {:ok, %Recipe{} = recipe} ->
        Imports.mark_completed(current_ref(socket), recipe.id)

        Logger.info("[unitools_review] saved ref=#{current_ref(socket)} recipe_id=#{recipe.id}")

        visibility = if recipe.private, do: "staged private", else: "published"

        {:noreply,
         socket
         |> put_flash(:info, "Saved “#{recipe.title}” (#{visibility}). Loading the next recipe.")
         |> advance()}

      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.warning(
          "[unitools_review] save failed ref=#{current_ref(socket)} errors=#{inspect(changeset_error_map(changeset))}"
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

  # ── form helpers (mirrors GutenbergReview) ────────────────────────────────────

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

  # ── picker helpers ────────────────────────────────────────────────────────────

  @doc "Saved + skipped counts for `dataset_id` from the `dataset_progress` map."
  def progress_for(dataset_progress, dataset_id) do
    stats = Map.get(dataset_progress, dataset_id, %{})
    {Map.get(stats, "completed", 0), Map.get(stats, "skipped", 0)}
  end

  @doc "Tailwind classes for a recipe-list status badge (`completed`/`skipped`)."
  def status_badge_class("completed"), do: "bg-basil/20 text-basil border border-basil/30"
  def status_badge_class("skipped"), do: "bg-amber-500/20 text-amber-300 border border-amber-500/30"
  def status_badge_class(_), do: "bg-ink-panel2 text-parchment-dim border border-ink-panel2"

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
