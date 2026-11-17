defmodule MehungryWeb.VipsMemory do
  @moduledoc """
  Boot-time memory caps for the libvips (`:vix`/`:image`) native layer.

  libvips allocates **outside** the BEAM heap: an operation cache (100 MB by
  default), a worker thread pool (sized to the CPU count by default), and per-op
  decode/encode buffers. None of it is visible to `:erlang.memory/0`, LiveDashboard
  or PromEx — but all of it counts toward the OS **RSS** that the Fly machine's
  1 GB cgroup limit (and the OOM killer) enforce. See
  `docs/implementation/infrastructure/memory_management.md`.

  `configure/0` must run **once at application start, before the first render** —
  the thread pool is created lazily on first use and cannot be shrunk afterwards,
  so late tuning is a no-op for threads already spawned.

  Tunable via config (all optional):

      config :mehungry_web, MehungryWeb.VipsMemory,
        cache_max_mem_mb: 0,   # operation-cache ceiling in MB (0 = disable the cache)
        cache_max_ops: 0,      # operation-cache entry count
        concurrency: 2         # worker threads; match the machine's vCPU count
  """
  require Logger

  @defaults [cache_max_mem_mb: 0, cache_max_ops: 0, concurrency: 2]

  @doc "Apply the libvips native-memory caps. Returns `:ok`."
  def configure do
    cfg = Keyword.merge(@defaults, Application.get_env(:mehungry_web, __MODULE__, []))

    Vix.Vips.cache_set_max_mem(cfg[:cache_max_mem_mb] * 1024 * 1024)
    Vix.Vips.cache_set_max(cfg[:cache_max_ops])
    Vix.Vips.concurrency_set(cfg[:concurrency])

    Logger.info(
      "libvips memory caps: cache=#{cfg[:cache_max_mem_mb]}MB/#{cfg[:cache_max_ops]}ops " <>
        "threads=#{Vix.Vips.concurrency_get()}"
    )

    :ok
  rescue
    e ->
      # Never let a tuning call take down boot; log and proceed with vix defaults.
      Logger.warning("libvips memory cap setup failed: #{inspect(e)}")
      :ok
  end
end
