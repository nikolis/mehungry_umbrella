defmodule Mehungry.Accounts.UserNotifier do
  @moduledoc false

  import Swoosh.Email
  require Logger
  alias Mehungry.Mailer

  # The M3Hungry mark is served as a hosted PNG rather than inline SVG — Gmail
  # and Outlook strip SVG from email, so an <img> is the only reliable logo.
  defp brand_header do
    """
    <img src="https://www.m3hungry.com/images/m3hungry_icon_192.png"
         width="76" height="76" alt="M3Hungry"
         style="display:block;border:0;outline:none;text-decoration:none;border-radius:18px;" />
    """
  end

  defp wordmark do
    """
    <div style="font-family:Georgia,'Times New Roman',serif;font-size:30px;
                font-weight:700;letter-spacing:1px;color:#F4EEDD;line-height:1;">
      M3<span style="color:#E8622C;">HUNGRY</span>
    </div>
    <div style="font-family:'Helvetica Neue',Helvetica,Arial,sans-serif;
                font-size:11px;letter-spacing:3px;color:#8FDDCE;margin-top:8px;">
      ANALYZE &#x2022; SHARE &#x2022; CONNECT
    </div>
    """
  end

  defp html_layout(title, subtitle, greeting, body, cta_label, cta_url, footer_note, lang \\ "en") do
    """
    <!DOCTYPE html>
    <html lang="#{lang}">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1.0">
      <title>#{title}</title>
    </head>
    <body style="margin:0;padding:0;background-color:#17140F;font-family:'Helvetica Neue',Helvetica,Arial,sans-serif;">
      <table width="100%" cellpadding="0" cellspacing="0" role="presentation"
             style="background-color:#17140F;">
        <tr>
          <td align="center" style="padding:48px 16px;">
            <table width="100%" cellpadding="0" cellspacing="0" role="presentation"
                   style="max-width:480px;">

              <!-- Logo -->
              <tr>
                <td align="center" style="padding-bottom:16px;">
                  #{brand_header()}
                </td>
              </tr>

              <!-- Wordmark -->
              <tr>
                <td align="center" style="padding-bottom:28px;">
                  #{wordmark()}
                </td>
              </tr>

              <!-- Title -->
              <tr>
                <td align="center" style="padding-bottom:6px;">
                  <h1 style="margin:0;font-family:Georgia,'Times New Roman',serif;color:#F4EEDD;font-size:26px;font-weight:700;letter-spacing:-0.2px;">
                    #{title}
                  </h1>
                </td>
              </tr>

              <!-- Subtitle -->
              <tr>
                <td align="center" style="padding-bottom:32px;">
                  <p style="margin:0;color:#8FDDCE;font-size:15px;">#{subtitle}</p>
                </td>
              </tr>

              <!-- Card -->
              <tr>
                <td style="background-color:#211D16;border:1px solid #2B2619;border-radius:20px;padding:32px 28px;">

                  <p style="margin:0 0 14px;color:#F4EEDD;font-size:15px;line-height:1.65;">
                    #{greeting}
                  </p>
                  <p style="margin:0 0 30px;color:#A9A08C;font-size:14px;line-height:1.7;">
                    #{body}
                  </p>

                  <!-- CTA button -->
                  <table width="100%" cellpadding="0" cellspacing="0" role="presentation">
                    <tr>
                      <td align="center" style="padding-bottom:28px;">
                        <a href="#{cta_url}"
                           style="display:inline-block;background-color:#E8622C;color:#17140F;
                                  text-decoration:none;font-weight:700;font-size:15px;
                                  padding:14px 36px;border-radius:9999px;
                                  border:1px solid #E8622C;">
                          #{cta_label}
                        </a>
                      </td>
                    </tr>
                  </table>

                  <!-- Fallback link -->
                  <p style="margin:0 0 4px;color:#6E6554;font-size:12px;">
                    If the button doesn't work, paste this link into your browser:
                  </p>
                  <p style="margin:0;">
                    <a href="#{cta_url}"
                       style="color:#E8622C;font-size:12px;word-break:break-all;text-decoration:none;">
                      #{cta_url}
                    </a>
                  </p>

                </td>
              </tr>

              <!-- Footer -->
              <tr>
                <td align="center" style="padding-top:28px;">
                  <p style="margin:0;color:#6E6554;font-size:12px;line-height:1.6;">
                    M3Hungry &mdash; #{footer_note}
                  </p>
                </td>
              </tr>

            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """
  end

  defp deliver(recipient, subject, text, html) do
    email =
      new()
      |> to(recipient)
      |> from({"Mehungry", "noreply@m3hungry.com"})
      |> subject(subject)
      |> text_body(text)
      |> html_body(html)

    case Mailer.deliver(email) do
      {:ok, _metadata} ->
        {:ok, email}

      {:error, reason} ->
        # Surface delivery failures (e.g. Mailgun rejecting a recipient or the
        # sending domain not being verified) instead of dropping them silently —
        # otherwise "no email arrived" is undiagnosable. Callers decide whether
        # to tell the user; this always logs the reason.
        Logger.error(
          "[UserNotifier] failed to deliver #{inspect(subject)} to #{inspect(recipient)}: " <>
            inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Send the account-confirmation email. `locale` ("en"/"el") selects the
  language — our audience is overwhelmingly Greek, so an English-only email was
  a likely cause of signups never confirming.
  """
  def deliver_confirmation_instructions(user, url, locale \\ "en")

  def deliver_confirmation_instructions(user, url, "el") do
    text = """
    Γεια σας #{user.email},

    Καλώς ήρθατε στο Mehungry! Επιβεβαιώστε τον λογαριασμό σας επισκεπτόμενοι τον παρακάτω σύνδεσμο:

    #{url}

    Ο σύνδεσμος λήγει σε 7 ημέρες. Αν δεν δημιουργήσατε λογαριασμό, μπορείτε να αγνοήσετε αυτό το email.
    """

    html =
      html_layout(
        "Επιβεβαιώστε τον λογαριασμό σας",
        "Ένα κλικ πριν εξερευνήσετε περισσότερα",
        "Γεια σας #{user.email},",
        "Καλώς ήρθατε στο Mehungry! Επιβεβαιώστε τον λογαριασμό σας πατώντας το κουμπί παρακάτω. Ο σύνδεσμος λήγει σε 7 ημέρες.",
        "Επιβεβαίωση λογαριασμού",
        url,
        "Αν δεν δημιουργήσατε λογαριασμό, μπορείτε να αγνοήσετε αυτό το email με ασφάλεια.",
        "el"
      )

    deliver(user.email, "Επιβεβαιώστε τον λογαριασμό σας στο Mehungry", text, html)
  end

  def deliver_confirmation_instructions(user, url, _locale) do
    text = """
    Hi #{user.email},

    Welcome to Mehungry! Please confirm your account by visiting the link below:

    #{url}

    This link expires in 7 days. If you didn't create an account, you can ignore this email.
    """

    html =
      html_layout(
        "Confirm your account",
        "One click away from exploring more",
        "Hi #{user.email},",
        "Welcome to Mehungry! Please confirm your account by clicking the button below. This link expires in 7 days.",
        "Confirm my account",
        url,
        "If you didn't create an account, you can safely ignore this email."
      )

    deliver(user.email, "Confirm your Mehungry account", text, html)
  end

  def deliver_reset_password_instructions(user, url) do
    text = """
    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.
    """

    html =
      html_layout(
        "Reset your password",
        "We'll get you back in no time",
        "Hi #{user.email},",
        "You requested a password reset for your Mehungry account. Click the button below to choose a new password. This link expires in 24 hours.",
        "Reset password",
        url,
        "If you didn't request a password reset, you can safely ignore this email."
      )

    deliver(user.email, "Reset your Mehungry password", text, html)
  end

  def deliver_update_email_instructions(user, url) do
    text = """
    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.
    """

    html =
      html_layout(
        "Update your email",
        "Confirm your new email address",
        "Hi #{user.email},",
        "You requested an email address change on your Mehungry account. Click the button below to confirm your new address.",
        "Confirm new email",
        url,
        "If you didn't request this change, you can safely ignore this email."
      )

    deliver(user.email, "Update your Mehungry email", text, html)
  end

  # ── Android beta opt-in invite ───────────────────────────────────────────────

  @doc """
  Default opt-in URL for the Android closed-testing programme, read from
  `config :mehungry, :android_beta`. The admin UI lets you override it per-send.
  """
  def android_beta_opt_in_url do
    :mehungry
    |> Application.get_env(:android_beta, [])
    |> Keyword.get(:opt_in_url, "")
  end

  @doc "Default Google Group address the beta invite is sent to."
  def android_beta_group_email do
    :mehungry
    |> Application.get_env(:android_beta, [])
    |> Keyword.get(:group_email, "")
  end

  @doc "The current beta version/build being distributed (for send tracking)."
  def android_beta_current_version do
    :mehungry
    |> Application.get_env(:android_beta, [])
    |> Keyword.get(:current_version, "")
  end

  @doc """
  Build the branded HTML for the Android beta opt-in invite. Shared by the
  admin preview pane and `deliver_android_beta_invite/2` so what's previewed is
  exactly what's sent.

  Options:
    * `:opt_in_url` — Google Play closed-testing opt-in link (defaults to config)
    * `:intro` — optional extra paragraph of copy from the admin
  """
  def android_beta_email_html(opts \\ []) do
    opt_in_url = Keyword.get(opts, :opt_in_url) || android_beta_opt_in_url()
    intro = opts |> Keyword.get(:intro, "") |> to_string() |> String.trim()

    intro_fragment =
      if intro != "" do
        "<p style=\"margin:0 0 18px;color:#F4EEDD;font-size:15px;line-height:1.65;\">" <>
          html_escape(intro) <> "</p>"
      else
        ""
      end

    body =
      intro_fragment <>
        "You're one of the first to try the <strong style=\"color:#F4EEDD;\">Mehungry</strong> " <>
        "app on Android — still in closed testing. Tap the button below to become a tester " <>
        "on Google Play, then install the app from the Play Store page that opens. It can take " <>
        "a few minutes after opting in before the app appears in the Store."

    html_layout(
      "Test the Mehungry Android app",
      "You're invited to our closed beta",
      "Hi there,",
      body,
      "Become a tester",
      opt_in_url,
      "You're receiving this because you signed up for early access to the Mehungry app."
    )
  end

  defp android_beta_text(opts) do
    opt_in_url = Keyword.get(opts, :opt_in_url) || android_beta_opt_in_url()
    intro = opts |> Keyword.get(:intro, "") |> to_string() |> String.trim()

    intro_block = if intro != "", do: intro <> "\n\n", else: ""

    """
    Hi there,

    #{intro_block}You're invited to test the Mehungry app on Android, still in closed testing.

    1. Become a tester: #{opt_in_url}
    2. Install Mehungry from the Google Play page that opens.

    It can take a few minutes after opting in before the app appears in the Store.

    You're receiving this because you signed up for early access to the Mehungry app.
    """
  end

  @doc """
  Send the Android beta opt-in invite to `recipient` (a single address — an
  individual tester or a Google Group address, which fans out to its members).

  Options are passed through to `android_beta_email_html/1` (`:opt_in_url`,
  `:intro`).
  """
  def deliver_android_beta_invite(recipient, opts \\ []) do
    html = android_beta_email_html(opts)
    text = android_beta_text(opts)
    deliver(recipient, "You're invited to test the Mehungry Android app", text, html)
  end

  @doc """
  Welcome email sent when someone registers on the public `/trial` page. Thanks
  them, tells them an invite is coming, and carries the one-click unsubscribe
  link (`unsubscribe_url`).
  """
  def deliver_trial_welcome(recipient, unsubscribe_url) do
    text = """
    Hi there,

    Thanks for signing up to test the Mehungry Android app! We're in closed
    testing and will email you an invitation to join soon.

    In the meantime, explore Mehungry on the web: https://www.m3hungry.com

    Changed your mind? Remove yourself anytime: #{unsubscribe_url}
    """

    footer_note =
      "You signed up to test the Mehungry app. " <>
        "Not interested anymore? " <>
        "<a href=\"#{unsubscribe_url}\" style=\"color:#E8622C;text-decoration:underline;\">" <>
        "Unsubscribe</a>."

    html =
      html_layout(
        "You're on the list!",
        "Thanks for signing up to test Mehungry",
        "Hi there,",
        "Thanks for your interest in testing the <strong style=\"color:#F4EEDD;\">Mehungry</strong> " <>
          "Android app! We're in closed testing and will email you an invitation to join soon. " <>
          "In the meantime, feel free to explore Mehungry on the web.",
        "Explore Mehungry",
        "https://www.m3hungry.com",
        footer_note
      )

    deliver(recipient, "Thanks for signing up to test Mehungry", text, html)
  end

  # ── Nutritionist client onboarding invite ────────────────────────────────────

  @doc """
  Invite a not-yet-registered person to join Mehungry as a nutritionist's client.

  Sent when a nutritionist invites a client by an email that has no account yet:
  a login-less managed account has already been created and assigned to them, and
  `claim_url` is the `/claim/:token` link that lets the recipient set a password
  and take over that account (landing them already connected to the nutritionist).

  `professional_name` personalises the copy; `personal_message` is the optional
  note the nutritionist typed, shown as a quoted intro.
  """
  def deliver_client_onboarding_invite(recipient, professional_name, claim_url, personal_message \\ nil) do
    note = personal_message |> to_string() |> String.trim()

    intro_fragment =
      if note != "" do
        "<p style=\"margin:0 0 18px;color:#F4EEDD;font-size:15px;line-height:1.65;" <>
          "border-left:3px solid #E8622C;padding-left:14px;font-style:italic;\">" <>
          html_escape(note) <> "</p>"
      else
        ""
      end

    body =
      intro_fragment <>
        "<strong style=\"color:#F4EEDD;\">#{html_escape(professional_name)}</strong> uses " <>
        "Mehungry to help their clients eat well and has invited you to join. Create your " <>
        "account to connect with them, follow the meal plans they build for you, and track " <>
        "your own nutrition."

    text = """
    Hi there,

    #{if note != "", do: note <> "\n\n", else: ""}#{professional_name} uses Mehungry to help their clients eat well and has invited you to join.

    Create your account here to connect with them:

    #{claim_url}
    """

    html =
      html_layout(
        "You're invited to Mehungry",
        "#{professional_name} would like to connect with you",
        "Hi there,",
        body,
        "Create my account",
        claim_url,
        "You're receiving this because #{html_escape(professional_name)} invited you to Mehungry as their client."
      )

    deliver(recipient, "#{professional_name} invited you to join Mehungry", text, html)
  end

  # ── Appointment notifications ────────────────────────────────────────────────

  @doc """
  Notify the nutritionist that a client requested an appointment.
  `appointment` must have `:professional` and `:client` preloaded.
  `cta_url` links to their appointments dashboard.
  """
  def deliver_appointment_requested(appointment, client_name, cta_url) do
    prof = appointment.professional
    when_str = format_dt(appointment.scheduled_at)

    text = """
    Hi,

    #{client_name} requested an appointment with you on Mehungry.

    When: #{when_str}
    Notes: #{appointment.notes || "—"}

    Review and accept it here: #{cta_url}
    """

    html =
      html_layout(
        "New appointment request",
        "A client would like to meet",
        "Hi #{prof.email},",
        "#{client_name} requested an appointment for <strong>#{when_str}</strong>." <>
          notes_fragment(appointment) <>
          " Open your appointments to accept or decline — the client is notified only once you accept.",
        "Review request",
        cta_url,
        "You're receiving this because you offer consultations on Mehungry."
      )

    deliver(prof.email, "New appointment request on Mehungry", text, html)
  end

  @doc """
  Notify the client that the nutritionist accepted — attaches a calendar
  invite (.ics). `appointment` must have `:professional` and `:client` preloaded.
  """
  def deliver_appointment_accepted(appointment, professional_name, cta_url) do
    client = appointment.client
    when_str = format_dt(appointment.scheduled_at)
    meeting = appointment.meeting_url

    ics =
      Mehungry.Professionals.ICS.build(appointment,
        attendee_email: client.email,
        summary: "Consultation with #{professional_name}"
      )

    {cta_label, cta_target} =
      if meeting && meeting != "",
        do: {"Join the video call", meeting},
        else: {"Open Mehungry", cta_url}

    text = """
    Hi #{client.email},

    #{professional_name} accepted your appointment request.

    When: #{when_str}
    #{if meeting && meeting != "", do: "Video call: #{meeting}", else: ""}

    A calendar invite is attached to this email.
    """

    html =
      html_layout(
        "Your appointment is confirmed",
        "#{professional_name} accepted your request",
        "Hi #{client.email},",
        "Your appointment with <strong>#{professional_name}</strong> is confirmed for " <>
          "<strong>#{when_str}</strong>." <>
          if(meeting && meeting != "",
            do: " A video call link is included below and in the attached calendar invite.",
            else: " A calendar invite is attached to this email."
          ),
        cta_label,
        cta_target,
        "Add the attached invite to your calendar so you don't miss it."
      )

    deliver_with_ics(client.email, "Your Mehungry appointment is confirmed", text, html, ics)
  end

  @doc "Notify the client that the nutritionist declined the request."
  def deliver_appointment_declined(appointment, professional_name, cta_url) do
    client = appointment.client
    when_str = format_dt(appointment.scheduled_at)

    text = """
    Hi #{client.email},

    Unfortunately #{professional_name} can't take your appointment on #{when_str}.
    You can pick another time here: #{cta_url}
    """

    html =
      html_layout(
        "Appointment not available",
        "Let's find another time",
        "Hi #{client.email},",
        "Unfortunately <strong>#{professional_name}</strong> isn't able to meet on " <>
          "<strong>#{when_str}</strong>. You can browse their availability and request another slot.",
        "Pick another time",
        cta_url,
        "No charge was made for this request."
      )

    deliver(client.email, "Update on your Mehungry appointment", text, html)
  end

  # Escape admin-supplied free text before interpolating it into the HTML body.
  defp html_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp notes_fragment(%{notes: notes}) when is_binary(notes) and notes != "",
    do: " Their note: “#{notes}”."

  defp notes_fragment(_), do: ""

  defp format_dt(%NaiveDateTime{} = ndt) do
    Calendar.strftime(ndt, "%A %-d %B %Y, %H:%M UTC")
  end

  defp deliver_with_ics(recipient, subject, text, html, ics_string) do
    email =
      new()
      |> to(recipient)
      |> from({"Mehungry", "noreply@m3hungry.com"})
      |> subject(subject)
      |> text_body(text)
      |> html_body(html)
      |> attachment(
        Swoosh.Attachment.new({:data, ics_string},
          filename: "appointment.ics",
          content_type: "text/calendar",
          type: :attachment
        )
      )

    case Mailer.deliver(email) do
      {:ok, _metadata} ->
        {:ok, email}

      {:error, reason} ->
        Logger.error(
          "[UserNotifier] failed to deliver #{inspect(subject)} to #{inspect(recipient)}: " <>
            inspect(reason)
        )

        {:error, reason}
    end
  end
end
