defmodule MehungryWeb.ProfessionalLive.S3BrowserLive do
  use Phoenix.LiveView

  alias Mehungry.S3
  alias Mehungry.FoodData.Usda.SeedFiles
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    # Give the durable (connected) process a human-readable OTP label so it isn't an
    # anonymous pid in observer / :recon / LiveDashboard / the ProcessWatchdog when
    # its mailbox backs up under a seed run. Refined with the bucket in `apply_listing/5`.
    if connected?(socket), do: :proc_lib.set_label({:s3_browser_live, "(no bucket)"})

    {:ok,
     socket
     |> stream(:files, [])
     |> assign(
       bucket_name: "",
       prefix: nil,
       loading: false,
       error: nil,
       info: nil,
       folders: [],
       # key => row map (server-side bookkeeping; never rendered directly, so
       # updating it never re-renders the streamed table). Holds the S3 metadata
       # (size/last_modified/name) a live `{:seed_file, ...}` update lacks.
       file_index: %{},
       # status string => count, maintained incrementally so the summary line can
       # update without walking the whole listing on every broadcast.
       counts: %{},
       subscribed_bucket: nil
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
              {if @loading, do: "Loading...", else: "List Files"}
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
              {if @loading, do: "Loading...", else: "Load ingredients"}
            </button>

            <button
              phx-click="refresh"
              class="px-4 py-2 bg-green-500 text-white rounded-md hover:bg-green-600 focus:outline-none focus:ring-2 focus:ring-green-500"
              disabled={@loading}
            >
              Refresh
            </button>

            <button
              phx-click="reset-seed-status"
              data-confirm="Clear the pending seed queue so a fresh run can be started?"
              class="px-4 py-2 bg-yellow-500 text-white rounded-md hover:bg-yellow-600 focus:outline-none focus:ring-2 focus:ring-yellow-500"
              disabled={@loading}
            >
              Reset seed status
            </button>
          </div>
        <% end %>
      </div>

      <%= if @info do %>
        <div
          class="bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded mb-4"
          role="status"
        >
          <span class="block sm:inline">{@info}</span>
        </div>
      <% end %>

      <%= if seed_counts_present?(@counts) do %>
        <div
          class="flex flex-wrap gap-4 bg-gray-50 border border-gray-200 text-gray-700 px-4 py-3 rounded mb-4 text-sm"
          role="status"
        >
          <span class="font-medium">Seed status:</span>
          <span class="text-gray-500">Pending {Map.get(@counts, "pending", 0)}</span>
          <span class="text-blue-600">Processing {Map.get(@counts, "processing", 0)}</span>
          <span class="text-green-600">Completed {Map.get(@counts, "completed", 0)}</span>
          <span class="text-red-600">Failed {Map.get(@counts, "failed", 0)}</span>
        </div>
      <% end %>

      <%= if @prefix do %>
        <div class="mb-4">
          <button
            phx-click="navigate_up"
            class="px-3 py-1 bg-gray-200 text-gray-700 rounded-md hover:bg-gray-300 focus:outline-none"
          >
            ← Up one level
          </button>
          <span class="ml-2 text-gray-600">Current path: {display_prefix(@prefix)}</span>
        </div>
      <% end %>

      <%= if @error do %>
        <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4" role="alert">
          <strong class="font-bold">Error:</strong>
          <span class="block sm:inline">{@error}</span>
        </div>
      <% end %>

      <%= if @bucket_name != "" do %>
        <%= if not @loading do %>
          <div class="mb-2 text-sm text-gray-600">
            {map_size(@file_index)} file(s)<%= if @folders != [] do %>
              , {length(@folders)} folder(s)
            <% end %>
          </div>
        <% end %>
        <div class="bg-white shadow overflow-hidden border-b border-gray-200 rounded-lg">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th
                  scope="col"
                  class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                >
                  #
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                >
                  Type
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                >
                  Name
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                >
                  Size
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                >
                  Last Modified
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                >
                  Seed status
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                >
                  Actions
                </th>
              </tr>
            </thead>

            <%= if @loading do %>
              <tbody>
                <tr>
                  <td colspan="7" class="px-6 py-4 text-center text-gray-500">
                    Loading...
                  </td>
                </tr>
              </tbody>
            <% else %>
              <tbody class="bg-white divide-y divide-gray-200">
                <tr :for={folder <- @folders}>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <div class="text-sm text-gray-400">-</div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <div class="text-sm text-blue-500">📁 Folder</div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <div
                      class="text-sm font-medium text-blue-500 cursor-pointer"
                      phx-click="navigate_folder"
                      phx-value-folder={folder}
                    >
                      {display_name(folder, @prefix)}
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
                  <td class="px-6 py-4 whitespace-nowrap">
                    <div class="text-sm text-gray-500">-</div>
                  </td>
                </tr>
              </tbody>

              <tbody
                id="seed-file-rows"
                phx-update="stream"
                class="bg-white divide-y divide-gray-200"
              >
                <tr :for={{dom_id, row} <- @streams.files} id={dom_id}>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <div class="text-sm font-medium text-gray-500">•</div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <div class="text-sm text-gray-900">📄 File</div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <div class="text-sm font-medium text-gray-900">{row.name}</div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <div class="text-sm text-gray-500">{format_size(row.size)}</div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <div class="text-sm text-gray-500">{format_date(row.last_modified)}</div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <div
                      class={"text-sm font-medium #{seed_status_class(row)}"}
                      title={seed_status_title(row)}
                    >
                      {seed_status_label(row)}
                    </div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                    <button
                      phx-click="download_file"
                      phx-value-key={row.key}
                      class="text-indigo-600 hover:text-indigo-900 mr-3"
                    >
                      Download
                    </button>
                    <button
                      phx-click="redo_file"
                      phx-value-key={row.key}
                      class="text-amber-600 hover:text-amber-900 mr-3"
                    >
                      Re-do
                    </button>
                    <button
                      phx-click="delete_file"
                      phx-value-key={row.key}
                      data-confirm="Are you sure you want to delete this file?"
                      class="text-red-600 hover:text-red-900"
                    >
                      Delete
                    </button>
                  </td>
                </tr>
              </tbody>

              <%= if @folders == [] and map_size(@file_index) == 0 do %>
                <tbody>
                  <tr>
                    <td colspan="7" class="px-6 py-4 text-center text-gray-500">
                      No files found in this {if @prefix, do: "folder", else: "bucket"}.
                    </td>
                  </tr>
                </tbody>
              <% end %>
            <% end %>
          </table>
        </div>
      <% else %>
        <div class="bg-gray-50 p-6 text-center rounded-lg border border-gray-200">
          <p class="text-gray-500">
            Enter a bucket name and click "List Files" to browse S3 contents.
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("list_objects", %{"bucket_name" => bucket_name}, socket) do
    socket = assign(socket, bucket_name: bucket_name, error: nil, info: nil)
    {:noreply, start_list(socket, bucket_name, socket.assigns.prefix)}
  end

  @impl true
  def handle_event("load-ingredients", %{"bucket_name" => bucket_name}, socket) do
    prefix = socket.assigns.prefix

    Logger.info(
      "Enqueue seed-file imports from bucket #{bucket_name} (prefix: #{inspect(prefix)})"
    )

    socket =
      socket
      |> assign(bucket_name: bucket_name, loading: true, error: nil, info: nil)
      |> start_async({:load_ingredients, bucket_name, prefix}, fn ->
        case S3.list_objects(bucket_name, prefix) do
          {:ok, objects} ->
            contents = objects.body.contents

            # Only enqueue files not already completed — SeedFiles.pending_or_failed/2
            # filters the keys so a re-click skips finished imports. Presigning +
            # fetching happen inside the job, so URLs can't expire in the :imports queue.
            keys =
              contents
              |> Enum.map(& &1.key)
              |> Enum.reject(&String.ends_with?(&1, "/"))
              |> then(&SeedFiles.pending_or_failed(bucket_name, &1))

            {enqueued, failed} =
              Enum.reduce(keys, {0, 0}, fn key, {ok, err} ->
                case Mehungry.ObanWorkers.SeedFileImportWorker.enqueue(bucket_name, key) do
                  {:ok, _job} ->
                    {ok + 1, err}

                  {:error, reason} ->
                    Logger.error("[S3Browser] failed to enqueue #{key}: #{inspect(reason)}")
                    {ok, err + 1}
                end
              end)

            {:ok, contents, SeedFiles.list_by_bucket(bucket_name, prefix), enqueued, failed}

          {:error, error} ->
            {:error, error}
        end
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("reset-seed-status", _, socket) do
    bucket_name = socket.assigns.bucket_name

    if bucket_name == "" do
      {:noreply,
       assign(socket, error: "List a bucket first — there is no seed status to reset.", info: nil)}
    else
      count = SeedFiles.reset(bucket_name, socket.assigns.prefix)

      # Keep the files on screen but clear their status back to "—" without a
      # re-list round-trip: strip the status fields off the cached rows and
      # re-stream them.
      cleared =
        Map.new(socket.assigns.file_index, fn {key, row} ->
          {key, %{row | status: nil, ingredient_count: nil, error: nil}}
        end)

      {:noreply,
       socket
       |> stream(:files, ordered_rows(cleared), reset: true)
       |> assign(
         file_index: cleared,
         counts: %{},
         info: "Seed status reset — cleared #{count} tracking row(s). You can start a fresh run.",
         error: nil
       )}
    end
  end

  @impl true
  def handle_event("refresh", _, socket) do
    {:noreply, start_list(socket, socket.assigns.bucket_name, socket.assigns.prefix)}
  end

  @impl true
  def handle_event("navigate_folder", %{"folder" => folder}, socket) do
    {:noreply, start_list(socket, socket.assigns.bucket_name, folder)}
  end

  @impl true
  def handle_event("navigate_up", _, socket) do
    current_prefix = socket.assigns.prefix

    new_prefix =
      case String.split(current_prefix, "/", trim: true) do
        [] ->
          nil

        parts when length(parts) == 1 ->
          nil

        parts ->
          parts
          |> Enum.drop(-1)
          |> Enum.join("/")
          |> then(fn p -> p <> "/" end)
      end

    {:noreply, start_list(socket, socket.assigns.bucket_name, new_prefix)}
  end

  @impl true
  def handle_event("redo_file", %{"key" => key}, socket) do
    bucket_name = socket.assigns.bucket_name

    case Mehungry.ObanWorkers.SeedFileImportWorker.enqueue(bucket_name, key) do
      {:ok, _job} ->
        {:noreply, assign(socket, info: "Re-queued #{key} for import.", error: nil)}

      {:error, reason} ->
        {:noreply,
         assign(socket, error: "Failed to re-queue #{key}: #{inspect(reason)}", info: nil)}
    end
  end

  # Real file download: presign a short-lived URL and open the raw object in a new
  # browser tab (handled by the `phx:open_url` listener in app.js). No parsing here
  # — importing is the tracked worker's job, reachable via "Load ingredients"/"Re-do".
  @impl true
  def handle_event("download_file", %{"key" => key}, socket) do
    case S3.presigned_url(socket.assigns.bucket_name, key) do
      {:ok, url} ->
        {:noreply, push_event(socket, "open_url", %{url: url})}

      {:error, error} ->
        {:noreply, assign(socket, error: extract_error_message(error))}
    end
  end

  @impl true
  def handle_event("delete_file", %{"key" => key}, socket) do
    bucket_name = socket.assigns.bucket_name

    case S3.delete_object(bucket_name, key) do
      {:ok, _} ->
        # Refresh the list after deletion
        {:noreply, start_list(socket, bucket_name, socket.assigns.prefix)}

      {:error, error} ->
        error_message = extract_error_message(error)
        {:noreply, assign(socket, error: error_message, loading: false)}
    end
  end

  # Live status updates broadcast by `SeedFiles` as import jobs finish. Because the
  # row is a stream entry, we patch just that one <tr> (O(1) diff) instead of
  # re-rendering the whole table, and adjust the summary counts incrementally.
  # Ignores broadcasts for other buckets or for keys not on the current page.
  @impl true
  def handle_info({:seed_file, %{bucket: bucket, key: key} = seed_file}, socket) do
    cond do
      bucket != socket.assigns.bucket_name ->
        {:noreply, socket}

      not Map.has_key?(socket.assigns.file_index, key) ->
        {:noreply, socket}

      true ->
        old = Map.fetch!(socket.assigns.file_index, key)

        row = %{
          old
          | status: seed_file.status,
            ingredient_count: seed_file.ingredient_count,
            error: seed_file.error
        }

        {:noreply,
         socket
         |> stream_insert(:files, row)
         |> assign(
           file_index: Map.put(socket.assigns.file_index, key, row),
           counts: adjust_counts(socket.assigns.counts, old.status, seed_file.status)
         )}
    end
  end

  # Kicks off an async bucket/prefix listing so the "Loading…" state actually
  # renders during the (potentially slow) S3 round-trip. Sets the prefix eagerly
  # so the breadcrumb updates immediately; the contents/seed rows land in
  # `handle_async(:list, ...)`. Single entry point for every navigation path.
  defp start_list(socket, bucket_name, prefix) do
    socket
    |> assign(prefix: prefix, loading: true, error: nil)
    |> start_async({:list, bucket_name, prefix}, fn ->
      case S3.list_objects(bucket_name, prefix) do
        {:ok, objects} ->
          {:ok, objects.body.contents, SeedFiles.list_by_bucket(bucket_name, prefix)}

        {:error, error} ->
          {:error, error}
      end
    end)
  end

  @impl true
  def handle_async({:list, bucket_name, _prefix}, {:ok, {:ok, contents, seed_files}}, socket) do
    {:noreply, apply_listing(socket, bucket_name, contents, seed_files, loading: false, error: nil)}
  end

  def handle_async({:list, _bucket, _prefix}, {:ok, {:error, error}}, socket) do
    {:noreply, clear_listing(socket, error: extract_error_message(error))}
  end

  def handle_async({:list, _bucket, _prefix}, {:exit, reason}, socket) do
    {:noreply, clear_listing(socket, error: "Listing failed: #{inspect(reason)}")}
  end

  def handle_async(
        {:load_ingredients, bucket_name, _prefix},
        {:ok, {:ok, contents, seed_files, enqueued, failed}},
        socket
      ) do
    info =
      "Queued #{enqueued} file(s) for import" <>
        if(failed > 0, do: " (#{failed} failed to queue)", else: "")

    {:noreply,
     apply_listing(socket, bucket_name, contents, seed_files, loading: false, info: info, error: nil)}
  end

  def handle_async({:load_ingredients, _bucket, _prefix}, {:ok, {:error, error}}, socket) do
    {:noreply, clear_listing(socket, error: extract_error_message(error))}
  end

  def handle_async({:load_ingredients, _bucket, _prefix}, {:exit, reason}, socket) do
    {:noreply, assign(socket, error: "Import enqueue failed: #{inspect(reason)}", loading: false)}
  end

  # Merges the S3 listing with the DB seed-status rows into stream entries, resets
  # the stream to exactly that set, and rebuilds the server-side `file_index` +
  # `counts` bookkeeping. `extra` carries per-call flags (loading/info/error).
  defp apply_listing(socket, bucket_name, contents, seed_files, extra) do
    prefix = socket.assigns.prefix
    folder_list = folders(contents, prefix)

    rows =
      contents
      |> files(prefix)
      |> Enum.map(&build_row(&1, Map.get(seed_files, &1.key), prefix))

    file_index = Map.new(rows, &{&1.key, &1})
    counts = count_statuses(rows)

    if connected?(socket), do: :proc_lib.set_label({:s3_browser_live, bucket_name})

    socket
    |> ensure_subscribed(bucket_name)
    |> stream(:files, rows, reset: true)
    |> assign(
      [bucket_name: bucket_name, folders: folder_list, file_index: file_index, counts: counts] ++
        extra
    )
  end

  # Empties the listing (used on a failed load) while surfacing an error.
  defp clear_listing(socket, extra) do
    socket
    |> stream(:files, [], reset: true)
    |> assign([folders: [], file_index: %{}, counts: %{}, loading: false] ++ extra)
  end

  # Builds one stream row, merging the S3 object metadata with its (optional)
  # seed-status row. `id` must be a stable, HTML-id-safe token; S3 keys contain
  # slashes/dots, so encode them.
  defp build_row(object, seed_file, prefix) do
    %{
      id: "seed-file-" <> Base.url_encode64(object.key, padding: false),
      key: object.key,
      name: display_name(object.key, prefix),
      size: object.size,
      last_modified: object.last_modified,
      status: seed_file && seed_file.status,
      ingredient_count: seed_file && seed_file.ingredient_count,
      error: seed_file && seed_file.error
    }
  end

  defp ordered_rows(file_index), do: file_index |> Map.values() |> Enum.sort_by(& &1.key)

  defp count_statuses(rows) do
    rows
    |> Enum.reject(&is_nil(&1.status))
    |> Enum.frequencies_by(& &1.status)
  end

  # Decrement the old status bucket, increment the new — keeps `counts` correct
  # without re-scanning `file_index`. nil statuses (files never imported) don't
  # participate in any bucket.
  defp adjust_counts(counts, old_status, new_status) do
    counts
    |> then(fn c ->
      if old_status, do: Map.update(c, old_status, 0, &max(&1 - 1, 0)), else: c
    end)
    |> then(fn c ->
      if new_status, do: Map.update(c, new_status, 1, &(&1 + 1)), else: c
    end)
  end

  defp seed_counts_present?(counts), do: map_size(counts) > 0

  # Subscribes to a bucket's seed-status topic exactly once, swapping the
  # subscription when the browsed bucket changes. No-op until connected.
  defp ensure_subscribed(socket, bucket_name) do
    cond do
      not connected?(socket) ->
        socket

      socket.assigns.subscribed_bucket == bucket_name ->
        socket

      true ->
        if prev = socket.assigns.subscribed_bucket do
          Phoenix.PubSub.unsubscribe(Mehungry.PubSub, SeedFiles.topic(prev))
        end

        Phoenix.PubSub.subscribe(Mehungry.PubSub, SeedFiles.topic(bucket_name))
        assign(socket, subscribed_bucket: bucket_name)
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
    remaining = String.slice(key, prefix_length..-1//1)
    String.contains?(remaining, "/")
  end

  defp folder_name(key, prefix) do
    prefix_length = if prefix, do: String.length(prefix), else: 0
    remaining = String.slice(key, prefix_length..-1//1)

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

  # Seed-status rendering ----------------------------------------------------

  defp seed_status_label(%{status: "pending"}), do: "Pending"
  defp seed_status_label(%{status: "processing"}), do: "Processing…"

  defp seed_status_label(%{status: "completed", ingredient_count: count}),
    do: "Completed (#{count || 0})"

  defp seed_status_label(%{status: "failed"}), do: "Failed"
  defp seed_status_label(_), do: "—"

  defp seed_status_class(%{status: "pending"}), do: "text-gray-500"
  defp seed_status_class(%{status: "processing"}), do: "text-blue-600"
  defp seed_status_class(%{status: "completed"}), do: "text-green-600"
  defp seed_status_class(%{status: "failed"}), do: "text-red-600"
  defp seed_status_class(_), do: "text-gray-400"

  defp seed_status_title(%{status: "failed", error: error}) when is_binary(error), do: error
  defp seed_status_title(_), do: nil

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
