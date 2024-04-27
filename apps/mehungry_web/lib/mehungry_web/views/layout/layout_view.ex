defmodule MehungryWeb.LayoutView do
  use MehungryWeb, :html
  import Phoenix.HTML.Form

  embed_templates "templates/*"
  embed_templates "templates/menu/*"

  def get_main_content_container_class(conn) do
    "main-content-container"
  end
end
