defmodule MehungryWeb.LayoutView do
  use MehungryWeb, :html

  embed_templates "templates/*"
  embed_templates "templates/menu/*"

  def get_main_content_container_class(_conn) do
    "main-content-container"
  end
end
