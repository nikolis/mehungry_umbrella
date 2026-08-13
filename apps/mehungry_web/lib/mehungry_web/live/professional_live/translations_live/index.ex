defmodule MehungryWeb.ProfessionalLive.TranslationsLive.Index do
  @moduledoc """
  Translation coverage hub. Shows, for every user-facing DB resource, how
  translated it is in each target language (verified / ai-draft / missing), and
  links to each resource's translation panel.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Languages.{Coverage, Locale}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Translations")
     |> assign(:targets, Locale.targets())
     |> assign(:rows, Coverage.stats())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto">
      <div class="mb-6">
        <h1 class="text-xl font-semibold text-white flex items-center gap-2">
          <.icon name="hero-language" class="h-6 w-6 text-primary-400" /> Translation Coverage
        </h1>
        <p class="text-sm text-slate-400 mt-1">
          Every DB resource shown to users, and how much of it is translated per language.
          AI drafts the translation; a human verifies it.
        </p>
      </div>

      <div class="space-y-3">
        <%= for {label, rows} <- Enum.group_by(@rows, & &1.label) |> Enum.sort_by(fn {_l, [r | _]} -> r.pct end) do %>
          <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-4">
            <div class="flex items-center justify-between mb-3">
              <div class="flex items-center gap-2">
                <span class="font-semibold text-white text-sm">{label}</span>
                <span class="text-xs text-slate-500">{hd(rows).total} items</span>
              </div>
              <.link
                navigate={~p"/professional/translations/#{hd(rows).key}"}
                class="text-xs text-primary-400 hover:text-primary-300 flex items-center gap-1"
              >
                Open panel <.icon name="hero-arrow-right" class="h-3.5 w-3.5" />
              </.link>
            </div>

            <div class="space-y-2">
              <%= for row <- Enum.sort_by(rows, & &1.language) do %>
                <div class="flex items-center gap-3">
                  <span class="inline-flex items-center justify-center w-9 px-1.5 py-0.5 rounded bg-slate-700 text-slate-300 text-[10px] font-bold uppercase">
                    {row.language}
                  </span>
                  <div class="flex-1">
                    <.coverage_bar row={row} />
                  </div>
                  <span class="w-12 text-right text-sm font-semibold text-white tabular-nums">
                    {row.pct}%
                  </span>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # A three-segment bar: verified (green) · ai-draft (amber) · missing (slate).
  defp coverage_bar(assigns) do
    total = max(assigns.row.total, 1)
    assigns = assign(assigns, :total, total)

    ~H"""
    <div
      class="flex h-2.5 w-full rounded-full overflow-hidden bg-slate-700"
      title={"verified #{@row.verified} · draft #{@row.ai_draft} · missing #{@row.missing}"}
    >
      <div class="bg-emerald-500 h-full" style={"width: #{pct(@row.verified, @total)}%"}></div>
      <div class="bg-amber-400 h-full" style={"width: #{pct(@row.ai_draft, @total)}%"}></div>
    </div>
    """
  end

  defp pct(_n, 0), do: 0
  defp pct(n, total), do: n * 100 / total
end
