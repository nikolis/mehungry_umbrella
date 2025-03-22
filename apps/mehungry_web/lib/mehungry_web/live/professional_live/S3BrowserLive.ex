defmodule MehungryWeb.ProfessionalLive.S3BrowserLive do
 
  use Phoenix.LiveView
  alias Mehungry.S3Manager

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket,
      bucket_name: "",
      objects: [],
      prefix: nil, 
      loading: false,
      error: nil
    )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-4">
      <h1 class="text-2xl font-bold mb-4">AWS S3 Browser</h1>
      
      <div class="flex mb-4">
        <div class="flex-1 mr-2">
          <form phx-submit="list_objects" class="flex">
            <input 
              type="text" 
              name="bucket_name" 
              value={@bucket_name} 
              placeholder="Enter bucket name" 
              class="flex-1 px-3 py-2 border border-gray-300 rounded-l-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              phx-debounce="300"
            />
            <button 
              type="submit" 
              class="px-4 py-2 bg-blue-500 text-white rounded-r-md hover:bg-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
              disabled={@loading}
            >
              <%= if @loading, do: "Loading...", else: "List Files" %>
            </button>
            
          </form>
        </div>
        
        <%= if @bucket_name != "" do %>
          <div class="flex-none">
              <button 
                phx-click="load-ingredients" 
                phx-value-bucket_name={@bucket_name}
              class="px-4 py-2 bg-blue-500 text-white rounded-r-md hover:bg-red-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
              disabled={@loading}
            >
              <%= if @loading, do: "Loading...", else: "Load ingredients" %>
            </button>

            <button 
              phx-click="refresh" 
              class="px-4 py-2 bg-green-500 text-white rounded-md hover:bg-green-600 focus:outline-none focus:ring-2 focus:ring-green-500"
              disabled={@loading}
            >
              Refresh
            </button>
          </div>
        <% end %>
      </div>

      <%= if @prefix do %>
        <div class="mb-4">
          <button 
            phx-click="navigate_up" 
            class="px-3 py-1 bg-gray-200 text-gray-700 rounded-md hover:bg-gray-300 focus:outline-none"
          >
            ← Up one level
          </button>
          <span class="ml-2 text-gray-600">Current path: <%= display_prefix(@prefix) %></span>
        </div>
      <% end %>

      <%= if @error do %>
        <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4" role="alert">
          <strong class="font-bold">Error:</strong>
          <span class="block sm:inline"><%= @error %></span>
        </div>
      <% end %>

      <%= if @bucket_name != "" do %>
        <div class="bg-white shadow overflow-hidden border-b border-gray-200 rounded-lg">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Type</th>
                <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Name</th>
                <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Size</th>
                <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Last Modified</th>
                <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <%= if @loading do %>
                <tr>
                  <td colspan="5" class="px-6 py-4 text-center text-gray-500">
                    Loading...
                  </td>
                </tr>
              <% else %>
                <%= if folders(@objects, @prefix) != [] do %>
                  <%= for folder <- folders(@objects, @prefix) do %>
                    <tr>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <div class="text-sm text-blue-500">📁 Folder</div>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <div class="text-sm font-medium text-blue-500 cursor-pointer" phx-click="navigate_folder" phx-value-folder={folder}>
                          <%= display_name(folder, @prefix) %>
                        </div>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <div class="text-sm text-gray-500">-</div>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <div class="text-sm text-gray-500">-</div>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <div class="text-sm text-gray-500">-</div>
                      </td>
                    </tr>
                  <% end %>
                <% end %>
                
                <%= if files(@objects, @prefix) != [] do %>
                  <%= for file <- files(@objects, @prefix) do %>
                    <tr>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <div class="text-sm text-gray-900">📄 File</div>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <div class="text-sm font-medium text-gray-900">
                          <%= display_name(file.key, @prefix) %>
                        </div>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <div class="text-sm text-gray-500"><%= format_size(file.size) %></div>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <div class="text-sm text-gray-500"><%= format_date(file.last_modified) %></div>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                        <button 
                          phx-click="load_file" 
                          phx-value-key={file.key} 
                          class="text-indigo-600 hover:text-indigo-900 mr-3"
                        >
                          Download
                        </button>
                        <button 
                          phx-click="delete_file" 
                          phx-value-key={file.key}
                          data-confirm="Are you sure you want to delete this file?"
                          class="text-red-600 hover:text-red-900"
                        >
                          Delete
                        </button>
                      </td>
                    </tr>
                  <% end %>
                <% end %>
                
                <%= if @objects == [] do %>
                  <tr>
                    <td colspan="5" class="px-6 py-4 text-center text-gray-500">
                      No files found in this <%= if @prefix, do: "folder", else: "bucket" %>.
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      <% else %>
        <div class="bg-gray-50 p-6 text-center rounded-lg border border-gray-200">
          <p class="text-gray-500">Enter a bucket name and click "List Files" to browse S3 contents.</p>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("list_objects", %{"bucket_name" => bucket_name}, socket) do
    socket = assign(socket, bucket_name: bucket_name, loading: true, error: nil) 
    case S3Manager.list_objects(bucket_name, socket.assigns.prefix) do
      {:ok, objects} ->
        {:noreply, assign(socket, objects: objects.body.contents, loading: false)}
      {:error, error} ->
        error_message = extract_error_message(error)
        {:noreply, assign(socket, error: error_message, objects: [], loading: false)}
    end
  end


  @impl true
  def handle_event("load-ingredients", %{"bucket_name" => bucket_name}, socket) do
    socket = assign(socket, bucket_name: bucket_name, loading: true, error: nil) 
    case S3Manager.list_objects(bucket_name, socket.assigns.prefix) do
      {:ok, objects} ->

        Enum.each(objects.body.contents, fn x -> 
         case S3Manager.presigned_url(bucket_name, x.key) do
           {:ok, url} ->
             IO.inspect(url, label: "Url")
             {:ok, url} = url
             %HTTPoison.Response{body: body} = HTTPoison.get!(url)
             Mehungry.FdcFoodParserLeg.get_ingredients_from_json_body(body)
           {:error, the_err} ->
             IO.inspect(the_err, label: "The error in parsing")
         end 
        end)

        {:noreply, assign(socket, objects: objects.body.contents, loading: false)}
      {:error, error} ->
        IO.inspect(error) 
        error_message = extract_error_message(error)
        {:noreply, assign(socket, error: error_message, objects: [], loading: false)}
    end
  end

  @impl true
  def handle_event("refresh", _, socket) do
    bucket_name = socket.assigns.bucket_name
    prefix = socket.assigns.prefix
    socket = assign(socket, loading: true, error: nil)
    
    case S3Manager.list_objects(bucket_name, prefix) do
      {:ok, objects} ->
        {:noreply, assign(socket, objects: objects, loading: false)}
      
      {:error, error} ->
        error_message = extract_error_message(error)
        {:noreply, assign(socket, error: error_message, loading: false)}
    end
  end

  @impl true
  def handle_event("navigate_folder", %{"folder" => folder}, socket) do
    bucket_name = socket.assigns.bucket_name
    socket = assign(socket, loading: true, error: nil, prefix: folder)
    
    case S3Manager.list_objects(bucket_name, folder) do
      {:ok, objects} ->
        {:noreply, assign(socket, objects: objects, loading: false)}
      
      {:error, error} ->
        error_message = extract_error_message(error)
        {:noreply, assign(socket, error: error_message, loading: false)}
    end
  end

  @impl true
  def handle_event("navigate_up", _, socket) do
    bucket_name = socket.assigns.bucket_name
    current_prefix = socket.assigns.prefix
    
    new_prefix = case String.split(current_prefix, "/", trim: true) do
      [] -> nil
      parts when length(parts) == 1 -> nil
      parts ->
        parts
        |> Enum.drop(-1)
        |> Enum.join("/")
        |> then(fn p -> p <> "/" end)
    end
    
    socket = assign(socket, loading: true, error: nil, prefix: new_prefix)
    
    case S3Manager.list_objects(bucket_name, new_prefix) do
      {:ok, objects} ->
        {:noreply, assign(socket, objects: objects, loading: false)}
      
      {:error, error} ->
        error_message = extract_error_message(error)
        {:noreply, assign(socket, error: error_message, loading: false)}
    end
  end

  @impl true
  def handle_event("load_file", %{"key" => key}, socket) do
    bucket_name = socket.assigns.bucket_name
    
    case S3Manager.presigned_url(bucket_name, key) do
      {:ok, url} ->
        {:ok, url} = url
        %HTTPoison.Response{body: body} = HTTPoison.get!(url)
        Mehungry.FdcFoodParserLeg.get_ingredients_from_json_body(body)
        {:noreply, socket}
      
      {:error, error} ->
        error_message = extract_error_message(error)
        {:noreply, assign(socket, error: error_message)}
    end
  end

  @impl true
  def handle_event("delete_file", %{"key" => key}, socket) do
    bucket_name = socket.assigns.bucket_name
    socket = assign(socket, loading: true, error: nil)
    
    case S3Manager.delete_object(bucket_name, key) do
      {:ok, _} ->
        # Refresh the list after deletion
        case S3Manager.list_objects(bucket_name, socket.assigns.prefix) do
          {:ok, objects} ->
            {:noreply, assign(socket, objects: objects, loading: false)}
          
          {:error, error} ->
            error_message = extract_error_message(error)
            {:noreply, assign(socket, error: error_message, loading: false)}
        end
      
      {:error, error} ->
        error_message = extract_error_message(error)
        {:noreply, assign(socket, error: error_message, loading: false)}
    end
  end

  # Helper functions for displaying files and folders

  defp folders(objects, prefix) do
    objects
    |> Enum.map(& &1.key)
    |> Enum.filter(&folder?(&1, prefix))
    |> Enum.map(&folder_name(&1, prefix))
    |> Enum.uniq()
  end

  defp files(objects, prefix) do
    objects
    |> Enum.filter(&(!folder?(&1.key, prefix)))
  end

  defp folder?(key, prefix) do
    prefix_length = if prefix, do: String.length(prefix), else: 0
    remaining = String.slice(key, prefix_length..-1)
    String.contains?(remaining, "/")
  end

  defp folder_name(key, prefix) do
    prefix_length = if prefix, do: String.length(prefix), else: 0
    remaining = String.slice(key, prefix_length..-1)
    
    parts = String.split(remaining, "/", trim: true)
    folder_part = List.first(parts)
    
    if prefix, do: prefix <> folder_part <> "/", else: folder_part <> "/"
  end

  defp display_name(key, prefix) do
    if prefix do
      String.replace(key, prefix, "")
    else
      key
    end
  end

  defp display_prefix(nil), do: "/"
  defp display_prefix(prefix), do: "/" <> prefix

  defp format_size(size) when is_integer(size) do
    cond do
      size < 1024 -> "#{size} B"
      size < 1024 * 1024 -> "#{Float.round(size / 1024, 2)} KB"
      size < 1024 * 1024 * 1024 -> "#{Float.round(size / 1024 / 1024, 2)} MB"
      true -> "#{Float.round(size / 1024 / 1024 / 1024, 2)} GB"
    end
  end
  defp format_size(_), do: "-"

  defp format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end
  defp format_date(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end
  defp format_date(_), do: "-"

  defp extract_error_message({:error, error}) do
    extract_error_message(error)
  end
  defp extract_error_message(%{reason: reason}) when is_binary(reason) do
    reason
  end
  defp extract_error_message(%{message: message}) when is_binary(message) do
    message
  end
  defp extract_error_message(error) when is_binary(error) do
    error
  end
  defp extract_error_message(_) do
    "An unknown error occurred"
  end
end
