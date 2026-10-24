defmodule MehungryWeb.ProfessionalLive.AndroidBetaLive do
  @moduledoc """
  Admin tool for sending the Android closed-testing (Google Play) opt-in invite.

  Sends the branded `Accounts.deliver_android_beta_invite/2` email to one or more
  recipients — individual testers and/or a Google Group address that fans the
  invite out to its members. A live preview pane renders the exact HTML that
  will be sent.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Accounts
  alias Mehungry.BetaSignups

  # Deliberately forgiving: split on commas, semicolons and any whitespace.
  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  # This page sends the Android opt-in invite, so its bulk-load buttons target
  # only testers who said they're interested in Android.
  @platform "android"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:opt_in_url, Accounts.android_beta_opt_in_url())
     |> assign(:recipients, Accounts.android_beta_group_email())
     |> assign(:intro, "")
     |> assign(:version, Accounts.android_beta_current_version())
     |> assign(:platform, @platform)
     |> assign(:results, nil)
     |> refresh_signups()
     |> refresh_preview()}
  end

  @impl true
  def handle_event("validate", %{"invite" => params}, socket) do
    {:noreply,
     socket
     |> assign(:opt_in_url, params["opt_in_url"] || "")
     |> assign(:recipients, params["recipients"] || "")
     |> assign(:intro, params["intro"] || "")
     |> assign(:version, params["version"] || "")
     |> refresh_preview()}
  end

  def handle_event("use_group", _params, socket) do
    group = Accounts.android_beta_group_email()
    recipients = append_recipient(socket.assigns.recipients, group)
    {:noreply, assign(socket, :recipients, recipients)}
  end

  def handle_event("load_signups", _params, socket) do
    emails =
      socket.assigns.signups
      |> for_platform(@platform)
      |> Enum.map_join(", ", & &1.email)

    socket =
      if emails == "" do
        put_flash(socket, :error, "No Android testers registered yet.")
      else
        assign(socket, :recipients, emails)
      end

    {:noreply, socket}
  end

  def handle_event("load_missing", _params, socket) do
    version = String.trim(socket.assigns.version || "")

    socket =
      cond do
        version == "" ->
          put_flash(socket, :error, "Set a version first.")

        true ->
          missing = BetaSignups.signups_missing_version(version, @platform)

          if missing == [] do
            put_flash(socket, :info, "All Android testers already got #{version}.")
          else
            emails = Enum.map_join(missing, ", ", & &1.email)
            assign(socket, :recipients, emails)
          end
      end

    {:noreply, socket}
  end

  def handle_event("delete_signup", %{"id" => id}, socket) do
    id
    |> BetaSignups.get_beta_signup!()
    |> BetaSignups.delete_beta_signup()

    {:noreply, refresh_signups(socket)}
  end

  def handle_event("send", %{"invite" => params}, socket) do
    opt_in_url = String.trim(params["opt_in_url"] || "")
    intro = params["intro"] || ""
    version = String.trim(params["version"] || "")
    {valid, invalid} = parse_recipients(params["recipients"] || "")

    # Persist the submitted fields so the form keeps its values after submit
    # (no phx-change fires on submit).
    socket =
      socket
      |> assign(:opt_in_url, opt_in_url)
      |> assign(:recipients, params["recipients"] || "")
      |> assign(:intro, intro)
      |> assign(:version, version)
      |> refresh_preview()

    cond do
      opt_in_url == "" ->
        {:noreply, put_flash(socket, :error, "Add the Google Play opt-in URL before sending.")}

      version == "" ->
        {:noreply, put_flash(socket, :error, "Set the version being sent before sending.")}

      valid == [] ->
        {:noreply,
         put_flash(socket, :error, "Add at least one valid recipient email address.")}

      true ->
        opts = [opt_in_url: opt_in_url, intro: intro]

        results =
          Enum.map(valid, fn email ->
            case Accounts.deliver_android_beta_invite(email, opts) do
              {:ok, _} ->
                # Only a delivered invite counts as "this tester got this version".
                BetaSignups.record_send(email, version)
                {:ok, email}

              {:error, reason} ->
                {:error, email, inspect(reason)}
            end
          end)

        sent = Enum.count(results, &match?({:ok, _}, &1))
        failed = length(results) - sent

        flash =
          "Sent #{sent} invite#{plural(sent)} for #{version}" <>
            if(failed > 0, do: ", #{failed} failed", else: "") <>
            if(invalid != [], do: ". Skipped #{length(invalid)} invalid address#{plural_es(length(invalid))}.", else: ".")

        socket =
          socket
          |> assign(:results, %{results: results, invalid: invalid})
          |> refresh_signups()
          |> then(fn s ->
            if failed > 0, do: put_flash(s, :error, flash), else: put_flash(s, :info, flash)
          end)

        {:noreply, socket}
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp refresh_signups(socket) do
    socket
    |> assign(:signups, BetaSignups.list_beta_signups())
    |> assign(:versions_by_tester, BetaSignups.versions_by_tester())
  end

  defp refresh_preview(socket) do
    html =
      Accounts.android_beta_email_html(
        opt_in_url: socket.assigns.opt_in_url,
        intro: socket.assigns.intro
      )

    assign(socket, :preview_html, html)
  end

  defp parse_recipients(raw) do
    raw
    |> String.split([",", ";", "\n", "\r", "\t", " "], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.split_with(&Regex.match?(@email_regex, &1))
  end

  defp append_recipient(existing, email) do
    existing = String.trim(existing)

    if existing == "" do
      email
    else
      if String.contains?(existing, email), do: existing, else: existing <> ", " <> email
    end
  end

  defp plural(1), do: ""
  defp plural(_), do: "s"
  defp plural_es(1), do: ""
  defp plural_es(_), do: "es"

  defp version_label(v) when is_binary(v) and v != "", do: v
  defp version_label(_), do: "current"

  defp platform_label("android"), do: "Android"
  defp platform_label("ios"), do: "iOS"
  defp platform_label("web"), do: "Web"
  defp platform_label(other), do: other

  # Static, ready-to-share recruitment post for Facebook groups & communities.
  defp recruitment_post do
    """
    Hi everyone! 👋

    I'm a developer working on something I'm really passionate about, and I'd love to get your help.

    I'm building m3hungry, a nutrition app with a focus on the things that often go beyond the basics: micronutrients, bioactive compounds, and specialized therapeutic and functional diets.

    My goal is to create something that helps people explore nutrition more deeply, share their experiences and insights, learn from one another, and connect with nutrition professionals.

    But I don't want to build this app based only on my own ideas of what people need. I'd like to build it with the people it's meant to serve.

    I believe that useful nutrition tools and knowledge should be accessible to as many people as possible. My vision is to keep the vast majority of the app's features free for everyone while supporting its long-term development through tools that help nutrition professionals in their work.

    I'm still developing m3hungry, and that's exactly why I'm reaching out now. I'd love to hear from people who are interested in nutrition, whether you're simply curious about food, exploring a particular diet, or working in the nutrition field.

    If you'd like to help shape the app, share your thoughts, or become one of its early testers, I'd be genuinely happy to have you on board.

    👉 Sign up to become an early tester here: https://www.m3hungry.com/trial

    Would you be interested in helping me build m3hungry? ❤️

    Thanks for reading, and I'd love to hear your thoughts!
    """
  end

  # Versions a tester has been sent, from the in-memory map (keyed on canonical).
  defp tester_versions(versions_by_tester, signup) do
    Map.get(versions_by_tester, signup.canonical_email, [])
  end

  defp got_version?(versions_by_tester, signup, version) do
    version != "" and version in tester_versions(versions_by_tester, signup)
  end

  # Signups interested in `platform`.
  defp for_platform(signups, platform) do
    Enum.filter(signups, fn s -> platform in (s.platforms || []) end)
  end

  # How many Android testers have NOT been sent `version` (in-memory count).
  defp missing_count(_signups, _versions, ""), do: 0

  defp missing_count(signups, versions_by_tester, version) do
    signups
    |> for_platform(@platform)
    |> Enum.count(fn s -> not got_version?(versions_by_tester, s, version) end)
  end

  # ── Render ──────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-ink">
      <div class="container mx-auto px-4 py-6 max-w-6xl">
        <div class="mb-6">
          <h1 class="text-2xl font-bold text-white flex items-center gap-3">
            <.icon name="hero-device-phone-mobile" class="w-7 h-7 text-paprika flex-shrink-0" />
            Android Beta Invite
          </h1>
          <p class="text-parchment-dim text-sm mt-1">
            Send the Google Play closed-testing opt-in invite to testers or a Google Group.
          </p>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <!-- Form -->
          <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
            <.form for={%{}} as={:invite} id="android-beta-form" phx-change="validate" phx-submit="send">
              <div class="space-y-5">
                <div>
                  <label class="block text-sm font-medium text-white mb-1">Recipients</label>
                  <p class="text-xs text-parchment-dim mb-2">
                    One or more emails, separated by commas or new lines. A Google Group
                    address fans the invite out to its members.
                  </p>
                  <textarea
                    name="invite[recipients]"
                    rows="3"
                    class="w-full rounded-lg bg-ink border border-ink-panel2 text-white text-sm px-3 py-2 focus:border-paprika focus:ring-paprika placeholder:text-parchment-dim/60"
                    placeholder="tester@example.com, mehungry-android-testers@googlegroups.com"
                  >{@recipients}</textarea>
                  <div class="mt-2 flex flex-wrap items-center gap-4">
                    <button
                      type="button"
                      phx-click="use_group"
                      class="inline-flex items-center gap-1.5 text-xs text-paprika-soft hover:text-paprika transition"
                    >
                      <.icon name="hero-user-group" class="w-4 h-4" /> Add beta Google Group
                    </button>
                    <button
                      type="button"
                      phx-click="load_signups"
                      class="inline-flex items-center gap-1.5 text-xs text-paprika-soft hover:text-paprika transition"
                    >
                      <.icon name="hero-arrow-down-tray" class="w-4 h-4" />
                      Load Android testers ({length(for_platform(@signups, @platform))})
                    </button>
                    <button
                      type="button"
                      phx-click="load_missing"
                      class="inline-flex items-center gap-1.5 text-xs text-paprika-soft hover:text-paprika transition"
                    >
                      <.icon name="hero-sparkles" class="w-4 h-4" />
                      Load testers missing {version_label(@version)} ({missing_count(
                        @signups,
                        @versions_by_tester,
                        @version
                      )})
                    </button>
                  </div>
                </div>

                <div>
                  <label class="block text-sm font-medium text-white mb-1">
                    Google Play opt-in URL
                  </label>
                  <input
                    type="text"
                    name="invite[opt_in_url]"
                    value={@opt_in_url}
                    class="w-full rounded-lg bg-ink border border-ink-panel2 text-white text-sm px-3 py-2 focus:border-paprika focus:ring-paprika placeholder:text-parchment-dim/60"
                    placeholder="https://play.google.com/apps/testing/com.mehungry.app"
                  />
                </div>

                <div>
                  <label class="block text-sm font-medium text-white mb-1">
                    Version being sent
                  </label>
                  <p class="text-xs text-parchment-dim mb-2">
                    Recorded per tester so you can tell who already got this build.
                  </p>
                  <input
                    type="text"
                    name="invite[version]"
                    value={@version}
                    class="w-full rounded-lg bg-ink border border-ink-panel2 text-white text-sm px-3 py-2 focus:border-paprika focus:ring-paprika placeholder:text-parchment-dim/60"
                    placeholder="e.g. 1.2.0 (build 45)"
                  />
                </div>

                <div>
                  <label class="block text-sm font-medium text-white mb-1">
                    Intro message <span class="text-parchment-dim font-normal">(optional)</span>
                  </label>
                  <textarea
                    name="invite[intro]"
                    rows="3"
                    class="w-full rounded-lg bg-ink border border-ink-panel2 text-white text-sm px-3 py-2 focus:border-paprika focus:ring-paprika placeholder:text-parchment-dim/60"
                    placeholder="A personal line shown above the standard copy…"
                  >{@intro}</textarea>
                </div>

                <button
                  type="submit"
                  data-confirm="Send the Android beta invite now?"
                  class="inline-flex items-center gap-2 bg-paprika hover:bg-paprika-soft text-white font-semibold text-sm px-5 py-2.5 rounded-full transition"
                >
                  <.icon name="hero-paper-airplane" class="w-4 h-4" /> Send invite
                </button>
              </div>
            </.form>

            <%= if @results do %>
              <div class="mt-6 border-t border-ink-panel2 pt-4">
                <h3 class="text-sm font-semibold text-white mb-2">Delivery results</h3>
                <ul class="space-y-1.5">
                  <%= for result <- @results.results do %>
                    <li class="flex items-center gap-2 text-xs">
                      <%= case result do %>
                        <% {:ok, email} -> %>
                          <.icon name="hero-check-circle" class="w-4 h-4 text-basil flex-shrink-0" />
                          <span class="text-parchment">{email}</span>
                        <% {:error, email, reason} -> %>
                          <.icon name="hero-x-circle" class="w-4 h-4 text-red-400 flex-shrink-0" />
                          <span class="text-parchment">{email}</span>
                          <span class="text-red-400/80 truncate">— {reason}</span>
                      <% end %>
                    </li>
                  <% end %>
                  <%= for email <- @results.invalid do %>
                    <li class="flex items-center gap-2 text-xs">
                      <.icon name="hero-exclamation-triangle" class="w-4 h-4 text-amber-400 flex-shrink-0" />
                      <span class="text-parchment-dim">{email} — skipped (invalid)</span>
                    </li>
                  <% end %>
                </ul>
              </div>
            <% end %>
          </div>

          <!-- Preview -->
          <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
            <h3 class="text-sm font-semibold text-white mb-3 flex items-center gap-2">
              <.icon name="hero-eye" class="w-4 h-4 text-parchment-dim" /> Email preview
            </h3>
            <iframe
              title="Email preview"
              srcdoc={@preview_html}
              class="w-full h-[640px] rounded-lg border border-ink-panel2 bg-white"
            >
            </iframe>
          </div>
        </div>

        <!-- Recruitment post (copy & share) -->
        <div class="mt-6 bg-ink-panel border border-ink-panel2 rounded-xl p-5">
          <h3 class="text-sm font-semibold text-white flex items-center gap-2 mb-1">
            <.icon name="hero-megaphone" class="w-4 h-4 text-parchment-dim" />
            Recruitment post
          </h3>
          <p class="text-parchment-dim text-xs mb-3">
            Ready-to-share text for Facebook groups & communities — copy it and post as-is.
            It links people to the <code class="text-paprika">/trial</code> signup page.
          </p>
          <div id="recruitment-post" phx-update="ignore" x-data="{ copied: false }">
            <textarea
              x-ref="post"
              readonly
              rows="24"
              class="w-full rounded-lg bg-ink border border-ink-panel2 text-parchment text-sm px-3 py-3 leading-relaxed focus:border-paprika focus:ring-paprika"
            >{recruitment_post()}</textarea>
            <button
              type="button"
              x-on:click="navigator.clipboard.writeText($refs.post.value); copied = true; setTimeout(() => copied = false, 2000)"
              class="mt-3 inline-flex items-center gap-2 bg-paprika hover:bg-paprika-soft text-white font-semibold text-sm px-5 py-2.5 rounded-full transition"
            >
              <.icon name="hero-clipboard-document" class="w-4 h-4" />
              <span x-text="copied ? 'Copied!' : 'Copy post'">Copy post</span>
            </button>
          </div>
        </div>

        <!-- Registered testers -->
        <div class="mt-6 bg-ink-panel border border-ink-panel2 rounded-xl p-5">
          <div class="flex items-center justify-between mb-3">
            <h3 class="text-sm font-semibold text-white flex items-center gap-2">
              <.icon name="hero-clipboard-document-list" class="w-4 h-4 text-parchment-dim" />
              Registered testers
              <span class="text-parchment-dim font-normal">({length(@signups)})</span>
            </h3>
            <a href="/trial" target="_blank" class="text-xs text-paprika-soft hover:text-paprika">
              View public page ↗
            </a>
          </div>

          <%= if @signups == [] do %>
            <p class="text-parchment-dim text-sm">
              No one has registered yet. Share the <code class="text-paprika">/trial</code>
              page to collect testers.
            </p>
          <% else %>
            <ul class="divide-y divide-ink-panel2">
              <%= for signup <- @signups do %>
                <li class="flex items-center justify-between gap-4 py-2.5">
                  <div class="min-w-0">
                    <div class="flex items-center flex-wrap gap-2">
                      <span class="text-sm text-parchment truncate">{signup.email}</span>
                      <%= for p <- signup.platforms || [] do %>
                        <span class="text-[10px] font-semibold uppercase tracking-wide bg-paprika/10 text-paprika-soft border border-paprika/25 px-1.5 py-0.5 rounded-full">
                          {platform_label(p)}
                        </span>
                      <% end %>
                      <%= if @platform in (signup.platforms || []) do %>
                        <%= if got_version?(@versions_by_tester, signup, String.trim(@version || "")) do %>
                          <span class="text-[10px] font-semibold uppercase tracking-wide bg-basil/15 text-basil border border-basil/30 px-1.5 py-0.5 rounded-full">
                            ✓ {version_label(@version)}
                          </span>
                        <% else %>
                          <span class="text-[10px] font-semibold uppercase tracking-wide bg-amber-500/10 text-amber-400 border border-amber-500/30 px-1.5 py-0.5 rounded-full">
                            missing {version_label(@version)}
                          </span>
                        <% end %>
                      <% end %>
                    </div>
                    <div class="flex items-center flex-wrap gap-1.5 mt-1">
                      <span class="text-xs text-parchment-dim">
                        {Calendar.strftime(signup.inserted_at, "%d %b %Y")}
                      </span>
                      <%= for v <- tester_versions(@versions_by_tester, signup) do %>
                        <span class="text-[10px] text-parchment-dim bg-ink border border-ink-panel2 px-1.5 py-0.5 rounded">
                          {v}
                        </span>
                      <% end %>
                      <%= if tester_versions(@versions_by_tester, signup) == [] do %>
                        <span class="text-[10px] text-parchment-dim/70 italic">no versions sent yet</span>
                      <% end %>
                    </div>
                  </div>
                  <button
                    phx-click="delete_signup"
                    phx-value-id={signup.id}
                    data-confirm="Remove this tester from the list?"
                    class="flex-shrink-0 p-1.5 rounded-lg text-parchment-dim hover:text-red-400 hover:bg-red-500/10 transition"
                  >
                    <.icon name="hero-trash" class="w-4 h-4" />
                  </button>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
