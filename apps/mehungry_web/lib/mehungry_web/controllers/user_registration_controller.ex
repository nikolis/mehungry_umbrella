defmodule MehungryWeb.UserRegistrationController do
  use MehungryWeb, :controller

  alias Mehungry.Accounts
  alias Mehungry.Accounts.User
  alias MehungryWeb.Turnstile

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%User{})

    render(conn, "new.html",
      changeset: changeset,
      turnstile_site_key: Turnstile.site_key(),
      page_title: "Create Your Free Account"
    )
  end

  def create(conn, %{"user" => user_params} = params) do
    token = params["cf-turnstile-response"]

    case Turnstile.verify(token, client_ip(conn)) do
      :ok ->
        register(conn, user_params)

      {:error, _reason} ->
        # Re-render the form (preserving what was entered) instead of redirecting,
        # so the user sees why the submission didn't go through.
        changeset = Accounts.change_user_registration(%User{}, user_params)

        conn
        |> put_flash(:error, "Captcha verification failed. Please try again.")
        |> render("new.html",
          changeset: changeset,
          turnstile_site_key: Turnstile.site_key(),
          page_title: "Create Your Free Account"
        )
    end
  end

  defp register(conn, user_params) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        # Send the confirmation email in the visitor's locale (our audience is
        # overwhelmingly Greek). A delivery failure must not crash the request
        # after the account already exists — but it must not be silently
        # swallowed either: if Mailgun rejects it, tell the user so they can
        # resend, rather than sending them to wait for an email that never comes.
        delivery =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &Routes.user_confirmation_url(conn, :edit, &1),
            MehungryWeb.Locale.detect(conn)
          )

        conn
        |> put_flash(:ga_event, Jason.encode!(%{name: "sign_up", params: %{method: "email"}}))
        |> confirmation_flash(delivery)
        |> redirect(to: Routes.user_session_path(conn, :new))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html",
          changeset: changeset,
          turnstile_site_key: Turnstile.site_key(),
          page_title: "Create Your Free Account"
        )
    end
  end

  # Flash message depends on whether the confirmation email actually went out.
  # On failure we point the user at the login page, which resends the link on
  # the next sign-in attempt (and now shows a "resend" link).
  defp confirmation_flash(conn, {:ok, _email}) do
    put_flash(
      conn,
      :info,
      "Account created! Please check your email to confirm your account before logging in."
    )
  end

  defp confirmation_flash(conn, _error) do
    put_flash(
      conn,
      :error,
      "Account created, but we couldn't send the confirmation email just now. " <>
        "Try logging in to resend the confirmation link."
    )
  end

  # Behind the ALB, conn.remote_ip is the load balancer, so prefer the first hop
  # of x-forwarded-for (matches MehungryWeb.Presence's approach).
  defp client_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] ->
        forwarded |> String.split(",") |> List.first() |> String.trim()

      [] ->
        conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
