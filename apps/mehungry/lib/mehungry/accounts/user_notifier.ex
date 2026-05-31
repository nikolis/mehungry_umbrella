defmodule Mehungry.Accounts.UserNotifier do
  @moduledoc false

  import Swoosh.Email
  alias Mehungry.Mailer

  defp logo_svg do
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 450 120" width="300" height="80">
      <defs>
        <linearGradient id="em_top" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#FBBF24" />
          <stop offset="50%" stop-color="#F97316" />
          <stop offset="100%" stop-color="#EA580C" />
        </linearGradient>
        <linearGradient id="em_mid" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#F97316" />
          <stop offset="50%" stop-color="#EA580C" />
          <stop offset="100%" stop-color="#C2410C" />
        </linearGradient>
        <linearGradient id="em_bot" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#EA580C" />
          <stop offset="100%" stop-color="#7C2D12" />
        </linearGradient>
      </defs>
      <polygon points="60,95 80,82 100,95 100,115 80,128 60,115" fill="url(#em_bot)" />
      <polygon points="80,82 100,95 80,108 60,95" fill="#7C2D12" opacity="0.7" />
      <polygon points="80,65 100,52 120,65 120,85 100,98 80,85" fill="url(#em_mid)" />
      <polygon points="100,52 120,65 100,78 80,65" fill="#C2410C" opacity="0.7" />
      <polygon points="100,38 120,25 140,38 140,58 120,71 100,58" fill="url(#em_top)" />
      <polygon points="120,25 140,38 120,51 100,38" fill="#F97316" opacity="0.8" />
      <line x1="100" y1="58" x2="100" y2="78" stroke="#FBBF24" stroke-width="2" stroke-dasharray="3,3" />
      <line x1="80" y1="65" x2="80" y2="82" stroke="#FBBF24" stroke-width="2" stroke-dasharray="3,3" />
      <line x1="120" y1="52" x2="120" y2="65" stroke="#FBBF24" stroke-width="2" stroke-dasharray="3,3" />
      <text x="160" y="65"
            font-family="'Inter',system-ui,-apple-system,sans-serif"
            font-size="38" font-weight="800" fill="#F8FAFC" letter-spacing="2">
        M3<tspan fill="#EA580C">HUNGRY</tspan>
      </text>
      <text x="160" y="88"
            font-family="'Inter',system-ui,-apple-system,sans-serif"
            font-size="11" fill="#64748B" letter-spacing="3">
        ANALYZE &#x2022; SHARE &#x2022; CONNECT
      </text>
    </svg>
    """
  end

  defp html_layout(title, subtitle, greeting, body, cta_label, cta_url, footer_note) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width,initial-scale=1.0">
      <title>#{title}</title>
    </head>
    <body style="margin:0;padding:0;background-color:#0F172A;font-family:'Helvetica Neue',Helvetica,Arial,sans-serif;">
      <table width="100%" cellpadding="0" cellspacing="0" role="presentation"
             style="background-color:#0F172A;">
        <tr>
          <td align="center" style="padding:48px 16px;">
            <table width="100%" cellpadding="0" cellspacing="0" role="presentation"
                   style="max-width:480px;">

              <!-- Logo -->
              <tr>
                <td align="center" style="padding-bottom:20px;">
                  #{logo_svg()}
                </td>
              </tr>

              <!-- Title -->
              <tr>
                <td align="center" style="padding-bottom:6px;">
                  <h1 style="margin:0;color:#F8FAFC;font-size:26px;font-weight:800;letter-spacing:-0.4px;">
                    #{title}
                  </h1>
                </td>
              </tr>

              <!-- Subtitle -->
              <tr>
                <td align="center" style="padding-bottom:32px;">
                  <p style="margin:0;color:rgba(119,178,85,0.7);font-size:15px;">#{subtitle}</p>
                </td>
              </tr>

              <!-- Card -->
              <tr>
                <td style="background-color:#1E293B;border-radius:20px;padding:32px 28px;">

                  <p style="margin:0 0 14px;color:#CBD5E1;font-size:15px;line-height:1.65;">
                    #{greeting}
                  </p>
                  <p style="margin:0 0 30px;color:#94A3B8;font-size:14px;line-height:1.7;">
                    #{body}
                  </p>

                  <!-- CTA button -->
                  <table width="100%" cellpadding="0" cellspacing="0" role="presentation">
                    <tr>
                      <td align="center" style="padding-bottom:28px;">
                        <a href="#{cta_url}"
                           style="display:inline-block;background-color:#77b255;color:#ffffff;
                                  text-decoration:none;font-weight:700;font-size:15px;
                                  padding:14px 36px;border-radius:9999px;
                                  border:1px solid #77b255;">
                          #{cta_label}
                        </a>
                      </td>
                    </tr>
                  </table>

                  <!-- Fallback link -->
                  <p style="margin:0 0 4px;color:#475569;font-size:12px;">
                    If the button doesn't work, paste this link into your browser:
                  </p>
                  <p style="margin:0;">
                    <a href="#{cta_url}"
                       style="color:#77b255;font-size:12px;word-break:break-all;text-decoration:none;">
                      #{cta_url}
                    </a>
                  </p>

                </td>
              </tr>

              <!-- Footer -->
              <tr>
                <td align="center" style="padding-top:28px;">
                  <p style="margin:0;color:#334155;font-size:12px;line-height:1.6;">
                    Mehungry &mdash; #{footer_note}
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

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  def deliver_confirmation_instructions(user, url) do
    text = """
    Hi #{user.email},

    Welcome to Mehungry! Please confirm your account by visiting the link below:

    #{url}

    This link expires in 24 hours. If you didn't create an account, you can ignore this email.
    """

    html =
      html_layout(
        "Confirm your account",
        "One click away from exploring more",
        "Hi #{user.email},",
        "Welcome to Mehungry! Please confirm your account by clicking the button below. This link expires in 24 hours.",
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
end
