defmodule MehungryWeb.PublicNutritionistLive.Show do
  @moduledoc """
  Public nutritionist profile at `/nutritionists/:slug`. The profile body is
  rendered synchronously so the disconnected ("dead") render Googlebot indexes
  carries the full bio, city and `LocalBusiness`/`Person` JSON-LD (local intent,
  e.g. "nutritionist Rethymno"). Logged-in visitors can request an open slot from
  the nutritionist's weekly availability; the nutritionist must accept before
  anything is confirmed.
  """
  use MehungryWeb, :live_view

  # Recipe save/follow/comment handlers for the created-recipes grid + reused
  # elsewhere via the RecipeDetailsComponent.
  use MehungryWeb.LiveHelpers, :hook_for_update_recipe_details_component

  alias Mehungry.MealBlueprints
  alias Mehungry.Professionals
  alias Mehungry.Users
  alias MehungryWeb.RecipeComponents

  import MehungryWeb.BlueprintComponents, only: [blueprint_card: 1]

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Professionals.get_public_professional_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/nutritionists")}

      profile ->
        {:ok,
         socket
         # Logged-out visitors have no :current_user assigned by MaybeUserAuthLive.
         |> assign_new(:current_user, fn -> nil end)
         |> assign(:profile, profile)
         |> assign(:must_be_loged_in, nil)
         |> assign(:created_recipes, Users.list_user_created_recipes(profile.user))
         |> assign(:articles, Professionals.list_published_articles_for_profile(profile.id))
         |> assign(
           :blueprints,
           profile.user_id
           |> MealBlueprints.list_public_blueprints_for_user()
           |> MealBlueprints.localize_blueprints(Gettext.get_locale(MehungryWeb.Gettext))
         )
         |> assign_viewer_recipe_state()
         |> assign(:payments_enabled, Professionals.consultation_payments_enabled?())
         |> assign_seo(profile)}
    end
  end

  # Flash on return from Stripe Checkout (success/cancel URLs point back here).
  @impl true
  def handle_params(%{"booking" => "success"}, _uri, socket) do
    {:noreply,
     put_flash(
       socket,
       :info,
       "Your card is on hold — #{display_name(socket.assigns.profile)} will confirm by email. You're only charged once they accept."
     )}
  end

  def handle_params(%{"booking" => "cancelled"}, _uri, socket) do
    {:noreply, put_flash(socket, :error, "Payment was not completed, so no time was requested.")}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # The signed-in viewer's saved-recipe ids + follows drive the recipe cards'
  # save button state (the hook's save_user_recipe reads current_user_recipes).
  defp assign_viewer_recipe_state(%{assigns: %{current_user: nil}} = socket) do
    socket
    |> assign(:user_recipes, [])
    |> assign(:current_user_recipes, [])
    |> assign(:current_user_follows, [])
  end

  defp assign_viewer_recipe_state(%{assigns: %{current_user: user}} = socket) do
    saved = Users.list_user_saved_recipe_ids(user)
    follows = user |> Users.list_user_follows() |> Enum.map(& &1.follow_id)

    socket
    |> assign(:user_recipes, saved)
    |> assign(:current_user_recipes, saved)
    |> assign(:current_user_follows, follows)
  end

  @impl true
  def handle_event("keep_browsing", _params, socket) do
    {:noreply, assign(socket, :must_be_loged_in, nil)}
  end

  # The booking component fires this after a request-only booking succeeds; it
  # reloads its own slots, so nothing further is needed on the public page.
  @impl true
  def handle_info({:appointment_booked, _appt}, socket), do: {:noreply, socket}

  defp display_name(profile), do: profile.display_name || profile.specialization || "Nutritionist"

  # ── SEO ────────────────────────────────────────────────────────────────────

  defp assign_seo(socket, profile) do
    title =
      if profile.city,
        do: "#{display_name(profile)} — Nutritionist in #{profile.city}",
        else: "#{display_name(profile)} — Nutritionist"

    description =
      (profile.bio || "#{display_name(profile)}, #{profile.specialization}")
      |> String.slice(0, 155)

    socket
    |> assign(:page_title, title)
    |> assign(:page_description, description)
    |> assign(:canonical_path, "/nutritionists/#{profile.slug}")
    |> assign(:structured_data, structured_data(profile))
  end

  defp structured_data(profile) do
    canonical = url(~p"/nutritionists/#{profile.slug}")

    business =
      %{
        "@type" => "LocalBusiness",
        "name" => display_name(profile),
        "description" => profile.bio,
        "url" => canonical,
        "image" => profile.photo_url,
        "telephone" => profile.phone,
        "email" => profile.contact_email,
        "areaServed" => profile.city,
        "knowsAbout" => profile.specialization,
        "address" => postal_address(profile)
      }
      |> compact()

    person =
      %{
        "@type" => "Person",
        "name" => display_name(profile),
        "jobTitle" => profile.specialization,
        "url" => canonical,
        "image" => profile.photo_url,
        "worksFor" => %{"@type" => "Organization", "name" => "M3Hungry"}
      }
      |> compact()

    [business, person]
  end

  defp postal_address(profile) do
    %{
      "@type" => "PostalAddress",
      "streetAddress" => profile.office_address,
      "addressLocality" => profile.city,
      "addressRegion" => profile.region
    }
    |> compact()
  end

  defp compact(map) do
    map
    |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
    |> Map.new()
  end

  # ── Render ─────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <!-- Header -->
      <div class="flex flex-col sm:flex-row gap-6 items-start mb-8">
        <img
          :if={@profile.photo_url}
          src={@profile.photo_url}
          alt={display_name(@profile)}
          class="w-28 h-28 rounded-full object-cover"
        />
        <div
          :if={is_nil(@profile.photo_url)}
          class="w-28 h-28 rounded-full bg-paprika/10 text-paprika flex items-center justify-center font-bold text-3xl"
        >
          {String.first(display_name(@profile))}
        </div>
        <div class="flex-1">
          <h1 class="text-3xl font-display font-bold text-parchment">{display_name(@profile)}</h1>
          <p class="text-lg text-parchment-dim">{@profile.specialization}</p>
          <p :if={@profile.city} class="text-parchment-dim mt-1">
            📍 {[@profile.city, @profile.region] |> Enum.reject(&is_nil/1) |> Enum.join(", ")}
          </p>
          <div class="flex flex-wrap gap-4 mt-3 text-sm">
            <a
              :if={@profile.phone}
              href={"tel:#{@profile.phone}"}
              class="text-paprika hover:underline"
            >{@profile.phone}</a>
            <a
              :if={@profile.contact_email}
              href={"mailto:#{@profile.contact_email}"}
              class="text-paprika hover:underline"
            >{@profile.contact_email}</a>
            <a
              :if={@profile.website_url}
              href={@profile.website_url}
              rel="noopener"
              target="_blank"
              class="text-paprika hover:underline"
            >Website</a>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <!-- Details -->
        <div class="lg:col-span-2 space-y-6">
          <.detail_section :if={@profile.bio} title="About">{@profile.bio}</.detail_section>
          <.detail_section :if={@profile.education} title="Education">
            {@profile.education}
          </.detail_section>
          <.detail_section :if={@profile.professional_achievements} title="Professional achievements">
            {@profile.professional_achievements}
          </.detail_section>
          <.detail_section :if={@profile.scientific_contributions} title="Scientific contributions">
            {@profile.scientific_contributions}
          </.detail_section>
          <p :if={@profile.office_address} class="text-sm text-parchment-dim">
            Office: {@profile.office_address}
          </p>
        </div>

        <!-- Booking -->
        <div class="lg:col-span-1">
          <.live_component
            module={MehungryWeb.AppointmentBookingComponent}
            id="public-profile-booking"
            variant={:card}
            profile={@profile}
            current_user={@current_user}
            payments_enabled={@payments_enabled}
            return_path={~p"/nutritionists/#{@profile.slug}"}
          />
        </div>
      </div>

      <!-- Articles by this nutritionist -->
      <section :if={@articles != []} class="mt-12">
        <h2 class="text-2xl font-display font-bold text-parchment mb-6">
          Articles by {display_name(@profile)}
        </h2>
        <ul class="space-y-3">
          <li
            :for={article <- @articles}
            class="bg-ink-panel border border-ink-panel2 rounded-xl p-4 hover:border-paprika transition"
          >
            <a href={~p"/nutritionists/#{@profile.slug}/articles/#{article.slug}"} class="block">
              <h3 class="font-display font-semibold text-parchment">{article.title}</h3>
              <p :if={article.summary} class="text-parchment-dim text-sm mt-1">{article.summary}</p>
            </a>
          </li>
        </ul>
      </section>

      <!-- Meal blueprints published by this nutritionist -->
      <section :if={@blueprints != []} class="mt-12">
        <h2 class="text-2xl font-display font-bold text-parchment mb-6">
          Meal blueprints by {display_name(@profile)}
        </h2>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          <.blueprint_card :for={bp <- @blueprints} blueprint={bp} />
        </div>
      </section>

      <!-- Recipes created by this nutritionist -->
      <section :if={@created_recipes != []} class="mt-12">
        <h2 class="text-2xl font-display font-bold text-parchment mb-6">
          Recipes by {display_name(@profile)}
        </h2>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          <RecipeComponents.recipe_card
            :for={recipe <- @created_recipes}
            recipe={recipe}
            type="browse"
            user_recipes={@user_recipes}
            navigate_details={true}
            path_to_details={~p"/browse/#{recipe.id}"}
            id={"recipe" <> Integer.to_string(recipe.id)}
          />
        </div>
      </section>

      <.modal
        :if={!is_nil(@must_be_loged_in)}
        id="nutritionist_must_be_login"
        show
        on_cancel={JS.push("keep_browsing")}
      >
        <.live_component module={MehungryWeb.MustBeLoginComponent} id={:new} patch={~p"/browse"} />
      </.modal>

      <.nutritionist_recruit_cta current_user={@current_user} variant={:banner} />
    </div>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp detail_section(assigns) do
    ~H"""
    <section>
      <h2 class="font-display font-semibold text-parchment mb-1">{@title}</h2>
      <p class="text-parchment-dim whitespace-pre-line">{render_slot(@inner_block)}</p>
    </section>
    """
  end
end
