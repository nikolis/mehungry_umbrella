defmodule MehungryWeb.CreateRecipeLive.Show do
  use MehungryWeb, :live_view
  use MehungryWeb.Searchable, :transfers_to_search

  alias Mehungry.Food
  alias Mehungry.Food.{Recipe}

  alias Mehungry.Food.Recipe
  alias Mehungry.Accounts
  alias MehungryWeb.CreateRecipeLive.Components
  alias MehungryWeb.SimpleS3Upload

  def mount_search(_params, session, socket) do
    {:ok, socket}
  end
end
