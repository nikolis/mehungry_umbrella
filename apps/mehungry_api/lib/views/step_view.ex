defmodule MehungryApi.StepView do
  use MehungryApi, :view

  def render("step.json", %{step: step}) do
    %{
      title: step.title,
      description: step.description
    }
  end
end
