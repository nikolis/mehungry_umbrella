defmodule Mehungry.AiBot.Notifier do
  import Swoosh.Email
  alias Mehungry.Mailer

  @admin_email "nikolisgal@gmail.com"

  def deliver_recipes_ready(recipe_count, review_url) do
    date = Date.add(Date.utc_today(), 1) |> Date.to_string()

    text = """
    Hi Admin,

    #{recipe_count} AI bot recipes for #{date} are ready for review.

    Visit the review queue: #{review_url}

    Please approve or reject each recipe before their scheduled publish time.
    """

    html = """
    <!DOCTYPE html>
    <html lang="en">
    <head><meta charset="utf-8"><title>Recipes Ready for Review</title></head>
    <body style="margin:0;padding:0;background-color:#0F172A;font-family:'Helvetica Neue',Helvetica,Arial,sans-serif;">
      <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="background-color:#0F172A;">
        <tr>
          <td align="center" style="padding:48px 16px;">
            <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="max-width:480px;">
              <tr>
                <td style="background-color:#1E293B;border-radius:20px;padding:32px 28px;">
                  <h1 style="margin:0 0 12px;color:#F8FAFC;font-size:22px;font-weight:800;">
                    #{recipe_count} Recipes Ready for Review
                  </h1>
                  <p style="margin:0 0 24px;color:#94A3B8;font-size:14px;line-height:1.7;">
                    The AI bot has generated #{recipe_count} recipes scheduled for <strong style="color:#F8FAFC;">#{date}</strong>.
                    Please review and approve them before their scheduled publish times.
                  </p>
                  <table width="100%" cellpadding="0" cellspacing="0" role="presentation">
                    <tr>
                      <td align="center">
                        <a href="#{review_url}"
                           style="display:inline-block;background-color:#77b255;color:#ffffff;
                                  text-decoration:none;font-weight:700;font-size:15px;
                                  padding:14px 36px;border-radius:9999px;">
                          Review Recipes
                        </a>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>
              <tr>
                <td align="center" style="padding-top:28px;">
                  <p style="margin:0;color:#334155;font-size:12px;">
                    Mehungry AI Bot &mdash; automated daily recipe review
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

    email =
      new()
      |> to(@admin_email)
      |> from({"Mehungry Bot", "noreply@m3hungry.com"})
      |> subject("#{recipe_count} AI recipes ready for review — #{date}")
      |> text_body(text)
      |> html_body(html)

    Mailer.deliver(email)
  end
end
