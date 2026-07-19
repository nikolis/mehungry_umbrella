defmodule Mehungry.Social.PublisherStub do
  @moduledoc """
  Test stand-in for `MehungryWeb.SocialMediaPublisher` (wired up via the
  `:social_media_publisher` config key in `config/test.exs`).

  Tests control the result and observe calls through app config:

      Application.put_env(:mehungry, :publisher_stub, fn _recipe, _bot_user, _id, _lang, opts ->
        send(test_pid, {:publish_recipe, opts})
        %{instagram: :ok, facebook: :ok, pinterest: :ok}
      end)
      on_exit(fn -> Application.delete_env(:mehungry, :publisher_stub) end)
  """

  @behaviour Mehungry.Social.PublisherBehaviour

  @impl true
  def publish_recipe(recipe, bot_user, ai_bot_recipe_id, language_name, opts) do
    case Application.get_env(:mehungry, :publisher_stub) do
      nil -> %{instagram: :ok, facebook: :ok, pinterest: :ok}
      fun -> fun.(recipe, bot_user, ai_bot_recipe_id, language_name, opts)
    end
  end
end
