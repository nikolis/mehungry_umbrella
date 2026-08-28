defmodule MehungryWeb.PublicNutritionistLive.Article do
  @moduledoc """
  Public, SEO-indexed article page at
  `/nutritionists/:slug/articles/:article_slug`. Only **published** articles
  resolve; the full body (paragraphs, per-paragraph images, and a numbered
  scientific bibliography) is rendered synchronously so the disconnected
  ("dead") render Googlebot indexes carries the whole article plus `Article`
  JSON-LD. Draft or unknown slugs redirect back to the author's profile.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Professionals

  @impl true
  def mount(%{"slug" => slug, "article_slug" => article_slug}, _session, socket) do
    case Professionals.get_published_article_by_slug(article_slug) do
      %{professional_profile: %{slug: ^slug} = profile} = article ->
        {:ok,
         socket
         |> assign_new(:current_user, fn -> nil end)
         |> assign(:profile, profile)
         |> assign(:article, article)
         |> assign(:references, numbered_references(article))
         |> assign_seo(article, profile)}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/nutritionists/#{slug}")}
    end
  end

  # ── SEO ──────────────────────────────────────────────────────────────────────

  defp assign_seo(socket, article, profile) do
    description =
      (article.summary || article.title)
      |> String.slice(0, 155)

    socket
    |> assign(:page_title, article.title)
    |> assign(:page_description, description)
    |> assign(:canonical_path, "/nutritionists/#{profile.slug}/articles/#{article.slug}")
    |> assign(:structured_data, structured_data(article, profile))
  end

  defp structured_data(article, profile) do
    canonical = url(~p"/nutritionists/#{profile.slug}/articles/#{article.slug}")

    node =
      %{
        "@type" => "Article",
        "headline" => article.title,
        "description" => article.summary,
        "image" => article.cover_image_url,
        "url" => canonical,
        "datePublished" => iso8601(article.published_at),
        "dateModified" => iso8601(article.updated_at),
        "author" => %{
          "@type" => "Person",
          "name" => display_name(profile),
          "url" => url(~p"/nutritionists/#{profile.slug}")
        },
        "publisher" => %{"@type" => "Organization", "name" => "M3Hungry"},
        "citation" =>
          article.paragraphs
          |> Enum.flat_map(& &1.references)
          |> Enum.uniq_by(&ref_key/1)
          |> Enum.map(&citation_text/1)
      }
      |> compact()

    [node]
  end

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso8601(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)

  defp compact(map) do
    map
    |> Enum.reject(fn {_k, v} -> v in [nil, [], ""] end)
    |> Map.new()
  end

  # ── References (numbered, deduped in encounter order) ────────────────────────

  # Returns %{key => number} plus the ordered unique reference list, so both the
  # inline markers and the foot bibliography share one numbering.
  defp numbered_references(article) do
    unique =
      article.paragraphs
      |> Enum.flat_map(& &1.references)
      |> Enum.uniq_by(&ref_key/1)

    numbers =
      unique
      |> Enum.with_index(1)
      |> Map.new(fn {ref, n} -> {ref_key(ref), n} end)

    %{list: unique, numbers: numbers}
  end

  defp ref_key(%{reference_type: t, study_id: s, species_id: sp, compound_id: c, condition_id: co}),
    do: {t, s, sp, c, co}

  defp ref_number(references, ref), do: Map.get(references.numbers, ref_key(ref))

  # ── Citation formatting ──────────────────────────────────────────────────────

  defp citation_text(%{reference_type: "study", study: s}) do
    authors =
      case s.authors do
        [a | _] = list when length(list) > 3 -> "#{a} et al."
        list when is_list(list) and list != [] -> Enum.join(list, ", ")
        _ -> nil
      end

    [authors, s.publication_date && "(#{s.publication_date})", s.title, s.journal]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(". ")
  end

  defp citation_text(%{reference_type: "species", species: sp}),
    do: sp.scientific_name || sp.name

  defp citation_text(%{reference_type: "compound", compound: c}), do: "Compound: #{c.name}"
  defp citation_text(%{reference_type: "condition", condition: c}), do: "Disease: #{c.name}"
  defp citation_text(_), do: "Reference"

  defp citation_url(%{reference_type: "study", study: %{pmid: pmid}}) when not is_nil(pmid),
    do: "https://pubmed.ncbi.nlm.nih.gov/#{pmid}"

  defp citation_url(_), do: nil

  defp display_name(profile), do: profile.display_name || "Nutritionist"

  # ── Render ───────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <article class="max-w-3xl mx-auto px-4 py-8">
      <nav class="text-sm text-parchment-dim mb-6">
        <.link navigate={~p"/nutritionists/#{@profile.slug}"} class="hover:text-parchment">
          ← {display_name(@profile)}
        </.link>
      </nav>

      <img
        :if={@article.cover_image_url}
        src={@article.cover_image_url}
        alt={@article.title}
        class="w-full max-h-80 object-cover rounded-xl mb-6"
      />

      <h1 class="text-3xl sm:text-4xl font-display font-bold text-parchment leading-tight">
        {@article.title}
      </h1>

      <p class="text-parchment-dim mt-3">
        By
        <.link navigate={~p"/nutritionists/#{@profile.slug}"} class="text-paprika hover:underline">
          {display_name(@profile)}
        </.link>
        <span :if={@article.published_at}>
          · <time datetime={iso8601(@article.published_at)}>
            {Calendar.strftime(@article.published_at, "%B %-d, %Y")}
          </time>
        </span>
      </p>

      <p :if={@article.summary} class="text-lg text-parchment-dim mt-4 italic">
        {@article.summary}
      </p>

      <div class="prose prose-invert max-w-none mt-8 space-y-8">
        <section :for={paragraph <- @article.paragraphs}>
          <h2 :if={paragraph.heading} class="text-xl font-display font-semibold text-parchment mb-2">
            {paragraph.heading}
          </h2>
          <p :if={paragraph.body} class="text-parchment whitespace-pre-line leading-relaxed">
            {paragraph.body}<span
              :for={ref <- paragraph.references}
              class="align-super text-xs text-paprika ml-0.5"
            ><a href={"#ref-#{ref_number(@references, ref)}"}>[{ref_number(@references, ref)}]</a></span>
          </p>
          <figure :if={paragraph.image_url} class="my-4">
            <img src={paragraph.image_url} alt={paragraph.image_caption} class="w-full rounded-lg" />
            <figcaption :if={paragraph.image_caption} class="text-parchment-dim text-sm mt-2 italic">
              {paragraph.image_caption}
            </figcaption>
          </figure>
        </section>
      </div>

      <!-- Bibliography -->
      <section :if={@references.list != []} class="mt-12 border-t border-ink-panel2 pt-6">
        <h2 class="text-lg font-display font-semibold text-parchment mb-4">References</h2>
        <ol class="space-y-2 text-sm text-parchment-dim">
          <li :for={ref <- @references.list} id={"ref-#{ref_number(@references, ref)}"} class="flex gap-2">
            <span class="text-paprika">{ref_number(@references, ref)}.</span>
            <span>
              <%= if citation_url(ref) do %>
                <a
                  href={citation_url(ref)}
                  target="_blank"
                  rel="noopener nofollow"
                  class="hover:text-parchment"
                >
                  {citation_text(ref)}
                </a>
              <% else %>
                {citation_text(ref)}
              <% end %>
            </span>
          </li>
        </ol>
      </section>
    </article>
    """
  end
end
