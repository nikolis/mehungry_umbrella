defmodule MehungryWeb.NutritionistLive.ArticleEditor do
  @moduledoc """
  Editor for a single professional article. Persists incrementally: the header
  (title/summary/cover) is one form; each paragraph is its own row with its own
  save, its own optional image (single S3 upload bound to the paragraph whose
  image drawer is open), and its own scientific references (PubMed studies, food
  species, compounds, diseases). Publish/unpublish flips public visibility.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Professionals
  alias Mehungry.{Food, Health, Literature}
  alias MehungryWeb.SimpleS3Upload

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    profile = Professionals.get_professional_profile(user.id)
    article = Professionals.get_article!(id)

    if profile && article.professional_profile_id == profile.id do
      {:ok,
       socket
       |> assign(:page_title, "Edit Article")
       |> assign(:profile, profile)
       |> assign(:article, article)
       |> assign(:article_changeset, Professionals.change_article(article))
       |> assign(:image_paragraph_id, nil)
       |> assign(:species_results, [])
       |> assign(:species_paragraph_id, nil)
       |> assign(:compounds, Food.list_compounds())
       |> assign(:conditions, Health.list_conditions())
       |> allow_upload(:cover,
         accept: ~w(.jpg .jpeg .png .webp),
         max_entries: 1,
         max_file_size: 5_000_000,
         external: &presign_upload/2
       )
       |> allow_upload(:paragraph_image,
         accept: ~w(.jpg .jpeg .png .webp),
         max_entries: 1,
         max_file_size: 5_000_000,
         external: &presign_upload/2
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "Article not found.")
       |> push_navigate(to: ~p"/nutritionist/articles")}
    end
  end

  # ── Header (title / summary / cover / publish) ───────────────────────────────

  @impl true
  def handle_event("validate_article", %{"article" => params}, socket) do
    changeset =
      socket.assigns.article
      |> Professionals.change_article(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :article_changeset, changeset)}
  end

  @impl true
  def handle_event("save_article", %{"article" => params}, socket) do
    attrs = maybe_put_cover(params, socket)

    case Professionals.update_article(socket.assigns.article, attrs) do
      {:ok, _article} ->
        {:noreply,
         socket
         |> put_flash(:info, "Article saved.")
         |> reload_article()}

      {:error, changeset} ->
        {:noreply, assign(socket, :article_changeset, changeset)}
    end
  end

  @impl true
  def handle_event("publish", _params, socket) do
    {:ok, _} = Professionals.publish_article(socket.assigns.article)
    {:noreply, socket |> put_flash(:info, "Article published.") |> reload_article()}
  end

  @impl true
  def handle_event("unpublish", _params, socket) do
    {:ok, _} = Professionals.unpublish_article(socket.assigns.article)
    {:noreply, socket |> put_flash(:info, "Moved back to draft.") |> reload_article()}
  end

  # ── Paragraphs ───────────────────────────────────────────────────────────────

  @impl true
  def handle_event("add_paragraph", _params, socket) do
    {:ok, _} = Professionals.create_paragraph(socket.assigns.article.id)
    {:noreply, reload_article(socket)}
  end

  @impl true
  def handle_event("save_paragraph", %{"_id" => id} = params, socket) do
    paragraph = fetch_paragraph(socket, id)

    {:ok, _} =
      Professionals.update_paragraph(paragraph, %{
        "heading" => params["heading"],
        "body" => params["body"],
        "image_caption" => params["image_caption"]
      })

    {:noreply, socket |> put_flash(:info, "Paragraph saved.") |> reload_article()}
  end

  @impl true
  def handle_event("delete_paragraph", %{"id" => id}, socket) do
    {:ok, _} = socket |> fetch_paragraph(id) |> Professionals.delete_paragraph()
    {:noreply, reload_article(socket)}
  end

  @impl true
  def handle_event("move_up", %{"id" => id}, socket),
    do: {:noreply, move(socket, id, -1)}

  @impl true
  def handle_event("move_down", %{"id" => id}, socket),
    do: {:noreply, move(socket, id, 1)}

  # ── Paragraph image ──────────────────────────────────────────────────────────

  @impl true
  def handle_event("open_image", %{"id" => id}, socket),
    do: {:noreply, assign(socket, :image_paragraph_id, String.to_integer(id))}

  @impl true
  def handle_event("cancel_image", _params, socket),
    do: {:noreply, assign(socket, :image_paragraph_id, nil)}

  @impl true
  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("save_image", %{"_id" => id} = params, socket) do
    paragraph = fetch_paragraph(socket, id)

    attrs =
      case consume_uploaded_entries(socket, :paragraph_image, fn %{url: url, key: key}, _entry ->
             {:ok, url <> "/" <> key}
           end) do
        [image_url | _] -> %{"image_url" => image_url, "image_caption" => params["image_caption"]}
        [] -> %{"image_caption" => params["image_caption"]}
      end

    {:ok, _} = Professionals.update_paragraph(paragraph, attrs)

    {:noreply, socket |> assign(:image_paragraph_id, nil) |> reload_article()}
  end

  @impl true
  def handle_event("remove_image", %{"id" => id}, socket) do
    {:ok, _} =
      socket |> fetch_paragraph(id) |> Professionals.update_paragraph(%{"image_url" => nil})

    {:noreply, reload_article(socket)}
  end

  # ── References ───────────────────────────────────────────────────────────────

  @impl true
  def handle_event("search_species", %{"_id" => id, "term" => term}, socket) do
    {:noreply,
     socket
     |> assign(:species_results, Food.search_species(term))
     |> assign(:species_paragraph_id, String.to_integer(id))}
  end

  @impl true
  def handle_event("add_species_ref", %{"paragraph-id" => pid, "species-id" => sid}, socket) do
    add_ref(socket, pid, %{"reference_type" => "species", "species_id" => sid})
    |> then(
      &{:noreply, &1 |> assign(:species_results, []) |> assign(:species_paragraph_id, nil)}
    )
  end

  @impl true
  def handle_event("add_compound_ref", %{"_id" => pid, "compound_id" => cid}, socket)
      when cid != "" do
    {:noreply, add_ref(socket, pid, %{"reference_type" => "compound", "compound_id" => cid})}
  end

  @impl true
  def handle_event("add_condition_ref", %{"_id" => pid, "condition_id" => cid}, socket)
      when cid != "" do
    {:noreply, add_ref(socket, pid, %{"reference_type" => "condition", "condition_id" => cid})}
  end

  @impl true
  def handle_event("add_study_ref", %{"_id" => pid, "pmid" => pmid}, socket) do
    case Literature.fetch_and_upsert_study(pmid) do
      {:ok, study} ->
        {:noreply, add_ref(socket, pid, %{"reference_type" => "study", "study_id" => study.id})}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, "Could not find PubMed paper #{pmid}. Check the PMID.")}
    end
  end

  def handle_event("add_compound_ref", _params, socket), do: {:noreply, socket}
  def handle_event("add_condition_ref", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("remove_reference", %{"id" => id}, socket) do
    reference = Professionals.get_reference!(id)

    if reference.article_id == socket.assigns.article.id do
      {:ok, _} = Professionals.delete_reference(reference)
      {:noreply, reload_article(socket)}
    else
      {:noreply, socket}
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp add_ref(socket, paragraph_id, attrs) do
    paragraph = fetch_paragraph(socket, paragraph_id)

    case Professionals.add_reference(paragraph, attrs) do
      {:ok, _} -> reload_article(socket)
      {:error, _} -> put_flash(socket, :error, "That reference is already cited here.")
    end
  end

  defp fetch_paragraph(socket, id) do
    id = if is_binary(id), do: String.to_integer(id), else: id
    Enum.find(socket.assigns.article.paragraphs, &(&1.id == id))
  end

  defp move(socket, id, delta) do
    pid = String.to_integer(id)
    ids = Enum.map(socket.assigns.article.paragraphs, & &1.id)

    case Enum.find_index(ids, &(&1 == pid)) do
      nil ->
        socket

      index ->
        target = index + delta

        if target >= 0 and target < length(ids) do
          reordered = ids |> List.delete_at(index) |> List.insert_at(target, pid)
          Professionals.reorder_paragraphs(socket.assigns.article.id, reordered)
          reload_article(socket)
        else
          socket
        end
    end
  end

  defp reload_article(socket) do
    article = Professionals.get_article!(socket.assigns.article.id)

    socket
    |> assign(:article, article)
    |> assign(:article_changeset, Professionals.change_article(article))
  end

  defp maybe_put_cover(params, socket) do
    case consume_uploaded_entries(socket, :cover, fn %{url: url, key: key}, _entry ->
           {:ok, url <> "/" <> key}
         end) do
      [cover_url | _] -> Map.put(params, "cover_image_url", cover_url)
      [] -> params
    end
  end

  defp presign_upload(entry, socket) do
    {:ok, SimpleS3Upload.meta_for(entry, 5_000_000, "article_images"), socket}
  end

  # Display label + external link for a reference chip.
  defp reference_label(%{reference_type: "study", study: %{} = s}),
    do: {s.title || "PMID #{s.pmid}", "https://pubmed.ncbi.nlm.nih.gov/#{s.pmid}"}

  defp reference_label(%{reference_type: "species", species: %{} = s}),
    do: {s.scientific_name || s.name, nil}

  defp reference_label(%{reference_type: "compound", compound: %{} = c}), do: {c.name, nil}
  defp reference_label(%{reference_type: "condition", condition: %{} = c}), do: {c.name, nil}
  defp reference_label(_), do: {"reference", nil}

  defp reference_kind(%{reference_type: t}), do: t

  # ── Render ───────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto pb-24">
      <div class="flex items-center justify-between mb-6">
        <.link navigate={~p"/nutritionist/articles"} class="text-sm text-parchment-dim hover:text-parchment">
          ← All articles
        </.link>
        <div class="flex items-center gap-3">
          <span class={[
            "text-xs px-2 py-0.5 rounded-full",
            @article.status == "published" && "bg-basil/20 text-basil",
            @article.status == "draft" && "bg-ink-panel2 text-parchment-dim"
          ]}>
            {@article.status}
          </span>
          <a
            :if={@article.status == "published" && @profile.slug}
            href={~p"/nutritionists/#{@profile.slug}/articles/#{@article.slug}"}
            target="_blank"
            class="text-sm text-paprika hover:text-paprika-soft"
          >
            View public →
          </a>
          <button
            :if={@article.status == "draft"}
            phx-click="publish"
            class="px-3 py-1.5 rounded-lg bg-basil hover:bg-basil/80 text-ink font-semibold text-sm transition"
          >
            Publish
          </button>
          <button
            :if={@article.status == "published"}
            phx-click="unpublish"
            class="px-3 py-1.5 rounded-lg bg-ink-panel2 hover:bg-ink-panel text-parchment text-sm transition"
          >
            Unpublish
          </button>
        </div>
      </div>

      <!-- Header form -->
      <.form
        :let={f}
        for={@article_changeset}
        id="article-header-form"
        phx-change="validate_article"
        phx-submit="save_article"
        class="bg-ink-panel border border-ink-panel2 rounded-xl p-6 space-y-4 mb-6"
      >
        <div>
          <label class="block text-sm text-parchment-dim mb-1">Title</label>
          <.input field={f[:title]} type="text" placeholder="Article title" class="w-full" />
        </div>
        <div>
          <label class="block text-sm text-parchment-dim mb-1">Summary</label>
          <.input field={f[:summary]} type="textarea" rows="2" class="w-full" />
        </div>
        <div>
          <label class="block text-sm text-parchment-dim mb-1">Cover image</label>
          <img
            :if={@article.cover_image_url}
            src={@article.cover_image_url}
            class="w-full max-h-48 object-cover rounded-lg mb-2"
          />
          <.live_file_input upload={@uploads.cover} class="text-parchment-dim text-sm" />
        </div>
        <div class="flex justify-end">
          <button
            type="submit"
            class="px-4 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-semibold text-sm transition"
          >
            Save
          </button>
        </div>
      </.form>

      <!-- Paragraphs -->
      <h2 class="text-lg font-display font-semibold text-parchment mb-3">Body</h2>

      <div class="space-y-4">
        <div
          :for={{paragraph, index} <- Enum.with_index(@article.paragraphs)}
          class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 space-y-4"
        >
          <div class="flex items-center justify-between">
            <span class="text-xs text-parchment-dim">Paragraph {index + 1}</span>
            <div class="flex items-center gap-2">
              <button
                phx-click="move_up"
                phx-value-id={paragraph.id}
                disabled={index == 0}
                class="text-parchment-dim hover:text-parchment disabled:opacity-30 text-sm"
              >
                ↑
              </button>
              <button
                phx-click="move_down"
                phx-value-id={paragraph.id}
                disabled={index == length(@article.paragraphs) - 1}
                class="text-parchment-dim hover:text-parchment disabled:opacity-30 text-sm"
              >
                ↓
              </button>
              <button
                phx-click="delete_paragraph"
                phx-value-id={paragraph.id}
                data-confirm="Delete this paragraph?"
                class="text-parchment-dim hover:text-red-400 text-sm"
              >
                Delete
              </button>
            </div>
          </div>

          <form phx-submit="save_paragraph" class="space-y-3">
            <input type="hidden" name="_id" value={paragraph.id} />
            <input
              type="text"
              name="heading"
              value={paragraph.heading}
              placeholder="Optional heading"
              class="w-full bg-ink border border-ink-panel2 rounded-lg text-parchment px-3 py-2 text-sm"
            />
            <textarea
              name="body"
              rows="5"
              placeholder="Paragraph text…"
              class="w-full bg-ink border border-ink-panel2 rounded-lg text-parchment px-3 py-2 text-sm"
            >{paragraph.body}</textarea>
            <input type="hidden" name="image_caption" value={paragraph.image_caption} />
            <div class="flex justify-end">
              <button
                type="submit"
                class="px-3 py-1.5 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-semibold text-xs transition"
              >
                Save paragraph
              </button>
            </div>
          </form>

          <!-- Image -->
          <div class="border-t border-ink-panel2 pt-3">
            <div :if={paragraph.image_url} class="mb-2">
              <img src={paragraph.image_url} class="w-full max-h-56 object-cover rounded-lg" />
              <p :if={paragraph.image_caption} class="text-parchment-dim text-xs mt-1 italic">
                {paragraph.image_caption}
              </p>
            </div>

            <div :if={@image_paragraph_id != paragraph.id} class="flex items-center gap-3">
              <button
                phx-click="open_image"
                phx-value-id={paragraph.id}
                class="text-sm text-paprika hover:text-paprika-soft"
              >
                {if paragraph.image_url, do: "Change image", else: "+ Add image"}
              </button>
              <button
                :if={paragraph.image_url}
                phx-click="remove_image"
                phx-value-id={paragraph.id}
                class="text-sm text-parchment-dim hover:text-red-400"
              >
                Remove image
              </button>
            </div>

            <form
              :if={@image_paragraph_id == paragraph.id}
              phx-submit="save_image"
              phx-change="validate_upload"
              class="space-y-2"
            >
              <input type="hidden" name="_id" value={paragraph.id} />
              <.live_file_input upload={@uploads.paragraph_image} class="text-parchment-dim text-sm" />
              <input
                type="text"
                name="image_caption"
                value={paragraph.image_caption}
                placeholder="Image caption (optional)"
                class="w-full bg-ink border border-ink-panel2 rounded-lg text-parchment px-3 py-2 text-sm"
              />
              <div class="flex items-center gap-2">
                <button
                  type="submit"
                  class="px-3 py-1.5 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-semibold text-xs transition"
                >
                  Save image
                </button>
                <button
                  type="button"
                  phx-click="cancel_image"
                  class="text-sm text-parchment-dim hover:text-parchment"
                >
                  Cancel
                </button>
              </div>
            </form>
          </div>

          <!-- References -->
          <div class="border-t border-ink-panel2 pt-3">
            <span class="text-xs font-semibold text-basil uppercase tracking-wider">References</span>

            <div :if={paragraph.references != []} class="flex flex-wrap gap-2 mt-2">
              <span
                :for={ref <- paragraph.references}
                class="inline-flex items-center gap-1 bg-ink-panel2 text-parchment-dim text-xs rounded-full pl-2 pr-1 py-0.5"
              >
                <span class="text-basil">{reference_kind(ref)}</span>
                <% {label, _url} = reference_label(ref) %>
                <span class="truncate max-w-[16rem]">{label}</span>
                <button
                  phx-click="remove_reference"
                  phx-value-id={ref.id}
                  class="hover:text-red-400 px-1"
                >
                  ×
                </button>
              </span>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-3">
              <!-- PubMed -->
              <form phx-submit="add_study_ref" class="flex gap-2">
                <input type="hidden" name="_id" value={paragraph.id} />
                <input
                  type="text"
                  name="pmid"
                  inputmode="numeric"
                  placeholder="PubMed PMID"
                  class="flex-1 bg-ink border border-ink-panel2 rounded-lg text-parchment px-3 py-1.5 text-sm"
                />
                <button type="submit" class="text-sm text-paprika hover:text-paprika-soft">Add</button>
              </form>

              <!-- Compound -->
              <form phx-submit="add_compound_ref" class="flex gap-2">
                <input type="hidden" name="_id" value={paragraph.id} />
                <select
                  name="compound_id"
                  class="flex-1 bg-ink border border-ink-panel2 rounded-lg text-parchment px-3 py-1.5 text-sm"
                >
                  <option value="">Compound…</option>
                  <option :for={c <- @compounds} value={c.id}>{c.name}</option>
                </select>
                <button type="submit" class="text-sm text-paprika hover:text-paprika-soft">Add</button>
              </form>

              <!-- Condition -->
              <form phx-submit="add_condition_ref" class="flex gap-2">
                <input type="hidden" name="_id" value={paragraph.id} />
                <select
                  name="condition_id"
                  class="flex-1 bg-ink border border-ink-panel2 rounded-lg text-parchment px-3 py-1.5 text-sm"
                >
                  <option value="">Disease…</option>
                  <option :for={c <- @conditions} value={c.id}>{c.name}</option>
                </select>
                <button type="submit" class="text-sm text-paprika hover:text-paprika-soft">Add</button>
              </form>

              <!-- Species -->
              <form phx-submit="search_species" class="flex gap-2">
                <input type="hidden" name="_id" value={paragraph.id} />
                <input
                  type="text"
                  name="term"
                  placeholder="Search species…"
                  class="flex-1 bg-ink border border-ink-panel2 rounded-lg text-parchment px-3 py-1.5 text-sm"
                />
                <button type="submit" class="text-sm text-paprika hover:text-paprika-soft">Find</button>
              </form>
            </div>

            <div
              :if={@species_paragraph_id == paragraph.id && @species_results != []}
              class="mt-2 flex flex-wrap gap-2"
            >
              <button
                :for={s <- @species_results}
                phx-click="add_species_ref"
                phx-value-paragraph-id={paragraph.id}
                phx-value-species-id={s.id}
                class="text-xs bg-ink-panel2 hover:bg-ink text-parchment rounded-full px-2 py-1"
              >
                {s.name}<span :if={s.scientific_name} class="text-parchment-dim italic"> · {s.scientific_name}</span>
              </button>
            </div>
          </div>
        </div>
      </div>

      <button
        phx-click="add_paragraph"
        class="mt-4 w-full py-3 rounded-xl border border-dashed border-ink-panel2 text-parchment-dim hover:text-parchment hover:border-paprika transition text-sm"
      >
        + Add paragraph
      </button>
    </div>
    """
  end
end
