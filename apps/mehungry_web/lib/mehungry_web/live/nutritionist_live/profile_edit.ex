defmodule MehungryWeb.NutritionistLive.ProfileEdit do
  @moduledoc """
  The nutritionist's own profile editor: public-facing details, a photo, the
  publish toggle, and a recurring weekly availability grid. Payments (Stripe
  onboarding + service pricing) live on the separate `/nutritionist/payments`
  workspace.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Professionals
  alias Mehungry.Professionals.ProfessionalProfile
  alias Mehungry.Storage

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
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    profile =
      Professionals.get_professional_profile(user.id) || %ProfessionalProfile{user_id: user.id}

    socket =
      socket
      |> assign(:page_title, gettext("My Professional Profile"))
      |> assign(:profile, profile)
      |> assign(:short_link_base, MehungryWeb.Endpoint.url())
      |> assign(:short_link_host, URI.parse(MehungryWeb.Endpoint.url()).host)
      |> assign(
        :changeset,
        Professionals.change_professional_profile(profile, %{user_id: user.id})
      )
      |> assign(:availability, availability_model(user.id))
      |> assign(:weekdays, @weekdays)
      |> assign(:time_options, time_options())
      |> assign(:remove_photo, false)
      |> allow_upload(:photo,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 5_000_000,
        # Upload to storage on selection (not on form submit) so the progress
        # bar advances immediately and the preview is ready before Save.
        auto_upload: true,
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
    old_photo_url = socket.assigns.profile.photo_url
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

        cleanup_replaced_photo(old_photo_url, profile.photo_url)

        {:noreply,
         socket
         |> assign(:profile, profile)
         |> assign(:remove_photo, false)
         |> assign(:changeset, Professionals.change_professional_profile(profile))
         |> assign(:availability, availability_model(user.id))
         |> put_flash(:info, profile_saved_flash(profile))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:changeset, Map.put(changeset, :action, :insert))
         |> put_flash(:error, gettext("Please fix the errors below."))}
    end
  end

  @impl true
  def handle_event("cancel-photo", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  @impl true
  def handle_event("remove-photo", _params, socket) do
    {:noreply, assign(socket, :remove_photo, true)}
  end

  @impl true
  def handle_event("keep-photo", _params, socket) do
    {:noreply, assign(socket, :remove_photo, false)}
  end

  defp with_user_id(params, socket),
    do: Map.put(params, "user_id", socket.assigns.current_user.id)

  # Resolve the photo for this save: a freshly uploaded file wins; otherwise, if
  # the nutritionist asked to remove their current photo, clear it; else leave
  # the stored value untouched (so it survives an unrelated field edit).
  defp maybe_put_photo(attrs, socket) do
    case consume_uploaded_entries(socket, :photo, fn %{public_url: public_url}, _entry ->
           {:ok, public_url}
         end) do
      [photo_url | _] -> Map.put(attrs, "photo_url", photo_url)
      [] -> if socket.assigns.remove_photo, do: Map.put(attrs, "photo_url", nil), else: attrs
    end
  end

  # Delete the previous object once the profile no longer points at it (replaced
  # or removed), so swapping a photo doesn't orphan files in storage.
  # `delete_by_url/1` is a no-op for URLs we don't own.
  defp cleanup_replaced_photo(old_url, new_url)
       when is_binary(old_url) and old_url != "" and old_url != new_url do
    Storage.delete_by_url(old_url)
    :ok
  end

  defp cleanup_replaced_photo(_old_url, _new_url), do: :ok

  defp error_to_string(:too_large), do: gettext("That image is too large (max 5 MB).")
  defp error_to_string(:not_accepted), do: gettext("Please choose a JPG, PNG or WebP image.")
  defp error_to_string(:too_many_files), do: gettext("Please choose a single image.")
  defp error_to_string(_), do: gettext("That file could not be uploaded.")

  # Initial letter for the empty-photo avatar, read live from the changeset so it
  # tracks the display-name field as it's typed.
  defp display_initial(changeset) do
    case Ecto.Changeset.get_field(changeset, :display_name) do
      name when is_binary(name) and name != "" -> String.first(name)
      _ -> "?"
    end
  end

  defp presign_upload(entry, socket) do
    key = MehungryWeb.Uploads.key_for("profile_photos", entry)
    {:ok, MehungryWeb.Uploads.meta(entry, key, 5_000_000), socket}
  end

  defp profile_saved_flash(%{is_public: true, slug: slug}) when is_binary(slug),
    do: gettext("Profile saved and published at /nutritionists/%{slug}.", slug: slug)

  defp profile_saved_flash(_), do: gettext("Profile saved.")

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
        <h1 class="text-2xl font-display font-bold text-parchment">{gettext("My Professional Profile")}</h1>
        <a
          :if={@profile.slug && @profile.is_public}
          href={~p"/nutritionists/#{@profile.slug}"}
          target="_blank"
          class="text-sm text-paprika hover:text-paprika-soft"
        >
          {gettext("View public page →")}
        </a>
      </div>

      <.form
        :let={f}
        id="profile-form"
        for={@changeset}
        phx-change="validate"
        phx-submit="save"
        class="profile-form space-y-8"
      >
        <!-- Public details -->
        <section class="bg-ink-panel border border-ink-panel2 rounded-xl p-6 space-y-4">
          <h2 class="text-lg font-display font-semibold text-parchment">{gettext("Public details")}</h2>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.labeled label={gettext("Display name")}>
              <.input
                field={f[:display_name]}
                type="text"
                placeholder={gettext("e.g. Maria Papadaki")}
                class="w-full"
              />
            </.labeled>
            <.labeled label={gettext("Specialization")}>
              <.input
                field={f[:specialization]}
                type="text"
                placeholder={gettext("Clinical Dietitian")}
                class="w-full"
              />
            </.labeled>
          </div>

          <.labeled label={gettext("Short bio")}>
            <.input field={f[:bio]} type="textarea" rows="3" class="w-full" />
          </.labeled>
          <.labeled label={gettext("Education")}>
            <.input field={f[:education]} type="textarea" rows="3" class="w-full" />
          </.labeled>
          <.labeled label={gettext("Scientific contributions")}>
            <.input field={f[:scientific_contributions]} type="textarea" rows="3" class="w-full" />
          </.labeled>
          <.labeled label={gettext("Professional achievements")}>
            <.input field={f[:professional_achievements]} type="textarea" rows="3" class="w-full" />
          </.labeled>

          <div>
            <label class="block text-sm text-parchment-dim mb-1">{gettext("Profile photo")}</label>
            <p class="text-parchment-dim text-xs mb-3">
              {gettext("A clear, friendly headshot — shown on your public profile and in the nutritionist directory. JPG, PNG or WebP, up to 5 MB.")}
            </p>

            <div class="flex items-center gap-4" phx-drop-target={@uploads.photo.ref}>
              <div class="shrink-0">
                <%!-- Selected-but-unsaved file preview wins over the stored photo. --%>
                <.live_img_preview
                  :for={entry <- @uploads.photo.entries}
                  entry={entry}
                  class="w-24 h-24 rounded-full object-cover border border-ink-panel2"
                />
                <img
                  :if={@uploads.photo.entries == [] and not is_nil(@profile.photo_url) and not @remove_photo}
                  src={@profile.photo_url}
                  class="w-24 h-24 rounded-full object-cover border border-ink-panel2"
                />
                <div
                  :if={@uploads.photo.entries == [] and (is_nil(@profile.photo_url) or @remove_photo)}
                  class="w-24 h-24 rounded-full bg-paprika/10 text-paprika flex items-center justify-center font-bold text-3xl"
                >
                  {display_initial(@changeset)}
                </div>
              </div>

              <div class="space-y-2">
                <%!-- The native file input is hidden app-wide (essentials.css), so a
                     styled <label> tied to its ref is the visible, clickable trigger. --%>
                <label
                  for={@uploads.photo.ref}
                  class="inline-flex items-center gap-2 px-3 py-1.5 rounded-lg border border-paprika/40 text-paprika hover:bg-paprika/10 text-sm cursor-pointer transition"
                >
                  <.icon name="hero-arrow-up-tray" class="w-4 h-4" />
                  {if @profile.photo_url, do: gettext("Change photo"), else: gettext("Choose photo")}
                </label>
                <.live_file_input upload={@uploads.photo} />

                <div :for={entry <- @uploads.photo.entries} class="flex items-center gap-3">
                  <span class="text-parchment-dim text-xs">{entry.progress}%</span>
                  <button
                    type="button"
                    phx-click="cancel-photo"
                    phx-value-ref={entry.ref}
                    class="text-xs text-paprika hover:text-paprika-soft"
                  >
                    {gettext("Cancel")}
                  </button>
                </div>

                <button
                  :if={@uploads.photo.entries == [] and not is_nil(@profile.photo_url) and not @remove_photo}
                  type="button"
                  phx-click="remove-photo"
                  class="text-xs text-parchment-dim hover:text-paprika"
                >
                  {gettext("Remove photo")}
                </button>
                <div :if={@remove_photo} class="space-y-1">
                  <button
                    type="button"
                    phx-click="keep-photo"
                    class="text-xs text-parchment-dim hover:text-paprika"
                  >
                    {gettext("Keep current photo")}
                  </button>
                  <p class="text-parchment-dim text-xs">
                    {gettext("Your photo will be removed when you save.")}
                  </p>
                </div>
              </div>
            </div>

            <p :for={err <- upload_errors(@uploads.photo)} class="text-rose-400 text-xs mt-2">
              {error_to_string(err)}
            </p>
            <%= for entry <- @uploads.photo.entries, err <- upload_errors(@uploads.photo, entry) do %>
              <p class="text-rose-400 text-xs mt-2">{error_to_string(err)}</p>
            <% end %>
          </div>
        </section>

        <!-- Personal short link -->
        <section class="bg-ink-panel border border-ink-panel2 rounded-xl p-6 space-y-4">
          <h2 class="text-lg font-display font-semibold text-parchment">{gettext("Personal short link")}</h2>
          <p class="text-parchment-dim text-sm">
            {gettext(
              "A short, memorable link to print on cards or drop in your social bios. It redirects visitors to your public profile."
            )}
          </p>
          <.labeled label={gettext("Handle")}>
            <div class="flex items-center gap-2">
              <span class="text-parchment-dim text-sm whitespace-nowrap">{@short_link_host}/@</span>
              <.input field={f[:handle]} type="text" placeholder="maria" class="flex-1" />
            </div>
          </.labeled>
          <div :if={(f[:handle].value || "") != ""} class="flex items-center gap-3 flex-wrap">
            <code class="text-parchment text-sm break-all">
              {@short_link_base}/@{f[:handle].value}
            </code>
            <button
              type="button"
              x-data
              data-link={"#{@short_link_base}/@#{f[:handle].value}"}
              @click={"navigator.clipboard.writeText($el.dataset.link); $el.textContent = '#{gettext("Copied!")}'"}
              class="px-3 py-1.5 rounded-lg border border-paprika/40 text-paprika hover:bg-paprika/10 text-sm transition"
            >
              {gettext("Copy link")}
            </button>
          </div>
          <p :if={(f[:handle].value || "") != "" and not @profile.is_public} class="text-parchment-dim text-xs">
            {gettext("Publish your profile below for this link to go live.")}
          </p>
        </section>

        <!-- Contact & location -->
        <section class="bg-ink-panel border border-ink-panel2 rounded-xl p-6 space-y-4">
          <h2 class="text-lg font-display font-semibold text-parchment">{gettext("Contact & location")}</h2>
          <p class="text-parchment-dim text-sm">
            {gettext("The city is used to rank your profile for local searches (e.g. “nutritionist Rethymno”).")}
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.labeled label={gettext("City")}>
              <.input field={f[:city]} type="text" placeholder="Rethymno" class="w-full" />
            </.labeled>
            <.labeled label={gettext("Region")}>
              <.input field={f[:region]} type="text" placeholder="Crete" class="w-full" />
            </.labeled>
            <.labeled label={gettext("Office address")}>
              <.input field={f[:office_address]} type="text" class="w-full" />
            </.labeled>
            <.labeled label={gettext("Phone")}>
              <.input field={f[:phone]} type="text" class="w-full" />
            </.labeled>
            <.labeled label={gettext("Contact email")}>
              <.input field={f[:contact_email]} type="text" class="w-full" />
            </.labeled>
            <.labeled label={gettext("Website")}>
              <.input field={f[:website_url]} type="text" placeholder="https://" class="w-full" />
            </.labeled>
          </div>
        </section>

        <!-- Availability -->
        <section class="bg-ink-panel border border-ink-panel2 rounded-xl p-6 space-y-4">
          <h2 class="text-lg font-display font-semibold text-parchment">{gettext("Weekly availability")}</h2>
          <p class="text-parchment-dim text-sm">
            {gettext("Set the hours you take appointments each week. Visitors can request open slots inside these windows.")}
          </p>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
            <.labeled label={gettext("Appointment length (minutes)")}>
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
                {weekday_label(name)}
              </label>
              <.time_dropdown
                name={"availability[#{dow}][start]"}
                value={get_in(@availability, [dow, :start]) || "09:00"}
                options={@time_options}
              />
              <span class="text-parchment-dim">{gettext("to")}</span>
              <.time_dropdown
                name={"availability[#{dow}][end]"}
                value={get_in(@availability, [dow, :end]) || "17:00"}
                options={@time_options}
              />
            </div>
          </div>
        </section>

        <!-- Payments (moved to its own workspace) -->
        <section class="bg-ink-panel border border-ink-panel2 rounded-xl p-6 space-y-2">
          <h2 class="text-lg font-display font-semibold text-parchment">{gettext("Payments & pricing")}</h2>
          <p class="text-parchment-dim text-sm">
            {gettext("Connect payouts and set your session/package prices on the")}
            <a href="/nutritionist/payments" class="text-paprika hover:text-paprika-soft">{gettext("Payments")}</a>
            {gettext("page.")}
          </p>
        </section>

        <!-- Publish -->
        <section class="bg-ink-panel border border-ink-panel2 rounded-xl p-6 space-y-3">
          <label class="flex items-center gap-3 text-parchment">
            <.input field={f[:is_public]} type="checkbox" />
            <span class="font-medium">{gettext("Make my profile public")}</span>
          </label>
          <p class="text-parchment-dim text-sm">
            {gettext(
              "A display name, city and short bio are required to publish. Public profiles appear in the nutritionist directory and search engines."
            )}
          </p>
        </section>

        <div class="flex justify-end">
          <button
            type="submit"
            class="px-5 py-2.5 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-medium text-sm transition"
          >
            {gettext("Save profile")}
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

  # Weekday names are stored in the @weekdays module attribute (compile-time), so
  # they can't be wrapped in gettext in place. Translate the literal at render.
  defp weekday_label("Monday"), do: gettext("Monday")
  defp weekday_label("Tuesday"), do: gettext("Tuesday")
  defp weekday_label("Wednesday"), do: gettext("Wednesday")
  defp weekday_label("Thursday"), do: gettext("Thursday")
  defp weekday_label("Friday"), do: gettext("Friday")
  defp weekday_label("Saturday"), do: gettext("Saturday")
  defp weekday_label("Sunday"), do: gettext("Sunday")
  defp weekday_label(other), do: other
end
