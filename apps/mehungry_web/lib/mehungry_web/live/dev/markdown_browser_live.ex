# Dev-only Markdown browser / viewer / editor.
#
# Guarded by `Mix.env() == :dev` so the module (which references Earmark, a
# dev-only dependency) is never compiled in :test or :prod. The matching route
# lives in the router's `if Mix.env() == :dev` block.
if Mix.env() == :dev do
  defmodule MehungryWeb.Dev.MarkdownBrowserLive do
    @moduledoc """
    A tiny, self-contained editor for the repo's Markdown files (docs/, CLAUDE.md,
    READMEs, …). Browse the tree on the left, read the rendered doc on the right,
    and hit *Edit* for a split textarea + live preview that writes straight back
    to disk. Available at `/dev/docs` in development only.
    """
    use MehungryWeb, :live_view

    @impl true
    def mount(_params, _session, socket) do
      files = list_files()
      tree = build_tree(files)

      socket =
        socket
        |> assign(:page_title, "Docs")
        |> assign(:root, File.cwd!())
        |> assign(:files, files)
        |> assign(:tree, tree)
        # Directory paths that are currently collapsed (default: all collapsed).
        |> assign(:collapsed, MapSet.new(dir_paths(tree)))
        |> assign(:selected, nil)
        |> assign(:content, nil)
        |> assign(:editing, false)
        |> assign(:draft, "")
        |> assign(:flash_msg, nil)

      {:ok, socket, layout: false}
    end

    @impl true
    def handle_event("select", %{"path" => rel}, socket) do
      {:noreply, load_file(socket, rel)}
    end

    def handle_event("toggle_dir", %{"path" => dir}, socket) do
      collapsed = socket.assigns.collapsed

      collapsed =
        if MapSet.member?(collapsed, dir),
          do: MapSet.delete(collapsed, dir),
          else: MapSet.put(collapsed, dir)

      {:noreply, assign(socket, :collapsed, collapsed)}
    end

    def handle_event("edit", _params, socket) do
      {:noreply, assign(socket, editing: true, draft: socket.assigns.content || "", flash_msg: nil)}
    end

    def handle_event("cancel", _params, socket) do
      {:noreply, assign(socket, editing: false, flash_msg: nil)}
    end

    def handle_event("change", %{"content" => content}, socket) do
      {:noreply, assign(socket, draft: content)}
    end

    def handle_event("save", %{"content" => content}, socket) do
      case save_file(socket.assigns.root, socket.assigns.selected, content) do
        :ok ->
          {:noreply,
           socket
           |> assign(content: content, editing: false, flash_msg: {:ok, "Saved #{socket.assigns.selected}"})
           |> assign(:files, list_files())}

        {:error, reason} ->
          {:noreply, assign(socket, flash_msg: {:error, "Save failed: #{inspect(reason)}"})}
      end
    end

    # ── View ────────────────────────────────────────────────────────────────

    @impl true
    def render(assigns) do
      ~H"""
      <div class="flex h-screen overflow-hidden font-sans">
        <aside class="w-72 shrink-0 overflow-y-auto border-r border-slate-800 bg-slate-900">
          <div class="sticky top-0 z-10 border-b border-slate-800 bg-slate-900 px-4 py-3">
            <h1 class="text-sm font-semibold tracking-wide text-slate-200">📄 Docs browser</h1>
            <p class="mt-0.5 text-xs text-slate-500">{length(@files)} markdown files · dev only</p>
          </div>
          <nav class="p-2">
            <.tree_nodes nodes={@tree} selected={@selected} collapsed={@collapsed} depth={0} />
          </nav>
        </aside>

        <main class="flex-1 overflow-hidden">
          <%= if @selected do %>
            <div class="flex h-full flex-col">
              <header class="flex items-center justify-between gap-3 border-b border-slate-800 bg-slate-900/60 px-5 py-3">
                <div class="min-w-0">
                  <p class="truncate font-mono text-sm text-slate-300">{@selected}</p>
                  <%= if @flash_msg do %>
                    <p class={"mt-0.5 text-xs " <> if(elem(@flash_msg, 0) == :ok, do: "text-emerald-400", else: "text-rose-400")}>
                      {elem(@flash_msg, 1)}
                    </p>
                  <% end %>
                </div>
                <div class="flex shrink-0 gap-2">
                  <%= if @editing do %>
                    <button
                      type="submit"
                      form="editor-form"
                      class="rounded bg-emerald-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-emerald-500"
                    >
                      Save
                    </button>
                    <button
                      type="button"
                      phx-click="cancel"
                      class="rounded border border-slate-700 px-3 py-1.5 text-sm text-slate-300 hover:bg-slate-800"
                    >
                      Cancel
                    </button>
                  <% else %>
                    <button
                      type="button"
                      phx-click="edit"
                      class="rounded bg-indigo-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-indigo-500"
                    >
                      Edit
                    </button>
                  <% end %>
                </div>
              </header>

              <div class="flex-1 overflow-hidden">
                <%= if @editing do %>
                  <form
                    id="editor-form"
                    phx-change="change"
                    phx-submit="save"
                    class="grid h-full grid-cols-2 divide-x divide-slate-800"
                  >
                    <textarea
                      name="content"
                      spellcheck="false"
                      class="h-full w-full resize-none bg-slate-950 p-5 font-mono text-sm leading-relaxed text-slate-200 focus:outline-none"
                    ><%= @draft %></textarea>
                    <div class="h-full overflow-y-auto bg-slate-950 p-6">
                      <.markdown body={@draft} />
                    </div>
                  </form>
                <% else %>
                  <div class="h-full overflow-y-auto bg-slate-950 p-8">
                    <.markdown body={@content} />
                  </div>
                <% end %>
              </div>
            </div>
          <% else %>
            <div class="flex h-full items-center justify-center text-slate-600">
              <p class="text-sm">Select a document from the left to start reading.</p>
            </div>
          <% end %>
        </main>
      </div>
      """
    end

    attr :nodes, :list, required: true
    attr :selected, :string, default: nil
    attr :collapsed, :any, required: true
    attr :depth, :integer, default: 0

    # Recursive directory tree. Directories are collapsible; files select a doc.
    defp tree_nodes(assigns) do
      ~H"""
      <ul class="space-y-0.5">
        <li :for={node <- @nodes}>
          <%= if node.type == :dir do %>
            <button
              type="button"
              phx-click="toggle_dir"
              phx-value-path={node.path}
              style={"padding-left: #{@depth * 12 + 6}px"}
              class="flex w-full items-center gap-1 rounded py-1 pr-2 text-left text-xs font-medium text-slate-300 hover:bg-slate-800"
              title={node.path}
            >
              <span class="w-3 shrink-0 text-slate-500">
                {if MapSet.member?(@collapsed, node.path), do: "▸", else: "▾"}
              </span>
              <span class="shrink-0">📁</span>
              <span class="truncate">{node.name}</span>
            </button>
            <div :if={not MapSet.member?(@collapsed, node.path)}>
              <.tree_nodes
                nodes={node.children}
                selected={@selected}
                collapsed={@collapsed}
                depth={@depth + 1}
              />
            </div>
          <% else %>
            <button
              type="button"
              phx-click="select"
              phx-value-path={node.path}
              style={"padding-left: #{@depth * 12 + 22}px"}
              class={
                "flex w-full items-center gap-1.5 truncate rounded py-1 pr-2 text-left text-xs " <>
                  if(node.path == @selected,
                    do: "bg-indigo-600/20 font-medium text-indigo-300",
                    else: "text-slate-400 hover:bg-slate-800 hover:text-slate-200"
                  )
              }
              title={node.path}
            >
              <span class="shrink-0 opacity-70">📄</span>
              <span class="truncate">{node.name}</span>
            </button>
          <% end %>
        </li>
      </ul>
      """
    end

    attr :body, :string, default: nil

    defp markdown(assigns) do
      ~H"""
      <article class="md-body">
        {render_markdown(@body)}
      </article>
      <style>
        .md-body { color: #cbd5e1; max-width: 52rem; }
        .md-body h1, .md-body h2, .md-body h3 { color: #f1f5f9; font-weight: 600; line-height: 1.25; margin: 1.4em 0 0.6em; }
        .md-body h1 { font-size: 1.6rem; border-bottom: 1px solid #1e293b; padding-bottom: .3em; }
        .md-body h2 { font-size: 1.3rem; border-bottom: 1px solid #1e293b; padding-bottom: .25em; }
        .md-body h3 { font-size: 1.1rem; }
        .md-body p, .md-body ul, .md-body ol, .md-body blockquote, .md-body table { margin: 0.75em 0; }
        .md-body a { color: #818cf8; text-decoration: underline; }
        .md-body ul { list-style: disc; padding-left: 1.5em; }
        .md-body ol { list-style: decimal; padding-left: 1.5em; }
        .md-body li { margin: 0.25em 0; }
        .md-body code { background: #1e293b; color: #e2e8f0; padding: .15em .35em; border-radius: 4px; font-size: .85em; }
        .md-body pre { background: #0b1120; border: 1px solid #1e293b; border-radius: 8px; padding: 1em; overflow-x: auto; }
        .md-body pre code { background: none; padding: 0; }
        .md-body blockquote { border-left: 3px solid #334155; padding-left: 1em; color: #94a3b8; }
        .md-body table { border-collapse: collapse; display: block; overflow-x: auto; }
        .md-body th, .md-body td { border: 1px solid #1e293b; padding: .4em .7em; text-align: left; }
        .md-body th { background: #111827; }
        .md-body hr { border: 0; border-top: 1px solid #1e293b; margin: 1.5em 0; }
        .md-body img { max-width: 100%; }
      </style>
      """
    end

    # ── Markdown / file helpers ───────────────────────────────────────────────

    defp render_markdown(nil), do: ""

    defp render_markdown(body) do
      case Earmark.as_html(body, %Earmark.Options{gfm: true, breaks: false, code_class_prefix: "language-"}) do
        {:ok, html, _warnings} -> Phoenix.HTML.raw(html)
        {:error, html, _errors} -> Phoenix.HTML.raw(html)
      end
    end

    defp load_file(socket, rel) do
      with {:ok, abs} <- safe_path(socket.assigns.root, rel),
           {:ok, content} <- File.read(abs) do
        assign(socket, selected: rel, content: content, editing: false, draft: content, flash_msg: nil)
      else
        {:error, reason} -> assign(socket, flash_msg: {:error, "Could not open file: #{inspect(reason)}"})
      end
    end

    defp save_file(root, rel, content) do
      with {:ok, abs} <- safe_path(root, rel) do
        File.write(abs, content)
      end
    end

    # Only allow reading/writing `.md` files that resolve inside the repo root.
    defp safe_path(root, rel) do
      abs = Path.expand(rel, root)

      cond do
        Path.extname(abs) != ".md" -> {:error, :not_markdown}
        not String.starts_with?(abs, root <> "/") -> {:error, :outside_root}
        true -> {:ok, abs}
      end
    end

    defp list_files do
      root = File.cwd!()

      Path.wildcard(Path.join(root, "docs/**/*.md"))
      |> Enum.map(&Path.relative_to(&1, root))
      |> Enum.sort()
    end

    # Turn flat relative paths ("docs/ai/ai.md") into a nested tree of
    # %{type: :dir | :file, name:, path:, children:} nodes. Directories are
    # listed before files at each level, both alphabetically.
    defp build_tree(paths) do
      paths
      |> Enum.map(&{Path.split(&1), &1})
      |> build_nodes("")
    end

    defp build_nodes(entries, prefix) do
      {files, dirs} = Enum.split_with(entries, fn {segments, _} -> length(segments) == 1 end)

      dir_nodes =
        dirs
        |> Enum.group_by(fn {[head | _], _} -> head end, fn {[_ | rest], full} -> {rest, full} end)
        |> Enum.map(fn {name, children} ->
          dir_path = if prefix == "", do: name, else: prefix <> "/" <> name
          %{type: :dir, name: name, path: dir_path, children: build_nodes(children, dir_path)}
        end)
        |> Enum.sort_by(& &1.name)

      file_nodes =
        files
        |> Enum.map(fn {[name], full} -> %{type: :file, name: name, path: full} end)
        |> Enum.sort_by(& &1.name)

      dir_nodes ++ file_nodes
    end

    # Every directory path in the tree (used to collapse all folders initially).
    defp dir_paths(nodes) do
      Enum.flat_map(nodes, fn
        %{type: :dir, path: path, children: children} -> [path | dir_paths(children)]
        _ -> []
      end)
    end
  end
end
