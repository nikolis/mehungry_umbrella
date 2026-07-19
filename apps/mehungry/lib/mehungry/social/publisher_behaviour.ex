defmodule Mehungry.Social.PublisherBehaviour do
  @moduledoc """
  Contract between `Mehungry.ObanWorkers.RecipePublishWorker` (core app) and the
  publisher implementation (web app), resolved at runtime via the
  `:social_media_publisher` app config key. Tests wire a stub here.
  """

  @type platform_result :: :ok | :skipped | {:error, term()}

  @callback publish_recipe(
              recipe :: struct(),
              bot_user :: struct(),
              ai_bot_recipe_id :: integer(),
              language_name :: String.t(),
              opts :: map()
            ) :: %{optional(atom()) => platform_result()}
end
