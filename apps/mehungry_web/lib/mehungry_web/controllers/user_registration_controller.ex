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
        conn
        |> put_flash(:error, "Captcha verification failed. Please try again.")
        |> redirect(to: Routes.user_registration_path(conn, :new))
    end
  end

  defp register(conn, user_params) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &Routes.user_confirmation_url(conn, :edit, &1)
          )

        conn
        |> put_flash(:ga_event, Jason.encode!(%{name: "sign_up", params: %{method: "email"}}))
        |> put_flash(
          :info,
          "Account created! Please check your email to confirm your account before logging in."
        )
        |> redirect(to: Routes.user_session_path(conn, :new))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html",
          changeset: changeset,
          turnstile_site_key: Turnstile.site_key(),
          page_title: "Create Your Free Account"
        )
    end
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
