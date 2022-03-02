defmodule MehungryApi.AuthView do
  use MehungryApi, :view

  def render("show.json", %{user: user}) do
    %{data: render_one(user, MehungryApi.AuthView, "user.json", as: :user)}
  end

  def render("user.json", %{user: user}) do
    %{
      id: user.id,
      email: user.email
      # user_name: user.name,
      # facebook_id: user.facebook_id,
      # first_name: user.first_name,
      # last_name: user.last_name
    }
  end

  def render("jwt.json", login) do
    %{
      jwt: login.jwt
    }
  end

  def render("auth_error.json", %{email: email}) do
    %{
      error: "email password combination not correct"
    }
  end

  def render("captcha_error.json", %{msg: msg}) do
    %{
      error: "captcha not verified"
    }
  end

  def render("show.json", %{user: user}) do
    %{
      data: %{
        name: user.name,
        last_name: user.last_name,
        facebook_id: user.facebook_id,
        first_name: user.first_name
      }
    }
  end
end
