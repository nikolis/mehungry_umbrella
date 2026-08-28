defmodule MehungryWeb.NutritionistLive.ProfileEdit do
  @moduledoc """
  The nutritionist's own profile editor: public-facing details, a photo, the
  publish toggle, a recurring weekly availability grid, and Stripe Connect
  onboarding for payouts.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Professionals
  alias Mehungry.Professionals.ProfessionalProfile
  alias Mehungry.Billing.StripeHandler
  alias MehungryWeb.SimpleS3Upload

  # Rendered order (Mon → Sun) mapped to stored day_of_week (0 = Sunday).
  @weekdays [
    {1, "Monday"},
    {2, "Tuesday"},
    {3, "Wednesday"},
    {4, "Thursday"},
    {5, "Friday"},
    {6, "Saturday"},
    {0, "Sunday"}
  ]

  # ═══════════════════════════════════════════════════════════════════════════
  # Update (mount / events)
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user

    profile =
      Professionals.get_professional_profile(user.id) || %ProfessionalProfile{user_id: user.id}

    socket =
      socket
      |> assign(:page_title, "My Professional Profile")
      |> assign(:profile, profile)
      |> assign(
        :changeset,
        Professionals.change_professional_profile(profile, %{user_id: user.id})
      )
      |> assign(:availability, availability_model(user.id))
      |> assign(:weekdays, @weekdays)
      |> assign(:time_options, time_options())
      |> maybe_sync_stripe(profile, params)
      |> allow_upload(:photo,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 5_000_000,
        external: &presign_upload/2
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"professional_profile" => params}, socket) do
    changeset =
      socket.assigns.profile
      |> Professionals.change_professional_profile(with_user_id(params, socket))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_event("save", %{"professional_profile" => params} = all, socket) do
    user = socket.assigns.current_user
    attrs = with_user_id(params, socket) |> maybe_put_photo(socket)

    result =
      case socket.assigns.profile do
        %ProfessionalProfile{id: nil} -> Professionals.create_professional_profile(attrs)
        profile -> Professionals.update_professional_profile(profile, attrs)
      end

    case result do
      {:ok, profile} ->
        Professionals.replace_availabilities(
          user.id,
          availability_rows(all["availability"] || %{})
        )

        {:noreply,
         socket
         |> assign(:profile, profile)
         |> assign(:changeset, Professionals.change_professional_profile(profile))
         |> assign(:availability, availability_model(user.id))
         |> put_flash(:info, profile_saved_flash(profile))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:changeset, Map.put(changeset, :action, :insert))
         |> put_flash(:error, "Please fix the errors below.")}
    end
  end

  @impl true
  def handle_event("connect_stripe", _params, socket) do
    user = socket.assigns.current_user
    profile = socket.assigns.profile

    with {:ok, account_id} <- ensure_stripe_account(profile, user),
         {:ok, url} <-
           StripeHandler.create_account_link(
             account_id,
             url(~p"/nutritionist/profile?stripe=refresh"),
             url(~p"/nutritionist/profile?stripe=return")
           ) do
      {:noreply, redirect(socket, external: url)}
    else
      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Could not start payout onboarding: #{inspect(reason)}")}
    end
  end

  # Create the Connect account on first use and persist its id.
  defp ensure_stripe_account(%{stripe_connect_account_id: id} = _p, _user)
       when is_binary(id) and id != "",
       do: {:ok, id}

  defp ensure_stripe_account(profile, user) do
    with {:ok, account_id} <- StripeHandler.create_connect_account(user.email),
         {:ok, _} <-
           Professionals.update_professional_stripe(profile, %{
             stripe_connect_account_id: account_id
           }) do
      {:ok, account_id}
    end
  end

  # After Stripe redirects back, refresh charges_enabled from the API.
  defp maybe_sync_stripe(socket, %{stripe_connect_account_id: id} = profile, %{
         "stripe" => "return"
       })
       when is_binary(id) and id != "" do
    case StripeHandler.get_connect_account(id) do
      {:ok, %{charges_enabled: enabled}} ->
        {:ok, updated} =
          Professionals.update_professional_stripe(profile, %{stripe_charges_enabled: enabled})

        assign(socket, :profile, updated)

      _ ->
        socket
    end
  end

  defp maybe_sync_stripe(socket, _profile, _params), do: socket

  defp with_user_id(params, socket),
    do: Map.put(params, "user_id", socket.assigns.current_user.id)

  defp maybe_put_photo(attrs, socket) do
    case consume_uploaded_entries(socket, :photo, fn %{url: url, key: key}, _entry ->
           {:ok, url <> "/" <> key}
         end) do
      [photo_url | _] -> Map.put(attrs, "photo_url", photo_url)
      [] -> attrs
    end
  end

  defp presign_upload(entry, socket) do
    {:ok, SimpleS3Upload.meta_for(entry, 5_000_000, "profile_photos"), socket}
  end

  defp profile_saved_flash(%{is_public: true, slug: slug}) when is_binary(slug),
    do: "Profile saved and published at /nutritionists/#{slug}."

  defp profile_saved_flash(_), do: "Profile saved."

  # Build a dow => %{start, end} map for the form from stored availability rows
  # (first window per day; the editor supports one window per day).
  defp availability_model(user_id) do
    user_id
    |> Professionals.list_availabilities()
    |> Enum.reduce(%{}, fn a, acc ->
      Map.put_new(acc, a.day_of_week, %{
        start: Calendar.strftime(a.start_time, "%H:%M"),
        end: Calendar.strftime(a.end_time, "%H:%M")
      })
    end)
  end

  # Turn submitted availability params into changeset rows (enabled days only).
  # Unchecked days omit "enabled" but still submit start/end, so match loosely.
  defp availability_rows(availability_params) when is_map(availability_params) do
    Enum.flat_map(availability_params, fn {dow_str, row} ->
      with "true" <- Map.get(row, "enabled"),
           {:ok, start_time} <- parse_time(Map.get(row, "start")),
           {:ok, end_time} <- parse_time(Map.get(row, "end")) do
        [%{day_of_week: String.to_integer(dow_str), start_time: start_time, end_time: end_time}]
      else
        _ -> []
      end
    end)
  end

  defp availability_rows(_), do: []

  defp parse_time(nil), do: :error
  defp parse_time(""), do: :error
  defp parse_time(hhmm), do: Time.from_iso8601(hhmm <> ":00")

  # "HH:MM" options at 15-minute granularity for the availability time selects
  # (matches the 15-minute appointment-slot step).
  defp time_options do
    for h <- 0..23, m <- [0, 15, 30, 45] do
      :io_lib.format("~2..0B:~2..0B", [h, m]) |> List.to_string()
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Render
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto pb-16">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-display font-bold text-parchment">My Professional Profile</h1>
        <a
          :if={@profile.slug && @profile.is_public}
          href={~p"/nutritionists/#{@profile.slug}"}
          target="_blank"
          class="text-sm text-paprika hover:text-paprika-soft"
        >
          View public page →
        </a>
      </div>

      <.form
        :let={f}
        for={@changeset}
        phx-change="validate"
        phx-submit="save"
        class="profile-form space-y-8"
      >
        <!-- Public details -->
        <section class="bg-ink-panel border border-ink-panel2 rounded-xl p-6 space-y-4">
          <h2 class="text-lg font-display font-semibold text-parchment">Public details</h2>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.labeled label="Display name">
              <.input
                field={f[:display_name]}
                type="text"
                placeholder="e.g. Maria Papadaki"
                class="w-full"
              />
            </.labeled>
            <.labeled label="Specialization">
              <.input
                field={f[:specialization]}
                type="text"
                placeholder="Clinical Dietitian"
                class="w-full"
              />
            </.labeled>
          </div>

          <.labeled label="Short bio">
            <.input field={f[:bio]} type="textarea" rows="3" class="w-full" />
          </.labeled>
          <.labeled label="Education">
            <.input field={f[:education]} type="textarea" rows="3" class="w-full" />
          </.labeled>
          <.labeled label="Scientific contributions">
            <.input field={f[:scientific_contributions]} type="textarea" rows="3" class="w-full" />
          </.labeled>
          <.labeled label="Professional achievements">
            <.input field={f[:professional_achievements]} type="textarea" rows="3" class="w-full" />
          </.labeled>

          <div>
            <label class="block text-sm text-parchment-dim mb-1">Profile photo</label>
            <img
              :if={@profile.photo_url}
              src={@profile.photo_url}
              class="w-24 h-24 rounded-full object-cover mb-2"
            />
            <.live_file_input upload={@uploads.photo} class="text-parchment-dim text-sm" />
          </div>
        </section>

        <!-- Contact & location -->
        <section class="bg-ink-panel border border-ink-panel2 rounded-xl p-6 space-y-4">
          <h2 class="text-lg font-display font-semibold text-parchment">Contact &amp; location</h2>
          <p class="text-parchment-dim text-sm">
            The city is used to rank your profile for local searches (e.g. “nutritionist Rethymno”).
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.labeled label="City">
              <.input field={f[:city]} type="text" placeholder="Rethymno" class="w-full" />
            </.labeled>
            <.labeled label="Region">
              <.input field={f[:region]} type="text" placeholder="Crete" class="w-full" />
            </.labeled>
            <.labeled label="Office address">
              <.input field={f[:office_address]} type="text" class="w-full" />
            </.labeled>
            <.labeled label="Phone">
              <.input field={f[:phone]} type="text" class="w-full" />
            </.labeled>
            <.labeled label="Contact email">
              <.input field={f[:contact_email]} type="text" class="w-full" />
            </.labeled>
            <.labeled label="Website">
              <.input field={f[:website_url]} type="text" placeholder="https://" class="w-full" />
            </.labeled>
          </div>
        </section>

        <!-- Availability -->
        <section class="bg-ink-panel border border-ink-panel2 rounded-xl p-6 space-y-4">
          <h2 class="text-lg font-display font-semibold text-parchment">Weekly availability</h2>
          <p class="text-parchment-dim text-sm">
            Set the hours you take appointments each week. Visitors can request open slots inside these windows.
          </p>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
            <.labeled label="Appointment length (minutes)">
              <.input
                field={f[:appointment_slot_minutes]}
                type="number"
                min="15"
                step="15"
                class="w-full"
              />
            </.labeled>
          </div>
          <%!-- phx-update="ignore": these inputs aren't part of the changeset, so LiveView
               must not re-render (and reset) them on every phx-change="validate". --%>
          <div id="availability-grid" phx-update="ignore" class="space-y-2">
            <div :for={{dow, name} <- @weekdays} class="flex flex-wrap items-center gap-3">
              <label class="flex items-center gap-2 w-32 text-parchment text-sm cursor-pointer">
                <input
                  type="checkbox"
                  name={"availability[#{dow}][enabled]"}
                  value="true"
                  checked={Map.has_key?(@availability, dow)}
                  class="rounded w-4 h-4 cursor-pointer"
                />
                {name}
              </label>
              <.time_dropdown
                name={"availability[#{dow}][start]"}
                value={get_in(@availability, [dow, :start]) || "09:00"}
                options={@time_options}
              />
              <span class="text-parchment-dim">to</span>
              <.time_dropdown
                name={"availability[#{dow}][end]"}
                value={get_in(@availability, [dow, :end]) || "17:00"}
                options={@time_options}
              />
            </div>
          </div>
        </section>

        <!-- Payments -->
        <section class="bg-ink-panel border border-ink-panel2 rounded-xl p-6 space-y-4">
          <h2 class="text-lg font-display font-semibold text-parchment">Payments (optional)</h2>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.labeled label="Consultation fee (EUR)">
              <.input field={f[:consultation_fee_cents]} type="number" min="0" class="w-full" />
            </.labeled>
          </div>
          <div class="flex items-center gap-3">
            <%= if @profile.stripe_charges_enabled do %>
              <span class="inline-flex items-center gap-1 text-basil text-sm">
                <.icon name="hero-check-circle" class="w-5 h-5" /> Payouts connected
              </span>
            <% else %>
              <button
                type="button"
                phx-click="connect_stripe"
                class="px-4 py-2 rounded-lg border border-paprika/40 text-paprika hover:bg-paprika/10 text-sm transition"
              >
                Connect payouts with Stripe
              </button>
            <% end %>
          </div>
          <p class="text-parchment-dim text-xs">
            Connecting sets up a Stripe account so you can be paid for consultations. Charging clients at
            booking is coming next.
          </p>
        </section>

        <!-- Publish -->
        <section class="bg-ink-panel border border-ink-panel2 rounded-xl p-6 space-y-3">
          <label class="flex items-center gap-3 text-parchment">
            <.input field={f[:is_public]} type="checkbox" />
            <span class="font-medium">Make my profile public</span>
          </label>
          <p class="text-parchment-dim text-sm">
            A display name, city and short bio are required to publish. Public profiles appear in the
            nutritionist directory and search engines.
          </p>
        </section>

        <div class="flex justify-end">
          <button
            type="submit"
            class="px-5 py-2.5 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-medium text-sm transition"
          >
            Save profile
          </button>
        </div>
      </.form>
    </div>
    """
  end

  # Themed time picker: a hidden field (submitted with the form) plus an Alpine
  # dropdown. Replaces the native <input type="time"> whose popup didn't match the
  # dark design and couldn't be widened/height-capped. A 2-column panel keeps the
  # list short and wide rather than narrow and long; lives inside the
  # phx-update="ignore" grid so client selections survive validate re-renders.
  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :options, :list, required: true

  defp time_dropdown(assigns) do
    ~H"""
    <div class="relative" x-data={"{ open: false, val: '#{@value}' }"} @click.outside="open = false">
      <input type="hidden" name={@name} value={@value} x-bind:value="val" />
      <button
        type="button"
        @click="open = !open"
        class="flex items-center justify-between gap-2 w-24 bg-ink-panel2 text-parchment border border-ink-panel2 rounded px-2 py-1.5 text-sm focus:outline-none focus:border-paprika"
      >
        <span x-text="val"></span>
        <.icon name="hero-chevron-down" class="w-3.5 h-3.5 text-parchment-dim" />
      </button>
      <div
        x-show="open"
        x-cloak
        class="m3-scrollbar absolute left-0 z-30 mt-1 w-40 max-h-56 overflow-auto rounded-lg border border-ink-panel2 bg-ink-panel shadow-xl p-1 grid grid-cols-2 gap-0.5"
      >
        <button
          :for={t <- @options}
          type="button"
          @click={"val = '#{t}'; open = false"}
          x-bind:class={"val === '#{t}' ? 'bg-paprika text-ink' : 'text-parchment hover:bg-ink-panel2'"}
          class="rounded px-2 py-1 text-sm text-center"
        >
          {t}
        </button>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp labeled(assigns) do
    ~H"""
    <div>
      <label class="block text-sm text-parchment-dim mb-1">{@label}</label>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
