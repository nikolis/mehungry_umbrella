defmodule MehungryApi.LoginController do
  use MehungryApi, :controller

  alias MehungryApi.Guardian

  alias Mehungry.Accounts
  alias Mehungry.Accounts.User

  action_fallback(MehungryApi.FallbackController)

  def login_with_credential(conn, %{
        "credential" => %{"email" => email, "password" => pass, "captcha_token" => google_token}
      }) do
    case Accounts.authenticate_by_email_and_pass(email, pass) do
      {:ok, user} ->
        with {:ok, jwt, _claim} <- Guardian.encode_and_sign(user) do
          IO.inspect(jwt)

          conn
          |> render("jwt.json", %{jwt: jwt, user: user})
        end

      {:error, reason} ->
        conn
        |> render("auth_error.json", %{email: email})
    end
  end

  def login_by_facebook_token(conn, %{"user_id" => user_id, "token" => token}) do
    case validate_facebook_user(token) do
      {:ok, user_params} ->
        fb_id = user_params["facebook_id"]
        result = Accounts.get_user_by_fb_id(fb_id)

        case result do
          %User{} = ret_user ->
            with {:ok, jwt, _claim} <- Guardian.encode_and_sign(ret_user) do
              IO.inspect(jwt)

              conn
              |> render("jwt.json", %{jwt: jwt, user_id: ret_user.id})
            end

          _ ->
            with {:ok, %User{} = user} <- Accounts.create_user(user_params),
                 {:ok, jwt, _claims} <- Guardian.encode_and_sign(user) do
              conn
              |> render("jwt.json", %{jwt: jwt, user_id: user.id})
            end
        end

      %{error: problem} ->
        conn
        |> render("jwt.json", email: "blank")
    end
  end

  def fb_token_validation(token) do
    uri =
      URI.to_string(%URI{
        scheme: "https",
        host: "graph.facebook.com/",
        path:
          "debug_token?input_token=#{token}&access_token=902631176539278|CBzcAzROucHU1sX8tWBlObKvHc4"
      })
  end

  def fb_user_details(token) do
    uri =
      URI.to_string(%URI{
        scheme: "https",
        host: "graph.facebook.com/",
        path: "me/?fields=id,first_name,name,last_name,email&access_token=#{token}"
      })
  end

  def validate_facebook_user(token) do
    url =
      fb_token_validation(token)
      |> HTTPoison.get()

    case url do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body_map = Poison.decode!(body)
        data_map = body_map["data"]

        case data_map do
          %{"app_id" => "902631176539278", "is_valid" => true} ->
            user_details =
              fb_user_details(token)
              |> HTTPoison.get()

            case user_details do
              {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
                dec_body = Poison.decode!(body)
                {fb_id, dec_body} = Map.pop(dec_body, "id")
                result = Map.put_new(dec_body, "facebook_id", fb_id)
                {:ok, result}

              {_, _} ->
                %{error: "stjing 3rd else"}
            end

          _ ->
            %{error: "sthing else"}
        end

      {_, _} ->
        %{error: "email not valid"}
    end
  end
end
