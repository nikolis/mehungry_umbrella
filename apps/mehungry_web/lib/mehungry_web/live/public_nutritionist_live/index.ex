defmodule MehungryWeb.PublicNutritionistLive.Index do
  @moduledoc """
  Public, SEO-indexed nutritionist directory at `/nutritionists`. Lists
  published professional profiles and lets visitors filter by city and free
  text — the city filter drives local-intent queries like "nutritionist Rethymno".
  """
  use MehungryWeb, :live_view

  alias Mehungry.Professionals

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :cities, Professionals.list_professional_cities())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    city = blank_to_nil(params["city"])
    q = blank_to_nil(params["q"])
    profiles = Professionals.list_public_professionals(%{city: city, q: q})

    {:noreply,
     socket
     |> assign(:city, city)
     |> assign(:q, q)
     |> assign(:profiles, profiles)
     |> assign_seo(city, q, profiles)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    query =
      %{"city" => params["city"], "q" => params["q"]}
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
      |> URI.encode_query()

    to = if query == "", do: ~p"/nutritionists", else: ~p"/nutritionists?#{query}"
    {:noreply, push_patch(socket, to: to)}
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s), do: s

  defp assign_seo(socket, city, _q, profiles) do
    {title, description} =
      cond do
        city ->
          {"Nutritionists in #{city}",
           "Find qualified nutritionists and dietitians in #{city}. Browse profiles, specializations and book a consultation on M3Hungry."}

        true ->
          {"Find a Nutritionist",
           "Browse qualified nutritionists and dietitians by city and specialization, and book a consultation on M3Hungry."}
      end

    socket
    |> assign(:page_title, title)
    |> assign(:page_description, description)
    |> assign(:canonical_path, "/nutritionists")
    |> assign(:structured_data, [item_list_jsonld(profiles)])
  end

  defp item_list_jsonld(profiles) do
    %{
      "@type" => "ItemList",
      "itemListElement" =>
        profiles
        |> Enum.with_index(1)
        |> Enum.map(fn {p, i} ->
          %{
            "@type" => "ListItem",
            "position" => i,
            "url" => url(~p"/nutritionists/#{p.slug}"),
            "name" => p.display_name || p.specialization
          }
        end)
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto px-4 py-8">
      <h1 class="text-3xl font-display font-bold text-parchment mb-2">
        {(@city && "Nutritionists in #{@city}") || "Find a Nutritionist"}
      </h1>
      <p class="text-parchment-dim mb-6">
        Browse qualified nutritionists and dietitians and book a consultation.
      </p>

      <form phx-change="filter" phx-submit="filter" class="flex flex-wrap gap-3 mb-8">
        <select
          name="city"
          class="border border-ink-panel2 rounded-lg px-3 py-2 text-sm bg-ink-panel text-parchment focus:outline-none focus:border-paprika"
        >
          <option value="">All cities</option>
          <option :for={c <- @cities} value={c} selected={c == @city}>{c}</option>
        </select>
        <input
          type="text"
          name="q"
          value={@q}
          placeholder="Search name or specialization"
          class="flex-1 min-w-[12rem] border border-ink-panel2 rounded-lg px-3 py-2 text-sm bg-ink-panel text-parchment placeholder-parchment-dim focus:outline-none focus:border-paprika"
        />
      </form>

      <%= if @profiles == [] do %>
        <p class="text-parchment-dim">No nutritionists found. Try a different city or search.</p>
      <% else %>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
          <a
            :for={p <- @profiles}
            href={~p"/nutritionists/#{p.slug}"}
            class="block bg-ink-panel border border-ink-panel2 rounded-xl p-5 hover:border-paprika/40 transition"
          >
            <div class="flex items-center gap-3 mb-3">
              <img
                :if={p.photo_url}
                src={p.photo_url}
                alt={p.display_name}
                class="w-14 h-14 rounded-full object-cover"
              />
              <div
                :if={is_nil(p.photo_url)}
                class="w-14 h-14 rounded-full bg-paprika/10 text-paprika flex items-center justify-center font-bold text-lg"
              >
                {String.first(p.display_name || "N")}
              </div>
              <div class="min-w-0">
                <p class="font-semibold text-parchment truncate">{p.display_name}</p>
                <p class="text-sm text-parchment-dim truncate">{p.specialization}</p>
              </div>
            </div>
            <p :if={p.city} class="text-sm text-parchment-dim">📍 {p.city}</p>
            <p :if={p.bio} class="text-sm text-parchment-dim mt-2 line-clamp-3">{p.bio}</p>
          </a>
        </div>
      <% end %>
    </div>
    """
  end
end
