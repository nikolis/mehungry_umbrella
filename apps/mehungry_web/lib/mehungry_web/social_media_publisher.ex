defmodule MehungryWeb.SocialMediaPublisher do
  @moduledoc """
  Deprecated: the publisher lives in `Mehungry.SocialMediaPublisher`.

  This shim remains only in case an environment's `:social_media_publisher`
  config still names this module. New code should use the core module.
  """

  @behaviour Mehungry.SocialMediaPublisherBehaviour

  @impl true
  defdelegate publish_recipe(recipe, bot_user, ai_bot_recipe_id, language_name, opts \\ %{}),
    to: Mehungry.SocialMediaPublisher
end
