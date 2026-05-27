# lib/your_app_web/live/json_viewer_component.ex
defmodule MehungryWeb.JsonViewerComponent do
  use Phoenix.LiveComponent
  import Phoenix.Component

  @url_regex ~r/^(https?:\/\/)?([\w.-]+)+(:\d+)?(\/[\w\-._~:\/?#[\]@!$&'()*+,;=]*)?$/
  @image_regex ~r/\.(jpg|jpeg|png|gif|webp|svg)(\?.*)?$/i

  def valid_url?(url) when is_binary(url) do
    Regex.match?(@url_regex, url)
  end

  def valid_img?(url) when is_binary(url) do
    Regex.match?(@image_regex, url)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-gray-100 p-4 rounded overflow-auto  font-mono text-sm">
      <.json_render data={@json} />
    </div>
    """
  end

  defp json_render(%{data: data} = assigns) when is_list(data) and not is_bitstring(data) do
    ~H"""
    <ul class="pl-4 list-decimal">
      <%= for item <- @data do %>
        <li><.json_render data={item} /></li>
      <% end %>
    </ul>
    """
  end

  defp json_render(%{data: data} = assigns) when is_binary(data) do
    ~H"""
    <%= case valid_url?(data) do %>
      <% false -> %>
        <span>{data}</span>
      <% true -> %>
        <%= case valid_img?(data) do %>
          <% true -> %>
            <img src={data} />
          <% false -> %>
            <span>{data}</span>
        <% end %>
    <% end %>
    <span>{inspect(data)}</span>
    """
  end

  defp json_render(%{data: data} = assigns) when is_nil(data) do
    ~H"""
    <span>{inspect(data)}</span>
    """
  end

  # Recursive rendering of the JSON
  defp json_render(%{data: data} = assigns) do
    ~H"""
    <ul class="pl-4 list-disc">
      <%= for {key, value} <- data do %>
        <li>
          <strong>{Atom.to_string(key)}:</strong> <.json_render data={value} />
        </li>
      <% end %>
    </ul>
    """
  end
end
