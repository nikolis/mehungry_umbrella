defmodule MehungryWeb.ProfessionalLive.Ingredients do
  use MehungryWeb, :live_view

  alias Mehungry.Food

  alias MehungryWeb.{DemographicLive, RatingLive, Endpoint}
  @survey_results_topic "survey_results"

  alias __MODULE__.Component

  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
