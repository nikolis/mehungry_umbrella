defmodule MehungryApi.Guardian.AuthPipeline do
  use Guardian.Plug.Pipeline,
    otp_app: :mehungry_api,
    module: MehungryApi.Guardian,
    error_handler: MehungryApi.AuthErrorHandler

  plug(Guardian.Plug.VerifyHeader, realm: "Bearer")
  plug(Guardian.Plug.EnsureAuthenticated)
  plug(Guardian.Plug.LoadResource)
end
