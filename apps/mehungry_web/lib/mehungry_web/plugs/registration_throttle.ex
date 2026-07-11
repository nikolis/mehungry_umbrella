defmodule MehungryWeb.Plugs.RegistrationThrottle do
  @moduledoc """
  Per-IP fixed-window rate limit on account registration, to blunt scripted
  signups (e.g. Gmail-alias account farming). Backed by `Mehungry.RateLimit`.

  Only throttles the POST (submit); GET requests to render the form pass
  through. On limit breach, re-renders the registration form with an error flash
  instead of processing the signup.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3]

  alias Mehungry.RateLimit

  # Max signup POSTs allowed from one IP per window.
  @limit 5
  @window_ms :timer.minutes(10)

  def init(opts), do: opts

  def call(%Plug.Conn{method: "POST"} = conn, _opts) do
    key = "register:" <> client_ip(conn)

    case RateLimit.hit(key, @limit, @window_ms) do
      :ok ->
        conn

      {:error, :rate_limited} ->
        conn
        |> put_flash(:error, "Too many sign-up attempts. Please try again in a few minutes.")
        |> Phoenix.Controller.redirect(to: "/register")
        |> halt()
    end
  end

  def call(conn, _opts), do: conn

  # Behind the ALB, conn.remote_ip is the load balancer, so prefer the first hop
  # of x-forwarded-for (matches MehungryWeb.Presence's approach).
  defp client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] ->
        forwarded |> String.split(",") |> List.first() |> String.trim()

      [] ->
        conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
