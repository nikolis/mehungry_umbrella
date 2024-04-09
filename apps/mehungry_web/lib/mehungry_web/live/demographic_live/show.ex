defmodule MehungryWeb.DemographicLive.Show do
  use Phoenix.Component
  import Phoenix.HTML
  import Phoenix.HTML.Form
  use PhoenixHTMLHelpers

  def details(assigns) do
    ~H"""
    <div class="survey-component-container">
      <h2>Demographics <%= raw "&#x2713;" %></h2>
      <ul>
        <li>Capacity: <%= @demographic.capacity %></li>
        <li>Year of birth: <%= @demographic.year_of_birth %></li>
      </ul>
    </div>
    """
  end
end
