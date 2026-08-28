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

  alias Mehungry.Professionals
  alias Mehungry.ObanWorkers.AppointmentMailerWorker
  alias Mehungry.Users
  alias MehungryWeb.RecipeComponents

  @booking_window_days 30

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
         |> assign(:booking_window_days, @booking_window_days)
         |> assign(:must_be_loged_in, nil)
         |> assign(:created_recipes, Users.list_user_created_recipes(profile.user))
         |> assign(:articles, Professionals.list_published_articles_for_profile(profile.id))
         |> assign_viewer_recipe_state()
         |> reset_booking_state()
         |> load_slots()
         |> assign_seo(profile)}
    end
  end

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

  # ── Booking wizard: pick a day → pick a time → confirm → done ────────────────

  @impl true
  def handle_event("select_booking_date", %{"date" => iso}, socket) do
    case Date.from_iso8601(iso) do
      {:ok, date} ->
        {:noreply, socket |> assign(:booking_date, date) |> assign(:booking_slot, nil)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_booking_slot", %{"at" => iso}, socket) do
    case NaiveDateTime.from_iso8601(iso) do
      {:ok, at} -> {:noreply, assign(socket, :booking_slot, at)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("reset_booking", _params, socket) do
    {:noreply, reset_booking_state(socket)}
  end

  # Confirm: request the selected slot (the nutritionist must accept before it's
  # booked). Feedback stays inside the modal (a success screen) rather than a
  # flash the modal overlay would hide.
  def handle_event("confirm_booking", params, socket) do
    profile = socket.assigns.profile
    user = socket.assigns.current_user
    slot = socket.assigns.booking_slot

    cond do
      is_nil(user) ->
        {:noreply,
         socket
         |> put_flash(:error, "Please log in to request an appointment.")
         |> redirect(to: ~p"/users/log_in")}

      is_nil(slot) ->
        {:noreply, socket}

      true ->
        case Professionals.request_appointment(profile.user_id, user.id, slot,
               title: "Consultation with #{display_name(profile)}",
               notes: params["notes"]
             ) do
          {:ok, appt} ->
            AppointmentMailerWorker.enqueue("requested", appt.id, %{
              professional_name: display_name(profile),
              client_name: user.name || user.email,
              cta_url: url(~p"/nutritionist/appointments")
            })

            {:noreply,
             socket
             |> assign(:booking_status, :done)
             |> assign(:booked_slot, slot)
             |> assign(:booking_date, nil)
             |> assign(:booking_slot, nil)
             |> load_slots()}

          {:error, :slot_unavailable} ->
            {:noreply,
             socket
             |> assign(:booking_slot, nil)
             |> load_slots()
             |> put_flash(:error, "That slot was just taken — please pick another.")}

          _ ->
            {:noreply,
             put_flash(socket, :error, "Could not send your request. Please try again.")}
        end
    end
  end

  defp reset_booking_state(socket) do
    socket
    |> assign(:booking_date, nil)
    |> assign(:booking_slot, nil)
    |> assign(:booking_status, :idle)
    |> assign(:booked_slot, nil)
  end

  defp load_slots(socket) do
    profile = socket.assigns.profile
    today = Date.utc_today()

    slots_by_date =
      profile.user_id
      |> Professionals.available_slots(today, Date.add(today, @booking_window_days))
      |> Enum.group_by(&NaiveDateTime.to_date/1)
      |> Enum.sort_by(fn {date, _} -> date end, Date)

    assign(socket, :slots_by_date, slots_by_date)
  end

  # Slots for the currently selected day (from the grouped {date, slots} list).
  defp slots_for(_slots_by_date, nil), do: []

  defp slots_for(slots_by_date, date) do
    case List.keyfind(slots_by_date, date, 0) do
      {_date, slots} -> slots
      nil -> []
    end
  end

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
    assigns = assign(assigns, :day_slots, slots_for(assigns.slots_by_date, assigns.booking_date))

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
          <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 sticky top-4">
            <h2 class="font-display font-semibold text-parchment mb-1">Book a consultation</h2>
            <%= if @slots_by_date == [] do %>
              <p class="text-sm text-parchment-dim mt-2">
                No open times in the next {@booking_window_days} days. Please check back soon.
              </p>
            <% else %>
              <p class="text-xs text-parchment-dim mb-4">
                {display_name(@profile)} will confirm by email before it's booked.
              </p>
              <button
                type="button"
                phx-click={show_modal("book-appointment-modal")}
                class="w-full inline-flex items-center justify-center gap-1.5 py-2.5 px-4 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-medium text-sm transition"
              >
                <.icon name="hero-calendar-days" class="w-4 h-4 flex-none" /> Request an appointment
              </button>
              <p :if={is_nil(@current_user)} class="text-xs text-parchment-dim mt-3">
                You'll be asked to log in to confirm.
              </p>
            <% end %>
          </div>
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

      <.booking_modal
        profile={@profile}
        slots_by_date={@slots_by_date}
        day_slots={@day_slots}
        booking_window_days={@booking_window_days}
        booking_date={@booking_date}
        booking_slot={@booking_slot}
        booking_status={@booking_status}
        booked_slot={@booked_slot}
        current_user={@current_user}
      />

      <.modal
        :if={!is_nil(@must_be_loged_in)}
        id="nutritionist_must_be_login"
        show
        on_cancel={JS.push("keep_browsing")}
      >
        <.live_component module={MehungryWeb.MustBeLoginComponent} id={:new} patch={~p"/browse"} />
      </.modal>
    </div>
    """
  end

  # ── Booking wizard modal ─────────────────────────────────────────────────────

  attr :profile, :map, required: true
  attr :slots_by_date, :list, required: true
  attr :day_slots, :list, required: true
  attr :booking_window_days, :integer, required: true
  attr :booking_date, :any, default: nil
  attr :booking_slot, :any, default: nil
  attr :booking_status, :atom, default: :idle
  attr :booked_slot, :any, default: nil
  attr :current_user, :map, default: nil

  defp booking_modal(assigns) do
    ~H"""
    <.modal id="book-appointment-modal" show={false} on_cancel={JS.push("reset_booking")}>
      <div class="sm:min-w-[26rem]">
        <%= cond do %>
          <% @booking_status == :done -> %>
            <div class="text-center py-4">
              <div class="mx-auto w-14 h-14 rounded-full bg-basil/15 text-basil flex items-center justify-center mb-4">
                <.icon name="hero-check-circle" class="w-8 h-8" />
              </div>
              <h3 class="text-lg font-display font-semibold text-parchment mb-1">Request sent!</h3>
              <p class="text-sm text-parchment-dim">
                You asked to meet on
                <span class="text-parchment font-medium">
                  {Calendar.strftime(@booked_slot, "%A %b %-d at %H:%M")}
                </span>.
                {display_name(@profile)} will confirm by email — nothing is charged or final until
                they accept.
              </p>
              <div class="flex items-center justify-center gap-3 mt-6">
                <button
                  type="button"
                  phx-click="reset_booking"
                  class="px-4 py-2 rounded-lg border border-ink-panel2 text-parchment-dim hover:text-parchment text-sm transition"
                >
                  Book another time
                </button>
                <button
                  type="button"
                  phx-click={JS.push(hide_modal("book-appointment-modal"), "reset_booking")}
                  class="px-4 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-medium text-sm transition"
                >
                  Done
                </button>
              </div>
            </div>

          <% is_nil(@current_user) -> %>
            <h3 class="text-lg font-display font-semibold text-parchment mb-2">
              Request an appointment
            </h3>
            <p class="text-sm text-parchment-dim mb-5">
              Log in to request a time with {display_name(@profile)}.
            </p>
            <.link
              navigate={~p"/users/log_in"}
              class="inline-flex px-4 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-medium text-sm transition"
            >
              Log in to continue
            </.link>

          <% true -> %>
            <h3 class="text-lg font-display font-semibold text-parchment mb-1">
              Request an appointment
            </h3>
            <p class="text-sm text-parchment-dim mb-5">
              {display_name(@profile)} will confirm by email before it's booked.
            </p>

            <!-- Step 1 · day -->
            <p class="text-[11px] font-semibold text-parchment-dim uppercase tracking-wide mb-2">
              1 · Choose a day
            </p>
            <div class="flex gap-2 overflow-x-auto pb-2 m3-scrollbar mb-5">
              <button
                :for={{date, _slots} <- @slots_by_date}
                type="button"
                phx-click="select_booking_date"
                phx-value-date={Date.to_iso8601(date)}
                class={[
                  "flex-none w-16 py-2 rounded-lg border text-center transition",
                  if(@booking_date == date,
                    do: "border-paprika bg-paprika/10 text-paprika",
                    else:
                      "border-ink-panel2 text-parchment-dim hover:border-paprika/50 hover:text-parchment"
                  )
                ]}
              >
                <span class="block text-[10px] uppercase tracking-wide">
                  {Calendar.strftime(date, "%a")}
                </span>
                <span class="block text-sm font-semibold">{Calendar.strftime(date, "%-d")}</span>
                <span class="block text-[10px] text-parchment-dim">
                  {Calendar.strftime(date, "%b")}
                </span>
              </button>
            </div>

            <!-- Step 2 · time -->
            <div :if={@booking_date}>
              <p class="text-[11px] font-semibold text-parchment-dim uppercase tracking-wide mb-2">
                2 · Choose a time
              </p>
              <div class="flex flex-wrap gap-2 mb-5 max-h-40 overflow-y-auto m3-scrollbar">
                <button
                  :for={slot <- @day_slots}
                  type="button"
                  phx-click="select_booking_slot"
                  phx-value-at={NaiveDateTime.to_iso8601(slot)}
                  class={[
                    "px-3 py-1.5 rounded-md border text-sm transition",
                    if(@booking_slot == slot,
                      do: "border-paprika bg-paprika text-ink font-medium",
                      else: "border-paprika/40 text-paprika hover:bg-paprika/10"
                    )
                  ]}
                >
                  {Calendar.strftime(slot, "%H:%M")}
                </button>
              </div>
            </div>

            <!-- Step 3 · note + confirm -->
            <form
              :if={@booking_slot}
              phx-submit="confirm_booking"
              class="border-t border-ink-panel2 pt-4"
            >
              <label class="block text-[11px] font-semibold text-parchment-dim uppercase tracking-wide mb-2">
                3 · Add a note (optional)
              </label>
              <textarea
                name="notes"
                rows="2"
                class="w-full border border-ink-panel2 bg-ink-panel2 text-parchment rounded-lg px-2 py-1.5 text-sm mb-4 placeholder-parchment-dim focus:outline-none focus:border-paprika"
                placeholder="What would you like to discuss?"
              ></textarea>
              <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                <p class="text-sm text-parchment flex items-center gap-1.5">
                  <.icon name="hero-calendar-days" class="w-4 h-4 text-paprika flex-none" />
                  {Calendar.strftime(@booking_slot, "%A %b %-d, %H:%M")}
                </p>
                <button
                  type="submit"
                  class="px-5 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-medium text-sm transition"
                >
                  Confirm request
                </button>
              </div>
            </form>
        <% end %>
      </div>
    </.modal>
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
