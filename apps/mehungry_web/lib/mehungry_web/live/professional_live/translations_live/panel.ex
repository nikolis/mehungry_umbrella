defmodule MehungryWeb.ProfessionalLive.TranslationsLive.Panel do
  @moduledoc """
  Generic per-resource translation panel, driven by a
  `Mehungry.Languages.TranslationRegistry` descriptor. Two modes:

    * `:index` — a filterable list (missing / draft / verified) of a resource's
      rows, with per-row AI-translate/verify and a bulk "AI-translate all missing".
    * `:show`  — a per-item editor: original vs. editable translation, a
      human-triggered "AI Translate", and "Save & Verify" (mirrors the recipe
      translate UX).
  """
  use MehungryWeb, :live_view

  alias Mehungry.AI.{FieldTranslator, RecipeTranslator}
  alias Mehungry.Languages.{Locale, Translations, TranslationRegistry}
  alias Mehungry.ObanWorkers.ResourceTranslationWorker

  @per_page 25

  defp per_page, do: @per_page

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :translating, false)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    case TranslationRegistry.get(params["resource"]) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Unknown resource")
         |> push_navigate(to: ~p"/professional/translations")}

      descriptor ->
        locale = params["lang"] || hd(Locale.targets())

        socket =
          socket
          |> assign(:descriptor, descriptor)
          |> assign(:locale, locale)

        {:noreply, apply_action(socket, socket.assigns.live_action, params)}
    end
  end

  defp apply_action(socket, :index, params) do
    descriptor = socket.assigns.descriptor
    locale = socket.assigns.locale
    filter = parse_filter(params["filter"])
    page = parse_page(params["page"])

    items =
      Translations.list_items(descriptor, locale,
        filter: filter,
        limit: @per_page,
        offset: (page - 1) * @per_page
      )

    counts = %{
      missing: Translations.count_items(descriptor, locale, :missing),
      ai_draft: Translations.count_items(descriptor, locale, :ai_draft),
      verified: Translations.count_items(descriptor, locale, :verified)
    }

    socket
    |> assign(:page_title, "Translate: #{descriptor.label}")
    |> assign(:filter, filter)
    |> assign(:page, page)
    |> assign(:counts, counts)
    |> assign(:items, items)
  end

  defp apply_action(socket, :show, params) do
    descriptor = socket.assigns.descriptor
    locale = socket.assigns.locale
    pair = Translations.get_pair(descriptor, String.to_integer(params["id"]), locale)

    socket
    |> assign(:page_title, "Translate: #{item_title(descriptor, pair.base)}")
    |> assign(:base, pair.base)
    |> assign(:translation, pair.translation)
    |> assign(:draft, draft_from(descriptor, pair.translation))
    |> assign(:translating, false)
  end

  # ── Events: list ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/professional/translations/#{socket.assigns.descriptor.key}?filter=#{filter}"
     )}
  end

  @impl true
  def handle_event("ai_all", _params, socket) do
    %{descriptor: descriptor, locale: locale} = socket.assigns
    ids = Translations.missing_ids(descriptor, locale)

    case ResourceTranslationWorker.enqueue_all(descriptor.key, locale, ids) do
      {:ok, 0} ->
        {:noreply, put_flash(socket, :info, "Nothing missing — all rows already translated.")}

      {:ok, jobs} ->
        {:noreply,
         put_flash(
           socket,
           :info,
           "Queued AI translation of #{length(ids)} item(s) in #{jobs} batch(es). Drafts appear here as they finish."
         )}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not queue translation jobs.")}
    end
  end

  @impl true
  def handle_event("verify", %{"id" => id}, socket) do
    %{descriptor: descriptor, locale: locale, current_user: user} = socket.assigns

    case Translations.verify(descriptor, String.to_integer(id), locale, verified_by_id: user.id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Marked verified.")
         |> refresh_list()}

      _ ->
        {:noreply, put_flash(socket, :error, "Nothing to verify yet — translate it first.")}
    end
  end

  # ── Events: per-item editor ───────────────────────────────────────────────

  @impl true
  def handle_event("ai_translate", _params, socket) do
    send(self(), :do_translate)
    {:noreply, assign(socket, :translating, true)}
  end

  @impl true
  def handle_event("save", %{"fields" => fields}, socket) do
    %{descriptor: descriptor, base: base, locale: locale, current_user: user} = socket.assigns

    field_values =
      Map.new(descriptor.fields, fn field ->
        {field, Map.get(fields, Atom.to_string(field))}
      end)

    case Translations.upsert(descriptor, base.id, locale, field_values,
           status: "verified",
           verified_by_id: user.id
         ) do
      {:ok, translation} ->
        {:noreply,
         socket
         |> assign(:translation, translation)
         |> assign(:draft, draft_from(descriptor, translation))
         |> put_flash(:info, "Saved & verified.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not save translation.")}
    end
  end

  @impl true
  def handle_info(:do_translate, socket) do
    %{descriptor: descriptor, base: base, locale: locale} = socket.assigns

    case run_ai(descriptor, base, locale) do
      {:ok, values} ->
        {:noreply,
         socket
         |> assign(:draft, Map.merge(socket.assigns.draft, values))
         |> assign(:translating, false)
         |> put_flash(:info, "AI translation loaded — review and save.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:translating, false)
         |> put_flash(:error, "Translation failed: #{inspect(reason)}")}
    end
  end

  defp run_ai(%{ai: :recipe}, base, locale) do
    case RecipeTranslator.translate_recipe(base, Locale.write_code(locale)) do
      {:ok, %{title: title, description: description}} ->
        {:ok, %{title: title, description: description}}

      error ->
        error
    end
  end

  defp run_ai(%{ai: :fields} = descriptor, base, locale) do
    field_values = Map.new(descriptor.fields, fn f -> {f, Map.get(base, f)} end)
    FieldTranslator.translate_fields(field_values, locale, hint: descriptor.ai_hint)
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp refresh_list(socket) do
    assign(socket, apply_list_assigns(socket))
  end

  defp apply_list_assigns(socket) do
    %{descriptor: descriptor, locale: locale, filter: filter, page: page} = socket.assigns

    items =
      Translations.list_items(descriptor, locale,
        filter: filter,
        limit: @per_page,
        offset: (page - 1) * @per_page
      )

    counts = %{
      missing: Translations.count_items(descriptor, locale, :missing),
      ai_draft: Translations.count_items(descriptor, locale, :ai_draft),
      verified: Translations.count_items(descriptor, locale, :verified)
    }

    %{items: items, counts: counts}
  end

  defp draft_from(_descriptor, nil), do: %{}

  defp draft_from(descriptor, translation) do
    Map.new(descriptor.fields, fn field -> {field, Map.get(translation, field) || ""} end)
  end

  defp item_title(descriptor, base), do: Map.get(base, descriptor.name_field) || "##{base.id}"

  defp status_of(nil), do: :missing
  defp status_of(%{status: "verified"}), do: :verified
  defp status_of(_), do: :ai_draft

  defp parse_filter(f) when f in ~w(missing ai_draft verified all),
    do: String.to_existing_atom(f)

  defp parse_filter(_), do: :missing

  defp parse_page(p) do
    case Integer.parse(to_string(p)) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  # ── Render ─────────────────────────────────────────────────────────────────

  @impl true
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto">
      <.panel_header descriptor={@descriptor} locale={@locale} />

      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center gap-1.5">
          <.filter_tab filter={@filter} value={:missing} label="Missing" count={@counts.missing} />
          <.filter_tab filter={@filter} value={:ai_draft} label="AI draft" count={@counts.ai_draft} />
          <.filter_tab filter={@filter} value={:verified} label="Verified" count={@counts.verified} />
          <.filter_tab filter={@filter} value={:all} label="All" count={nil} />
        </div>
        <button
          phx-click="ai_all"
          data-confirm={"Queue AI translation for all #{@counts.missing} missing #{@descriptor.label}? Each becomes an unverified draft."}
          class="flex items-center gap-1.5 px-3 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium transition-colors disabled:opacity-40"
          disabled={@counts.missing == 0}
        >
          <.icon name="hero-cpu-chip" class="h-4 w-4" /> AI-translate all missing
        </button>
      </div>

      <div class="bg-slate-800 border border-slate-700/60 rounded-xl divide-y divide-slate-700/50">
        <%= if @items == [] do %>
          <div class="p-6 text-center text-sm text-slate-500">Nothing here.</div>
        <% end %>
        <%= for item <- @items do %>
          <div class="flex items-center gap-3 px-4 py-2.5">
            <.status_dot status={status_of(item.translation)} />
            <div class="flex-1 min-w-0">
              <div class="text-sm text-slate-200 truncate">
                {Map.get(item.base, @descriptor.name_field)}
              </div>
              <%= if item.translation && translation_preview(@descriptor, item.translation) do %>
                <div class="text-xs text-slate-400 truncate">
                  → {translation_preview(@descriptor, item.translation)}
                </div>
              <% end %>
            </div>
            <div class="flex items-center gap-1.5">
              <.link
                navigate={~p"/professional/translations/#{@descriptor.key}/#{item.base.id}"}
                class="px-2.5 py-1.5 rounded-lg bg-slate-700 hover:bg-slate-600 text-slate-200 text-xs transition-colors"
              >
                Edit
              </.link>
              <%= if status_of(item.translation) == :ai_draft do %>
                <button
                  phx-click="verify"
                  phx-value-id={item.base.id}
                  class="px-2.5 py-1.5 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white text-xs transition-colors"
                >
                  Verify
                </button>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>

      <.pager
        :if={@items != []}
        key={@descriptor.key}
        filter={@filter}
        page={@page}
        last?={length(@items) < per_page()}
      />
    </div>
    """
  end

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <div class="flex items-center gap-3 mb-5">
        <.link
          navigate={~p"/professional/translations/#{@descriptor.key}"}
          class="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition-colors"
        >
          <.icon name="hero-arrow-left" class="h-5 w-5" />
        </.link>
        <div class="flex-1 flex items-center gap-2">
          <span class="inline-flex items-center px-2 py-0.5 rounded-md bg-slate-700 text-slate-300 text-xs font-semibold uppercase">
            {Locale.source()}
          </span>
          <.icon name="hero-arrow-right" class="h-3.5 w-3.5 text-slate-500" />
          <span class="inline-flex items-center px-2 py-0.5 rounded-md bg-primary-600/30 text-primary-300 text-xs font-semibold uppercase border border-primary-500/30">
            {@locale}
          </span>
          <h1 class="text-base font-semibold text-white ml-1 truncate">
            {item_title(@descriptor, @base)}
          </h1>
          <.status_dot status={status_of(@translation)} />
        </div>
        <button
          phx-click="ai_translate"
          disabled={@translating}
          class="flex items-center gap-1.5 px-3 py-2 rounded-lg bg-slate-800 hover:bg-slate-700 border border-slate-700/60 text-slate-300 hover:text-white text-sm transition-colors disabled:opacity-50"
        >
          <%= if @translating do %>
            <svg class="animate-spin h-4 w-4" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
            </svg>
            Translating…
          <% else %>
            <.icon name="hero-cpu-chip" class="h-4 w-4" /> AI Translate
          <% end %>
        </button>
      </div>

      <form phx-submit="save" class="grid grid-cols-2 gap-5">
        <div class="space-y-3">
          <div class="text-xs font-semibold text-slate-500 uppercase tracking-wider">
            Original ({Locale.source()})
          </div>
          <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4 space-y-3">
            <%= for field <- @descriptor.fields do %>
              <div>
                <label class="block text-xs text-slate-500 mb-1">{field_label(field)}</label>
                <div class="text-sm text-slate-200 whitespace-pre-wrap">
                  {Map.get(@base, field) || "—"}
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <div class="space-y-3">
          <div class="text-xs font-semibold text-slate-500 uppercase tracking-wider">
            Translation ({@locale})
          </div>
          <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4 space-y-3">
            <%= for field <- @descriptor.fields do %>
              <div>
                <label class="block text-xs text-slate-500 mb-1">{field_label(field)}</label>
                <textarea
                  name={"fields[#{field}]"}
                  rows={textarea_rows(field)}
                  class="w-full bg-slate-700 border border-slate-600 rounded-lg text-slate-200 text-sm px-3 py-2 focus:border-primary-500 focus:outline-none resize-none"
                ><%= Map.get(@draft, field) %></textarea>
              </div>
            <% end %>
          </div>
          <button
            type="submit"
            class="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium transition-colors"
          >
            <.icon name="hero-check-badge" class="h-4 w-4" /> Save &amp; Verify
          </button>
        </div>
      </form>
    </div>
    """
  end

  # ── Function components ─────────────────────────────────────────────────────

  defp panel_header(assigns) do
    ~H"""
    <div class="flex items-center gap-3 mb-5">
      <.link
        navigate={~p"/professional/translations"}
        class="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition-colors"
      >
        <.icon name="hero-arrow-left" class="h-5 w-5" />
      </.link>
      <h1 class="text-lg font-semibold text-white flex items-center gap-2">
        {@descriptor.label}
        <span class="inline-flex items-center px-1.5 py-0.5 rounded bg-primary-600/30 text-primary-300 border border-primary-500/30 text-[10px] font-bold uppercase">
          {@locale}
        </span>
      </h1>
    </div>
    """
  end

  attr :filter, :atom, required: true
  attr :value, :atom, required: true
  attr :label, :string, required: true
  attr :count, :any, default: nil

  defp filter_tab(assigns) do
    ~H"""
    <button
      phx-click="filter"
      phx-value-filter={@value}
      class={[
        "px-3 py-1.5 rounded-lg text-xs font-medium transition-colors",
        @filter == @value && "bg-slate-700 text-white",
        @filter != @value && "text-slate-400 hover:text-slate-200 hover:bg-slate-800"
      ]}
    >
      {@label}<span :if={@count} class="ml-1 text-slate-500">{@count}</span>
    </button>
    """
  end

  attr :status, :atom, required: true

  defp status_dot(assigns) do
    ~H"""
    <span
      class={[
        "inline-block w-2 h-2 rounded-full flex-shrink-0",
        @status == :verified && "bg-emerald-500",
        @status == :ai_draft && "bg-amber-400",
        @status == :missing && "bg-slate-600"
      ]}
      title={to_string(@status)}
    />
    """
  end

  attr :key, :string, required: true
  attr :filter, :atom, required: true
  attr :page, :integer, required: true
  attr :last?, :boolean, required: true

  defp pager(assigns) do
    ~H"""
    <div class="flex items-center justify-between mt-4">
      <.link
        :if={@page > 1}
        patch={~p"/professional/translations/#{@key}?filter=#{@filter}&page=#{@page - 1}"}
        class="px-3 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 text-xs"
      >
        ← Prev
      </.link>
      <span class="text-xs text-slate-500">Page {@page}</span>
      <.link
        :if={not @last?}
        patch={~p"/professional/translations/#{@key}?filter=#{@filter}&page=#{@page + 1}"}
        class="px-3 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 text-xs ml-auto"
      >
        Next →
      </.link>
    </div>
    """
  end

  defp translation_preview(descriptor, translation) do
    Map.get(translation, descriptor.name_field) || Map.get(translation, hd(descriptor.fields))
  end

  defp field_label(field) do
    field |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  defp textarea_rows(field) when field in [:description, :ingredients_text], do: "5"
  defp textarea_rows(_field), do: "2"
end
