defmodule Mix.Tasks.Mem.Probe do
  @shortdoc "Measure the three memory domains (BEAM heap / native libvips / OS RSS) under the image pipeline"

  @moduledoc """
  Memory probe for the libvips (`:vix`/`:image`) graphics pipeline.

  The point of this task is to make the **native, off-BEAM memory** visible. On a
  memory-constrained Fly machine the thing that OOM-kills you is OS **RSS**, and a
  large chunk of RSS (libvips decode buffers, its operation cache, its thread pool)
  is **invisible to `:erlang.memory/0`** and therefore to LiveDashboard / PromEx /
  BeamScope. This task samples all three domains at once so the gap is undeniable:

      native_footprint ≈ RSS − BEAM_total

  Run it **on the actual Fly machine** (where the cgroup limit is real) to see the
  numbers that matter:

      fly ssh console -C "/app/bin/mehungry_umbrella eval 'Mix.Tasks.Mem.Probe.run([])'"

  or locally against the dev build (no DB needed — it only exercises vix):

      mix mem.probe
      mix mem.probe --iterations 40 --cap --concurrency 2

  Options:

    * `--iterations N`  how many renders per pass (default 25)
    * `--cap`           apply the recommended libvips caps (cache 0, bounded threads)
                        and re-run, printing a before/after comparison
    * `--concurrency N` libvips worker threads when `--cap` is set (default 2)

  See `docs/implementation/infrastructure/memory_management.md` for the strategy this
  task measures against.
  """
  use Mix.Task

  @mb 1024 * 1024
  @canvas 1080

  @impl true
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [iterations: :integer, cap: :boolean, concurrency: :integer]
      )

    # vix/image are deps of this app; no Repo / Endpoint needed.
    {:ok, _} = Application.ensure_all_started(:image)

    iterations = opts[:iterations] || 25

    print_env()
    {src, overlay_svg} = fixtures()

    IO.puts("\n== PASS 1: libvips DEFAULTS ==")
    run_pass(src, overlay_svg, iterations)

    if opts[:cap] do
      apply_caps(opts[:concurrency] || 2)
      IO.puts("\n== PASS 2: CAPPED (cache 0, concurrency #{Vix.Vips.concurrency_get()}) ==")
      run_pass(src, overlay_svg, iterations)
    end

    File.rm(src)
    IO.puts("")
  end

  # ── measurement ────────────────────────────────────────────────────────────

  @doc "Resident set size of THIS OS process, in bytes (0 if /proc unavailable)."
  def rss_bytes do
    with {:ok, s} <- File.read("/proc/self/status"),
         [_, kb] <- Regex.run(~r/VmRSS:\s+(\d+) kB/, s) do
      String.to_integer(kb) * 1024
    else
      _ -> 0
    end
  end

  @doc """
  The cgroup memory limit (bytes) and current usage this container is held to —
  the real ceiling the OOM killer enforces. Reads cgroup v2 then v1; `:unlimited`
  when unbounded, `nil` when not containerised (bare-metal dev box).
  """
  def cgroup_limit do
    cond do
      File.exists?("/sys/fs/cgroup/memory.max") ->
        {parse_limit(File.read!("/sys/fs/cgroup/memory.max")),
         parse_int(File.read("/sys/fs/cgroup/memory.current"))}

      File.exists?("/sys/fs/cgroup/memory/memory.limit_in_bytes") ->
        {parse_limit(File.read!("/sys/fs/cgroup/memory/memory.limit_in_bytes")),
         parse_int(File.read("/sys/fs/cgroup/memory/memory.usage_in_bytes"))}

      true ->
        {nil, nil}
    end
  end

  defp parse_limit("max" <> _), do: :unlimited
  defp parse_limit(bin) do
    case Integer.parse(String.trim(bin)) do
      # cgroup v1 reports a sentinel ~= 2^63 when unlimited
      {n, _} when n > 9_000_000_000_000_000_000 -> :unlimited
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_int({:ok, bin}) do
    case Integer.parse(String.trim(bin)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_int(_), do: nil

  # Background sampler keeps the max RSS seen while `fun` runs, so we catch the
  # transient decode peak even though the op is synchronous and fast.
  defp sample_peak(fun, ms \\ 3) do
    parent = self()
    ref = make_ref()
    pid = spawn_link(fn -> peak_loop(parent, ref, rss_bytes(), ms) end)
    result = fun.()
    send(pid, {:stop, ref})

    peak =
      receive do
        {:peak, ^ref, p} -> p
      after
        1_000 -> rss_bytes()
      end

    {result, peak}
  end

  defp peak_loop(parent, ref, peak, ms) do
    receive do
      {:stop, ^ref} -> send(parent, {:peak, ref, peak})
    after
      ms -> peak_loop(parent, ref, max(peak, rss_bytes()), ms)
    end
  end

  # ── passes ─────────────────────────────────────────────────────────────────

  defp run_pass(src, overlay_svg, n) do
    render = render_fun(src, overlay_svg)
    :erlang.garbage_collect()
    report("baseline")

    for i <- 1..n do
      {_bytes, peak} = sample_peak(render)

      if i == 1 or i == n or rem(i, 5) == 0 do
        IO.puts(
          fmt(
            "  iter ~3w  peak-RSS ~7.1f MB | settled-RSS ~7.1f MB | BEAM ~6.1f MB | native ~6.1f MB",
            [i, mb(peak), mb(rss_bytes()), mb(beam()), mb(rss_bytes() - beam())]
          )
        )
      end
    end

    :erlang.garbage_collect()
    report("after + GC")
  end

  # The real InsightGraphic shape: open (full decode) -> thumbnail -> flatten ->
  # rasterise overlay SVG -> compose -> encode to memory.
  defp render_fun(src, overlay_svg) do
    fn ->
      {:ok, base} = Image.open(src)
      {:ok, square} = Image.thumbnail(base, "#{@canvas}x#{@canvas}", crop: :center)
      {:ok, square} = Image.flatten(square)
      {:ok, overlay} = Image.from_svg(overlay_svg)
      {:ok, composed} = Image.compose(square, overlay)
      {:ok, bin} = Image.write(composed, :memory, suffix: ".jpg", quality: 88)
      byte_size(bin)
    end
  end

  defp apply_caps(concurrency) do
    Vix.Vips.cache_set_max_mem(0)
    Vix.Vips.cache_set_max(0)
    Vix.Vips.concurrency_set(concurrency)
    :erlang.garbage_collect()
  end

  # ── fixtures & output ──────────────────────────────────────────────────────

  defp fixtures do
    src = Path.join(System.tmp_dir!(), "mem_probe_src.jpg")
    {:ok, img} = Image.new(6000, 6000, color: [120, 160, 90])
    {:ok, _} = Image.write(img, src, quality: 90)

    svg = """
    <svg width="#{@canvas}" height="#{@canvas}" xmlns="http://www.w3.org/2000/svg">
      <rect x="0" y="780" width="#{@canvas}" height="300" fill="rgba(20,20,20,0.72)"/>
      <text x="60" y="880" font-family="DejaVu Sans" font-size="64" fill="#fff">High in Iron</text>
      <text x="60" y="960" font-family="DejaVu Sans" font-size="40" fill="#eee">A standout source</text>
      <circle cx="930" cy="900" r="90" fill="none" stroke="#e8542f" stroke-width="22"/>
    </svg>
    """

    {src, svg}
  end

  defp print_env do
    {limit, usage} = cgroup_limit()

    IO.puts("== ENVIRONMENT ==")
    IO.puts("  OTP schedulers online : #{:erlang.system_info(:schedulers_online)}")
    IO.puts("  libvips cache_max_mem : #{mb(Vix.Vips.cache_get_max_mem())} MB")
    IO.puts("  libvips cache_max ops : #{Vix.Vips.cache_get_max()}")
    IO.puts("  libvips concurrency   : #{Vix.Vips.concurrency_get()} threads")
    IO.puts("  cgroup memory.max     : #{fmt_limit(limit)}")
    IO.puts("  cgroup memory.current : #{if usage, do: "#{mb(usage)} MB", else: "n/a"}")
  end

  defp report(label) do
    IO.puts(
      fmt("  ~-12s BEAM ~6.1f MB | bin ~6.1f MB | RSS ~7.1f MB | native(RSS-BEAM) ~6.1f MB", [
        label,
        mb(beam()),
        mb(:erlang.memory(:binary)),
        mb(rss_bytes()),
        mb(rss_bytes() - beam())
      ])
    )
  end

  defp fmt_limit(:unlimited), do: "unlimited (not container-capped)"
  defp fmt_limit(nil), do: "n/a (no cgroup — bare-metal/dev)"
  defp fmt_limit(bytes), do: "#{mb(bytes)} MB"

  defp beam, do: :erlang.memory(:total)
  defp mb(b), do: Float.round(b / @mb, 1)
  defp fmt(f, args), do: to_string(:io_lib.format(f, args))
end
