defmodule Mehungry.Accounts.UserNotifier do
  @moduledoc false

  import Swoosh.Email
  alias Mehungry.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Mehungry", "noreply@mehungry.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirm your Mehungry account", """
    Hi #{user.email},

    Welcome to Mehungry! Please confirm your account by clicking the link below:

    #{url}

    This link expires in 24 hours. If you didn't create an account, you can ignore this email.
    """)
  end

  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset your Mehungry password", """
    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.
    """)
  end

  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update your Mehungry email", """
    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.
    """)
  end
end
