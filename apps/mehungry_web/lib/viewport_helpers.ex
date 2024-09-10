defmodule ViewportHelpers do
  alias Phoenix.{View}

  # in sync with css/shared/_media_queries.scss
  @mobile_max_width 480

  @desktop_kind :desktop
  @mobile_kind :mobile

  defmacro __using__(_) do
    quote do
      import ViewportHelpers

      def handle_event("viewport_resize", viewport, socket) do
        device_kind = viewport |> Map.get("width") |> device_kind_for_width()

        {:noreply,
         Phoenix.Component.assign(socket, device_kind: device_kind)
         |> Phoenix.Component.assign(socket, width: Map.get(viewport, "width"))}
      end
    end
  end

  def assign_device_kind(socket) do
    intermidiate =
      socket.private
      |> get_in([:connect_params, "viewport", "width"])

    device_kind = device_kind_for_width(intermidiate)

    Phoenix.Component.assign(socket, device_kind: device_kind)
    |> Phoenix.Component.assign(device_width: intermidiate)
  end

  def render_for_device(module, template, assigns = %{device_kind: device_kind}) do
    template = String.replace(template, ".html", ".#{device_kind}.html")
    View.render(module, template, assigns)
  end

  def render_for_device(module, template, assigns) do
    View.render(module, template, assigns)
  end

  def device_kind_for_width(width) when is_integer(width) and width <= @mobile_max_width do
    @mobile_kind
  end

  def device_kind_for_width(_width), do: @desktop_kind
end
