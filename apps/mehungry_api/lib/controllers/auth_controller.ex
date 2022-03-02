defmodule MehungryApi.AuthController do
  use MehungryApi, :controller
  use OpenApiSpex.ControllerSpecs

  alias Mehungry.Accounts
  alias MehungryApi.Guardian

  alias MehungryApi.Schemas.{
    RegisterUserParams,
    RegisterUserResponse,
    LoginWithCredentialsParams,
    LoginResponse
  }

  action_fallback(MehungryApi.FallbackController)

  operation(:register_user,
    summary: "Register user",
    request_body: {"User params", "application/json", RegisterUserParams},
    responses: [
      created: {"User response", "application/json", RegisterUserResponse}
    ]
  )

  def register_user(conn, %{"user" => user_params}) do
    with {:ok, user} <- Accounts.register_user(user_params) do
      # token = GreekCoin.Token.generate_new_account_token(user)
      # verification_url = user_url(token)
      # verification_email = Email.email_verification_email(user, verification_url)
      # mail_sent = Mailer.deliver_now verification_email
      conn
      |> put_status(:created)
      |> render("show.json", user: user)
    end
  end

  operation(:login_with_credential,
    summary: "Login with user credntials get jwt to access the apis",
    request_body: {"User params", "application/json", LoginWithCredentialsParams},
    responses: [
      ok: {"LoginResponse", "application/json", LoginResponse}
    ]
  )

  def login_with_credential(conn, %{
        "credential" => %{"email" => email, "password" => pass}
      }) do
    case Accounts.get_user_by_email_and_password(email, pass) do
      {:ok, user} ->
        with {:ok, jwt, _claim} <- Guardian.encode_and_sign(user) do
          conn
          |> render("jwt.json", %{jwt: jwt, user: user})
        end

      {:error, reason} ->
        conn
        |> render("auth_error.json", %{email: email})
    end
  end
end
