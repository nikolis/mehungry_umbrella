defmodule MehungryApi.AnnotationView do
  use MehungryApi, :view

  def render("annotation.json", %{annotation: annotation}) do
    %{
      id: annotation.id,
      body: annotation.body,
      at: annotation.at,
      user: render_one(annotation.user, MehungryApi.UserView, "user.json")
    }
  end
end
