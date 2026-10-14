defmodule MehungryWeb.TrialLive.Index do
  @moduledoc """
  Public, shareable signup page for the Android closed-testing programme.

  Visitors register their email (saved to `Mehungry.BetaSignups`) and receive a
  branded welcome email with a one-click unsubscribe link. A secondary "remove
  me" box lets them take themselves off the list on the spot. Cloudflare
  Turnstile guards the form (a no-op when no secret key is configured).
  """
  use MehungryWeb, :live_view

  alias Mehungry.BetaSignups
  alias Mehungry.Accounts
  alias MehungryWeb.Turnstile

  @owner_email "nikolisgal@gmail.com"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Join the Mehungry beta")
     |> assign(:owner_email, @owner_email)
     |> assign(:form, to_form(BetaSignups.change_beta_signup()))
     |> assign(:submitted, false)
     |> assign(:removed, nil)
     |> assign(:turnstile_site_key, Turnstile.site_key())}
  end

  @impl true
  def handle_event("validate", %{"beta_signup" => params}, socket) do
    changeset =
      BetaSignups.change_beta_signup(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("submit", %{"beta_signup" => params} = payload, socket) do
    token = payload["cf-turnstile-response"]

    case Turnstile.verify(token) do
      :ok ->
        do_signup(socket, params)

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, "Captcha verification failed. Please try again.")}
    end
  end

  def handle_event("remove", %{"remove" => %{"email" => email}}, socket) do
    {:ok, count} = BetaSignups.remove_by_email(email)

    message =
      if count > 0 do
        "You've been removed from the list."
      else
        "That email isn't on our list — nothing to remove."
      end

    {:noreply, assign(socket, :removed, message)}
  end

  defp do_signup(socket, params) do
    attrs = Map.put(params, "source", "trial_page")

    case BetaSignups.create_beta_signup(attrs) do
      {:ok, signup} ->
        Accounts.deliver_trial_welcome(signup.email, unsubscribe_url(signup.unsubscribe_token))
        {:noreply, assign(socket, :submitted, true)}

      {:error, changeset} ->
        if already_registered?(changeset) do
          # Idempotent from the visitor's point of view — they're on the list.
          {:noreply, assign(socket, :submitted, true)}
        else
          {:noreply, assign(socket, :form, to_form(changeset))}
        end
    end
  end

  defp already_registered?(changeset) do
    Enum.any?(changeset.errors, fn {field, _} -> field == :canonical_email end)
  end

  defp unsubscribe_url(token) do
    MehungryWeb.Endpoint.url() <> "/trial/unsubscribe/" <> token
  end

  # Currently-selected platforms from the form (list of strings).
  defp platform_values(form) do
    case form[:platforms].value do
      list when is_list(list) -> list
      _ -> []
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-ink text-parchment px-4 py-12">
      <div class="w-full max-w-lg mx-auto">
        <div class="mb-8 text-center">
          <img src="/images/logo2.svg" alt="Mehungry" class="w-14 h-14 mx-auto mb-5" />
          <h1 class="text-3xl font-display font-medium text-parchment">
            Help us test the Mehungry app
          </h1>
          <p class="text-parchment-dim text-base mt-3 leading-relaxed">
            I'm building <span class="text-paprika font-medium">Mehungry</span> — a food &
            recipe app that analyzes nutrition, builds meal plans, and connects you with a
            community of cooks. It's in early testing, and I'd love your help.
          </p>
          <p class="text-parchment-dim text-sm mt-3">
            Drop your email below to join the testing group — or email me directly at
            <a href={"mailto:#{@owner_email}"} class="text-paprika hover:text-paprika-soft underline">
              {@owner_email}
            </a>.
          </p>
        </div>

        <%= if @submitted do %>
          <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-8 text-center">
            <div class="inline-flex items-center justify-center w-12 h-12 rounded-full bg-green-500/10 mb-4">
              <.icon name="hero-check-circle" class="h-6 w-6 text-green-400" />
            </div>
            <h2 class="text-lg font-display font-medium text-parchment">You're on the list!</h2>
            <p class="text-parchment-dim text-sm mt-1">
              Thanks for signing up. We sent you a confirmation email and will be in touch with an
              invitation to join the beta soon.
            </p>
          </div>
        <% else %>
          <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-6">
            <.form
              for={@form}
              id="trial-signup-form"
              phx-change="validate"
              phx-submit="submit"
              class="space-y-5"
            >
              <div>
                <label class="block text-sm font-medium text-parchment-dim mb-1.5">
                  Your email
                </label>
                <.input
                  field={@form[:email]}
                  type="email"
                  placeholder="you@example.com"
                  class="w-full rounded-lg"
                />
              </div>

              <div>
                <label class="block text-sm font-medium text-parchment-dim mb-2">
                  Which platforms would you like to test?
                </label>
                <!-- hidden entry keeps the key present so unchecking all is a real
                     empty selection (→ validation error) instead of snapping back -->
                <input type="hidden" name="beta_signup[platforms][]" value="" />
                <div class="flex flex-wrap gap-2">
                  <%= for {val, label} <- [{"android", "Android"}, {"ios", "iOS"}, {"web", "Web"}] do %>
                    <label class="flex items-center gap-2 cursor-pointer select-none rounded-lg border border-ink-panel2 bg-ink px-3 py-2 hover:border-paprika/60 transition">
                      <input
                        type="checkbox"
                        name="beta_signup[platforms][]"
                        value={val}
                        checked={val in platform_values(@form)}
                        class="rounded border-ink-panel2 bg-ink text-paprika focus:ring-paprika"
                      />
                      <span class="text-sm text-parchment">{label}</span>
                    </label>
                  <% end %>
                </div>
                <%= for {msg, _opts} <- @form[:platforms].errors do %>
                  <p class="mt-1.5 text-xs text-red-400">{msg}</p>
                <% end %>
              </div>

              <%= if @turnstile_site_key do %>
                <div
                  id="trial-turnstile"
                  phx-hook="Turnstile"
                  phx-update="ignore"
                  data-sitekey={@turnstile_site_key}
                >
                </div>
              <% end %>

              <button
                type="submit"
                class="w-full py-2.5 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-bold transition-colors"
              >
                Join the beta
              </button>
            </.form>
          </div>

          <!-- Self-service removal -->
          <div class="mt-6 bg-ink-panel/60 border border-ink-panel2 rounded-xl p-5">
            <h3 class="text-sm font-medium text-parchment mb-1">Already registered?</h3>
            <p class="text-parchment-dim text-xs mb-3">
              Enter your email to remove yourself from the testing list.
            </p>
            <%= if @removed do %>
              <p class="text-sm text-basil-soft">{@removed}</p>
            <% else %>
              <form phx-submit="remove" class="flex gap-2">
                <input
                  type="email"
                  name="remove[email]"
                  placeholder="you@example.com"
                  required
                  class="flex-1 rounded-lg bg-ink border border-ink-panel2 text-parchment text-sm px-3 py-2 focus:border-paprika focus:ring-paprika"
                />
                <button
                  type="submit"
                  class="px-4 py-2 rounded-lg border border-ink-panel2 text-parchment-dim hover:text-parchment hover:border-parchment-dim text-sm transition"
                >
                  Remove me
                </button>
              </form>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
