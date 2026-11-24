# Dev-only: compiled from `dev/` (see elixirc_paths in mix.exs), never in the
# prod release — Wallaby is a dev/test dependency.
defmodule Mix.Tasks.Promo.Record do
  @shortdoc "Records the new-user promo video (signup → onboarding → AI plan → shopping list)"

  @moduledoc """
  Drives the real app with a scripted, human-paced browser session and records
  it as a vertical (9:16, 1080×1920) video for Reels / TikTok.

      mix promo.record                      # record against the `mehungry_promo` DB
      mix promo.record --rehearse           # headless dry run: screenshots, no video
      mix promo.record --db mehungry_server_dev --rehearse

  It boots the app itself (dev env, its own port, Oban cron OFF) against a
  **separate** database — by default `mehungry_promo`, made by
  `scripts/promo/snapshot_prod.sh` — then runs Chrome on a private Xvfb screen
  and grabs that screen with ffmpeg. Nothing is mocked: the meal plan is the
  real `UserMealPlanAgent` run (Anthropic + OpenAI keys come from your shell,
  so `source .env` first).

  Outputs (in `--out`, default `~/Videos/mehungry_promo/<timestamp>/`):
    * `raw.mp4`    — the whole take
    * `final.mp4`  — the take with the dead time cut out (login + AI wait),
                     joined by short crossfades
    * `markers.txt` — scene timestamps, to re-cut by hand in an editor

  Options:
    --db NAME          database to run against (default mehungry_promo)
    --locale el|en     UI language (default el)
    --prompt TEXT      what the user types into "Plan with AI"
    --diet NAME        omnivore | vegetarian | vegan | pescatarian (default omnivore)
    --calories N       daily calorie target typed in onboarding (default 1800)
    --size WxH         physical video size (default 1080x1920)
    --scale F          device scale factor (default 2.16 → a 500×889 CSS viewport;
                       Chrome won't size a window under 500 CSS px wide, so a
                       larger factor overflows the recorded screen)
    --port N           HTTP port for the app (default 4100)
    --out DIR          output directory
    --pace F           speed of on-camera movement: pauses, cursor travel, typing,
                       scrolls (default 0.65; 1.0 = the original, slower pace;
                       smaller = faster). Technical waits are not scaled.
    --rehearse         headless, no recording, a screenshot per scene
    --keep-user        don't delete the demo user afterwards (rehearsal on dev DB)
  """
  use Mix.Task

  alias Wallaby.Browser
  alias Wallaby.Query

  @switches [
    db: :string,
    locale: :string,
    prompt: :string,
    diet: :string,
    calories: :integer,
    size: :string,
    scale: :float,
    pace: :float,
    port: :integer,
    out: :string,
    rehearse: :boolean,
    keep_user: :boolean
  ]

  @default_prompts %{
    "el" => "Μεσογειακή εβδομάδα, πλούσια σε πρωτεΐνη, γρήγορα πρωινά",
    "en" => "Mediterranean week, high protein, quick breakfasts"
  }

  @display ":99"

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: @switches)
    cfg = config(opts)
    # Every on-camera timing goes through paced/1 (see `--pace`).
    Process.put(:promo_pace, cfg.pace)
    File.mkdir_p!(cfg.out)

    boot_app(cfg)
    xvfb = unless cfg.rehearse, do: start_xvfb(cfg)
    session = start_browser(cfg)

    state = %{cfg: cfg, session: session, t0: nil, ffmpeg: nil, marks: [], shot: 0}

    try do
      state
      |> prepare_offcamera()
      |> start_recording()
      |> scene_landing_and_signup()
      |> scene_onboarding()
      |> scene_ai_plan()
      |> scene_shopping_list()
      |> stop_recording()
      |> finish()
    rescue
      e ->
        Mix.shell().error("Take failed: " <> Exception.message(e))
        safe_screenshot(state, "failure")
        if port = Process.get(:promo_ffmpeg), do: stop_ffmpeg(port)
        reraise e, __STACKTRACE__
    after
      Wallaby.end_session(session)
      if xvfb, do: Port.close(xvfb)
      unless cfg.keep_user or cfg.db == "mehungry_promo", do: delete_demo_user(cfg)
    end
  end

  # ── Config / boot ────────────────────────────────────────────────────────

  defp config(opts) do
    locale = Keyword.get(opts, :locale, "el")

    [w, h] =
      opts
      |> Keyword.get(:size, "1080x1920")
      |> String.split("x")
      |> Enum.map(&String.to_integer/1)

    scale = Keyword.get(opts, :scale, 2.16)
    stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")

    %{
      db: Keyword.get(opts, :db, "mehungry_promo"),
      locale: locale,
      prompt: Keyword.get(opts, :prompt, @default_prompts[locale] || @default_prompts["en"]),
      diet: Keyword.get(opts, :diet, "omnivore"),
      calories: Keyword.get(opts, :calories, 1800),
      width: w,
      height: h,
      scale: scale,
      pace: Keyword.get(opts, :pace, 0.65),
      css_w: round(w / scale),
      css_h: round(h / scale),
      port: Keyword.get(opts, :port, 4100),
      out: Keyword.get(opts, :out, Path.expand("~/Videos/mehungry_promo/#{stamp}")),
      rehearse: Keyword.get(opts, :rehearse, false),
      keep_user: Keyword.get(opts, :keep_user, false),
      email: "maria#{Enum.random(1000..9999)}@m3hungry.com",
      password: "Kalimera-#{stamp}!"
    }
  end

  defp boot_app(cfg) do
    # Turnstile can't verify on localhost and would show a widget on camera.
    System.delete_env("TURNSTILE_SITE_KEY")
    System.delete_env("TURNSTILE_SECRET_KEY")

    Mix.Task.run("app.config")
    Logger.configure(level: :warning)

    repo = Application.get_env(:mehungry, Mehungry.Repo, [])
    Application.put_env(:mehungry, Mehungry.Repo, Keyword.put(repo, :database, cfg.db))

    # A copy of prod data must never fire prod's crons (social publishing,
    # token refreshes, …). Keep the queues so the meal-plan job runs.
    oban = Application.get_env(:mehungry, Oban, [])

    plugins =
      oban
      |> Keyword.get(:plugins, [])
      |> Enum.reject(fn p -> match?({Oban.Plugins.Cron, _}, p) or p == Oban.Plugins.Cron end)

    Application.put_env(:mehungry, Oban, Keyword.put(oban, :plugins, plugins))

    endpoint = Application.get_env(:mehungry_web, MehungryWeb.Endpoint, [])

    Application.put_env(
      :mehungry_web,
      MehungryWeb.Endpoint,
      endpoint
      |> Keyword.put(:http, ip: {127, 0, 0, 1}, port: cfg.port)
      |> Keyword.delete(:https)
      |> Keyword.put(:url, host: "localhost", port: cfg.port)
      |> Keyword.put(:code_reloader, false)
      # Live-reload would refresh the browser mid-take whenever a source file is
      # saved (it did: an edit during a take reloaded the calendar mid-plan).
      |> Keyword.delete(:live_reload)
    )

    Application.put_env(:phoenix, :serve_endpoints, true, persistent: true)
    Mix.Task.run("app.start")

    Application.put_env(:wallaby, :base_url, "http://localhost:#{cfg.port}")
    Application.put_env(:wallaby, :driver, Wallaby.Chrome)
    Application.put_env(:wallaby, :screenshot_dir, cfg.out)
    Application.put_env(:wallaby, :screenshot_on_failure, false)
    Application.put_env(:wallaby, :js_errors, false)
    Application.put_env(:wallaby, :max_wait_time, 10_000)
    Application.put_env(:wallaby, :chromedriver, headless: cfg.rehearse)
    # First page loads can be slow while esbuild/tailwind finish; never let the
    # WebDriver HTTP client time out under them.
    Application.put_env(:wallaby, :hackney_options, timeout: :infinity, recv_timeout: :infinity)

    Mix.shell().info("App up on http://localhost:#{cfg.port} (db #{cfg.db}); assets building…")
    # Let esbuild/tailwind finish their first build, then warm the server up.
    Process.sleep(6_000)
    warm_up("http://localhost:#{cfg.port}/#{cfg.locale}/welcome", 20)
  end

  defp warm_up(_url, 0), do: Mix.raise("app did not come up")

  defp warm_up(url, tries) do
    :inets.start()

    case :httpc.request(:get, {String.to_charlist(url), []}, [timeout: 60_000], []) do
      {:ok, {{_, status, _}, _, _}} when status in 200..399 -> :ok
      _ -> Process.sleep(1_500) && warm_up(url, tries - 1)
    end
  end

  defp start_xvfb(cfg) do
    xvfb = System.find_executable("Xvfb") || Mix.raise("Xvfb not found: sudo apt install -y xvfb")

    port =
      Port.open({:spawn_executable, xvfb}, [
        :binary,
        :exit_status,
        args: [
          @display,
          "-screen",
          "0",
          "#{cfg.width}x#{cfg.height}x24",
          "-nolisten",
          "tcp",
          "-ac"
        ]
      ])

    Process.sleep(800)
    System.put_env("DISPLAY", @display)
    # On a Wayland desktop Chrome follows WAYLAND_DISPLAY and opens on the real
    # screen, leaving Xvfb (what ffmpeg records) black. Hide Wayland from it.
    Enum.each(~w(WAYLAND_DISPLAY XDG_SESSION_TYPE), &System.delete_env/1)
    port
  end

  defp start_browser(cfg) do
    {:ok, _} = Application.ensure_all_started(:wallaby)

    base_args = [
      "--no-sandbox",
      "--no-first-run",
      "--no-default-browser-check",
      "--disable-infobars",
      "--disable-features=Translate,TranslateUI",
      "--hide-scrollbars",
      "--lang=#{cfg.locale}",
      "--force-device-scale-factor=#{cfg.scale}",
      "--window-position=0,0",
      "--window-size=#{cfg.css_w},#{cfg.css_h}"
    ]

    args =
      if cfg.rehearse,
        do: ["--headless=new" | base_args],
        # Force X11 so the window lands on the Xvfb screen being recorded.
        else: ["--kiosk", "--ozone-platform=x11" | base_args]

    capabilities = %{
      javascriptEnabled: true,
      loadImages: true,
      takesScreenshot: true,
      cssSelectorsEnabled: true,
      unhandledPromptBehavior: "accept",
      chromeOptions: %{
        args: args,
        excludeSwitches: ["enable-automation"],
        prefs: %{
          "credentials_enable_service" => false,
          "profile.password_manager_enabled" => false,
          "intl.accept_languages" => cfg.locale
        }
      }
    }

    {:ok, session} = Wallaby.start_session(capabilities: capabilities)
    unless cfg.rehearse, do: assert_fits_screen!(session, cfg)
    session
  end

  # The take is only usable if the page fills exactly the recorded screen. Chrome
  # clamps a window to ≥ 500 CSS px wide, so a scale that asks for less silently
  # overflows the right edge — check before recording anything.
  defp assert_fits_screen!(session, cfg) do
    session = Browser.visit(session, "/#{cfg.locale}/welcome")

    [w, dpr] =
      js(session, "return [window.innerWidth, window.devicePixelRatio]")

    if round(w * dpr) > cfg.width + 2 do
      Mix.raise(
        "viewport is #{w} CSS px × #{dpr} = #{round(w * dpr)} px, wider than the " <>
          "#{cfg.width} px screen; pass a smaller --scale (≤ #{Float.floor(cfg.width / 500, 2)})"
      )
    end
  end

  # ── Scenes ───────────────────────────────────────────────────────────────

  # Dismiss the cookie banner before the camera rolls (the consent cookie
  # persists for the session), so the first frame is a clean landing page.
  defp prepare_offcamera(%{session: s, cfg: cfg} = st) do
    Browser.visit(s, "/#{cfg.locale}/welcome")
    Process.sleep(1_500)

    if js(s, ~s|return !!document.querySelector('form[action="/cookie-consent/decline"] button')|) do
      Browser.click(s, Query.css(~s|form[action="/cookie-consent/decline"] button|))
      Process.sleep(1_000)
    end

    Browser.visit(s, "/#{cfg.locale}/welcome")
    wait_js(s, "return document.readyState === 'complete'", 15_000)
    Process.sleep(1_500)
    st
  end

  defp scene_landing_and_signup(%{session: s, cfg: cfg} = st) do
    st = mark(st, "landing")
    ensure_overlay(s)
    linger(1_800)
    glide(s, 260, 2_200)
    linger(900)

    st =
      if present?(s, ~s|a[href*="register"]|) do
        touch(s, ~s|a[href*="register"]|)
        st
      else
        Browser.visit(s, "/#{cfg.locale}/users/register")
        st
      end

    wait_for(s, ~s|input[type="email"]|)
    st = st |> mark("signup") |> shot("signup")
    ensure_overlay(s)
    linger(700)
    type(s, ~s|input[type="email"]|, cfg.email)
    linger(400)
    type(s, ~s|input[type="password"]|, cfg.password, 45..85)
    linger(600)
    touch(s, ~s|form button[type="submit"], form input[type="submit"]|)
    wait_for(s, ~s|input[type="password"]|)
    linger(1_400)

    # ── Cut: confirming the email + logging in is dead air on camera. ──
    st = mark(st, "cut_in:login")
    confirm_demo_user(cfg)
    Browser.fill_in(s, Query.css(~s|input[type="email"]|), with: cfg.email)
    Browser.fill_in(s, Query.css(~s|input[type="password"]|), with: cfg.password)
    Browser.click(s, Query.css(~s|form button[type="submit"], form input[type="submit"]|))
    wait_for(s, "#onboarding-modal", 20_000)
    linger(900)
    mark(st, "cut_out:login")
  end

  defp scene_onboarding(%{session: s, cfg: cfg} = st) do
    st = st |> mark("onboarding") |> shot("onboarding")
    ensure_overlay(s)
    linger(1_500)

    # Picking a language push_navigates to /<locale>/home (remounts the
    # wizard in that language) — wait for the remount before the next tap.
    unless js(s, "return location.pathname.startsWith(arguments[0])", ["/#{cfg.locale}/"]) do
      touch(s, ~s|button[phx-value-lang="#{cfg.locale}"]|)

      wait_js(
        s,
        "return location.pathname.startsWith(arguments[0])",
        15_000,
        ["/#{cfg.locale}/"],
        "locale switch"
      )

      wait_for(s, "[data-phx-main].phx-connected", 15_000)
      wait_visible(s, ~s|button[phx-value-diet="#{cfg.diet}"]|)
      ensure_overlay(s)
    end

    linger(700)
    touch(s, ~s|button[phx-value-diet="#{cfg.diet}"]|)
    linger(900)
    touch(s, ~s|button[phx-click="next_step"]|)

    wait_for(s, ~s|input[name="daily_calorie_target"]|)
    st = shot(st, "calories")
    linger(800)
    retype_number(s, ~s|input[name="daily_calorie_target"]|, to_string(cfg.calories))
    linger(1_000)

    # Admin-authored questions add a step 3 — pick the first option of each
    # choice question so the step reads as filled in.
    if present?(s, ~s|button[phx-click="next_step"]|) do
      touch(s, ~s|button[phx-click="next_step"]|)
      linger(900)
      answer_extra_step(s)
    end

    touch(s, "#onboarding_submit_button")
    wait_gone(s, "#onboarding-modal", 15_000)
    linger(1_200)
    st
  end

  defp scene_ai_plan(%{session: s, cfg: cfg} = st) do
    touch(s, ~s|a[href$="/#{cfg.locale}/calendar"]|)
    wait_for(s, "#create-week-basket", 20_000)
    st = st |> mark("calendar") |> shot("calendar_empty")
    ensure_overlay(s)
    linger(1_500)

    touch(s, ~s|.calendar-page button[aria-haspopup="true"]|)
    linger(700)
    touch(s, ~s|button[role="menuitem"]:has(path[d^="M13 10V3"])|)
    wait_visible(s, "#ai-plan-panel textarea")
    linger(900)
    type(s, "#ai-plan-panel textarea", cfg.prompt)
    linger(1_000)
    touch(s, ~s|#ai-plan-panel button[type="submit"]|)
    st = st |> mark("ai_generate") |> shot("ai_generating")

    # Show the "Planning…" spinner for a beat, then cut the wait.
    linger(3_500)
    st = mark(st, "cut_in:ai_wait")

    # Done when the submit button re-enables (generating → false). The page
    # shows success as a green line; a failure only resets the button, so the
    # reason is read from the job's tracking row.
    wait_js(
      s,
      "const b = document.querySelector('#ai-plan-panel button[type=submit]'); return !!(b && !b.disabled);",
      9 * 60_000,
      [],
      "the AI plan to finish"
    )

    cond do
      present?(s, "#ai-plan-panel p.text-green-400") ->
        :ok

      present?(s, ~s|#ai-plan-panel a[href$="/upgrade"]|) ->
        raise "AI quota exceeded — the demo user has no plan quota"

      true ->
        raise "AI plan failed: #{last_plan_error(cfg)}"
    end

    # Cut back in ~1s before the result so the spinner→result transition shows.
    st = %{st | marks: [{"cut_out:ai_wait", elapsed(st) - 1_000} | st.marks]}
    st = st |> mark("ai_result") |> shot("ai_result")
    linger(2_200)

    # Let the week sink in: slow scroll through the planned meals and back.
    glide(s, 700, 5_500, ".calendar-page")
    linger(1_200)
    glide(s, 700, 4_500, ".calendar-page")
    linger(1_000)
    glide(s, -1_400, 2_200, ".calendar-page")
    linger(900)
    st
  end

  defp scene_shopping_list(%{session: s} = st) do
    touch(s, "#create-week-basket")
    wait_for(s, ~s|[phx-click="toggle_basket"]|, 20_000)
    st = st |> mark("basket") |> shot("basket")
    ensure_overlay(s)
    linger(2_000)
    glide(s, 500, 4_500, "#shopping_basket_index")
    linger(800)

    # Tick off a few items, as if shopping.
    for _ <- 1..3 do
      sel = ~s|[phx-click="toggle_basket"]:not([data-promo-done])|

      if present?(s, sel) do
        js(s, ~s|document.querySelector('#{sel}').setAttribute('data-promo-pick','1')|)
        touch(s, ~s|[data-promo-pick="1"]|)

        js(
          s,
          ~s|const e=document.querySelector('[data-promo-pick="1"]'); if(e){e.removeAttribute('data-promo-pick'); e.setAttribute('data-promo-done','1')}|
        )

        linger(900)
      end
    end

    hide_overlay(s)
    linger(2_500)
    shot(st, "end")
  end

  # ── Recording ────────────────────────────────────────────────────────────

  defp start_recording(%{cfg: %{rehearse: true}} = st), do: %{st | t0: now()}

  defp start_recording(%{cfg: cfg} = st) do
    ffmpeg = System.find_executable("ffmpeg") || Mix.raise("ffmpeg not found")

    port =
      Port.open({:spawn_executable, ffmpeg}, [
        :binary,
        :exit_status,
        args:
          ~w(-y -loglevel error -f x11grab -draw_mouse 0 -framerate 30) ++
            ["-video_size", "#{cfg.width}x#{cfg.height}", "-i", "#{@display}.0"] ++
            ~w(-c:v libx264 -preset veryfast -crf 16 -pix_fmt yuv420p) ++
            [Path.join(cfg.out, "raw.mp4")]
      ])

    Process.put(:promo_ffmpeg, port)
    Process.sleep(500)
    %{st | ffmpeg: port, t0: now()}
  end

  defp stop_recording(%{ffmpeg: nil} = st), do: mark(st, "end")

  defp stop_recording(%{ffmpeg: port} = st) do
    st = mark(st, "end")
    stop_ffmpeg(port)
    st
  end

  defp stop_ffmpeg(port) do
    Process.delete(:promo_ffmpeg)
    Port.command(port, "q")

    receive do
      {^port, {:exit_status, _}} -> :ok
    after
      15_000 -> :timeout
    end
  end

  defp finish(%{cfg: cfg} = st) do
    marks = Enum.reverse(st.marks)

    File.write!(
      Path.join(cfg.out, "markers.txt"),
      Enum.map_join(marks, "\n", fn {name, ms} -> "#{fmt_ts(ms)}  #{name}" end) <> "\n"
    )

    unless cfg.rehearse, do: cut_final(cfg, marks)
    Mix.shell().info("Done → #{cfg.out}")
    st
  end

  # Keep [landing, end] minus every cut_in:X → cut_out:X span, joined with
  # 0.4s crossfades.
  defp cut_final(cfg, marks) do
    at = Map.new(marks)
    start = at["landing"] / 1000
    stop = at["end"] / 1000

    cuts =
      marks
      |> Enum.filter(fn {n, _} -> String.starts_with?(n, "cut_in:") end)
      |> Enum.map(fn {"cut_in:" <> k, ms} -> {ms / 1000, at["cut_out:" <> k] / 1000} end)
      |> Enum.sort()

    {segments, last} =
      Enum.reduce(cuts, {[], start}, fn {cin, cout}, {acc, from} ->
        {[{from, cin} | acc], cout}
      end)

    segments = Enum.reverse([{last, stop} | segments])
    fade = 0.4

    # One seeked input per segment (`-ss/-to` before `-i`). Trimming a single
    # input instead makes ffmpeg buffer every decoded frame until the last
    # segment is reached: a long AI wait at 1080×1920 ran out of memory (OOM kill).
    inputs =
      Enum.flat_map(segments, fn {a, b} ->
        ["-ss", f3(a), "-to", f3(b), "-i", Path.join(cfg.out, "raw.mp4")]
      end)

    trims =
      segments
      |> Enum.with_index()
      |> Enum.map_join(";", fn {_seg, i} -> "[#{i}:v]setpts=PTS-STARTPTS[s#{i}]" end)

    {chain, _, last_label} =
      segments
      |> Enum.with_index()
      |> Enum.drop(1)
      |> Enum.reduce({"", elem(hd(segments), 1) - elem(hd(segments), 0), "s0"}, fn {{a, b}, i},
                                                                                   {acc, len,
                                                                                    prev} ->
        out = "x#{i}"
        offset = len - fade

        {acc <>
           ";[#{prev}][s#{i}]xfade=transition=fade:duration=#{fade}:offset=#{f3(offset)}[#{out}]",
         len + (b - a) - fade, out}
      end)

    filter = trims <> chain <> ";[#{last_label}]format=yuv420p[v]"

    {output, code} =
      System.cmd(
        "ffmpeg",
        ["-y", "-loglevel", "error"] ++
          inputs ++
          ["-filter_complex", filter, "-map", "[v]"] ++
          ~w(-c:v libx264 -preset slow -crf 18 -movflags +faststart -r 30) ++
          [Path.join(cfg.out, "final.mp4")],
        stderr_to_stdout: true
      )

    if code != 0, do: Mix.shell().error(output)
    if code != 0, do: Mix.shell().error("final.mp4 cut failed — use raw.mp4 + markers.txt")
  end

  # ── Demo user (direct DB access: same node as the app) ───────────────────

  defp confirm_demo_user(cfg) do
    user = Mehungry.Accounts.get_user_by_email(cfg.email) || raise "demo user was not created"

    user
    |> Ecto.Changeset.change(
      confirmed_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    )
    |> Mehungry.Repo.update!()

    # Free tier has 0 AI meal plans/month — give the demo user Plus.
    Mehungry.Subscriptions.grant_plus(user.id)
  end

  defp last_plan_error(cfg) do
    import Ecto.Query

    user = Mehungry.Accounts.get_user_by_email(cfg.email)

    Mehungry.Repo.one(
      from(j in "api_meal_plan_jobs",
        where: j.user_id == ^user.id,
        order_by: [desc: j.id],
        limit: 1,
        select: {j.status, j.error}
      )
    )
    |> inspect()
  end

  defp delete_demo_user(cfg) do
    case Mehungry.Accounts.get_user_by_email(cfg.email) do
      nil -> :ok
      user -> Mehungry.Accounts.delete_user(user)
    end
  rescue
    e -> Mix.shell().error("Could not delete demo user #{cfg.email}: #{Exception.message(e)}")
  end

  # ── Human-paced actions ──────────────────────────────────────────────────

  defp touch(s, selector) do
    wait_visible(s, selector)
    ensure_overlay(s)
    js(s, "window.__promo.reveal(arguments[0])", [selector])
    Process.sleep(paced(550))
    %{"x" => x, "y" => y} = js(s, "return window.__promo.center(arguments[0])", [selector])
    move_ms = paced(650)
    js(s, "window.__promo.moveTo(arguments[0], arguments[1], arguments[2])", [x, y, move_ms])
    Process.sleep(move_ms + 50)
    js(s, "window.__promo.tap()")
    Process.sleep(140)
    click_stale_safe(s, selector, 3)
  end

  defp click_stale_safe(s, selector, tries) do
    Browser.click(s, Query.css(selector, at: 0, visible: true, count: :any))
  rescue
    e in [Wallaby.StaleReferenceError] ->
      if tries > 1 do
        Process.sleep(300)
        click_stale_safe(s, selector, tries - 1)
      else
        reraise e, __STACKTRACE__
      end
  end

  defp type(s, selector, text, delay \\ 70..140) do
    touch(s, selector)
    Process.sleep(paced(250))

    for g <- String.graphemes(text) do
      Browser.send_keys(s, Query.css(selector, at: 0, visible: true, count: :any), [g])
      Process.sleep(paced(Enum.random(delay) + if(g == " ", do: 60, else: 0)))
    end
  end

  defp retype_number(s, selector, value) do
    touch(s, selector)
    Process.sleep(paced(200))
    q = Query.css(selector, at: 0, visible: true, count: :any)
    Browser.send_keys(s, q, [:end])
    len = js(s, "return (document.querySelector(arguments[0]).value || '').length", [selector])

    for _ <- 1..max(len, 1) do
      Browser.send_keys(s, q, [:backspace])
      Process.sleep(paced(90))
    end

    Process.sleep(paced(250))

    for g <- String.graphemes(value) do
      Browser.send_keys(s, q, [g])
      Process.sleep(paced(Enum.random(110..170)))
    end

    # phx-change fires on input; blur too in case the field debounces.
    Browser.send_keys(s, q, [:tab])
  end

  defp answer_extra_step(s) do
    names =
      js(s, """
      return [...new Set([...document.querySelectorAll('#onboarding-modal input[type=radio]')]
        .map(i => i.name))];
      """) || []

    for name <- names do
      touch(s, ~s|#onboarding-modal input[type="radio"][name="#{name}"]|)
      linger(500)
    end
  end

  defp glide(s, px, ms, container \\ nil) do
    ms = paced(ms)
    ensure_overlay(s)
    js(s, "window.__promo.glide(arguments[0], arguments[1], arguments[2])", [px, ms, container])
    Process.sleep(ms + 150)
  end

  defp linger(ms), do: Process.sleep(paced(ms))

  # An on-camera duration scaled by `--pace`.
  defp paced(ms), do: max(round(ms * Process.get(:promo_pace, 1.0)), 1)

  defp hide_overlay(s), do: js(s, "window.__promo && window.__promo.hide()")

  # ── Waiting / JS plumbing ────────────────────────────────────────────────

  defp present?(s, selector) do
    ensure_overlay(s)
    js(s, "return window.__promo.find(arguments[0]) !== null", [selector]) == true
  end

  defp wait_for(s, selector, timeout \\ 10_000) do
    wait_js(s, "return !!document.querySelector(arguments[0])", timeout, [selector], selector)
  end

  defp wait_visible(s, selector, timeout \\ 10_000) do
    ensure_overlay(s)

    wait_js(
      s,
      "return !!(window.__promo && window.__promo.find(arguments[0]))",
      timeout,
      [selector],
      selector
    )
  end

  defp wait_gone(s, selector, timeout) do
    wait_js(
      s,
      "return !document.querySelector(arguments[0])",
      timeout,
      [selector],
      "gone " <> selector
    )
  end

  defp wait_js(s, script, timeout, args \\ [], label \\ "condition") do
    deadline = now() + timeout
    do_wait(s, script, args, deadline, label)
  end

  defp do_wait(s, script, args, deadline, label) do
    ensure_overlay(s)

    cond do
      safe_js(s, script, args) == true -> :ok
      now() > deadline -> raise "timed out waiting for #{label}"
      true -> Process.sleep(250) && do_wait(s, script, args, deadline, label)
    end
  end

  # Re-inject after every full page load (LiveView patches keep it, a dead
  # render — e.g. the login POST redirect — drops it).
  defp ensure_overlay(s), do: safe_js(s, overlay_js(), [])

  defp js(s, script, args \\ []) do
    ref = make_ref()
    Browser.execute_script(s, script, args, fn v -> send(self(), {ref, v}) end)

    receive do
      {^ref, v} -> v
    after
      0 -> nil
    end
  end

  defp safe_js(s, script, args) do
    js(s, script, args)
  rescue
    _ -> nil
  end

  defp mark(st, name), do: %{st | marks: [{name, elapsed(st)} | st.marks]}

  defp shot(%{cfg: %{rehearse: true}, session: s} = st, name) do
    n = st.shot + 1
    Browser.take_screenshot(s, name: "#{String.pad_leading("#{n}", 2, "0")}_#{name}")
    %{st | shot: n}
  end

  defp shot(st, _name), do: st

  defp safe_screenshot(st, name) do
    Browser.take_screenshot(st.session, name: name)
  rescue
    _ -> :ok
  end

  defp elapsed(%{t0: nil}), do: 0
  defp elapsed(%{t0: t0}), do: now() - t0
  defp now, do: System.monotonic_time(:millisecond)

  defp fmt_ts(ms) do
    s = div(ms, 1000)

    "#{String.pad_leading("#{div(s, 60)}", 2, "0")}:#{String.pad_leading("#{rem(s, 60)}", 2, "0")}.#{String.pad_leading("#{rem(ms, 1000)}", 3, "0")}"
  end

  defp f3(x), do: :erlang.float_to_binary(x / 1, decimals: 3)

  # A soft "finger" that glides to each target and pulses on tap — WebDriver
  # clicks draw no pointer, so without it things change with no visible cause.
  defp overlay_js do
    ~S"""
    // The floating mobile "Feedback" pill covers the wizard's Next button —
    // hide it on every call (cheap, survives page loads).
    document.querySelectorAll('a[href$="feedback"]').forEach(a => {
      if (getComputedStyle(a).position === 'fixed') a.style.setProperty('display', 'none', 'important');
    });
    if (window.__promo) return true;
    const c = document.createElement('div');
    c.id = '__promo_touch';
    Object.assign(c.style, {
      position: 'fixed', left: '50%', top: '72%', width: '46px', height: '46px',
      margin: '-23px 0 0 -23px', borderRadius: '50%', background: 'rgba(255,255,255,0.30)',
      border: '2px solid rgba(255,255,255,0.92)', boxShadow: '0 3px 14px rgba(0,0,0,0.40)',
      pointerEvents: 'none', zIndex: '2147483647', opacity: '0',
      transition: 'left 650ms cubic-bezier(.45,0,.2,1), top 650ms cubic-bezier(.45,0,.2,1), opacity 250ms, transform 140ms'
    });
    document.documentElement.appendChild(c);

    const visible = el => {
      const r = el.getBoundingClientRect(), cs = getComputedStyle(el);
      return r.width > 0 && r.height > 0 && cs.visibility !== 'hidden' && cs.display !== 'none' && cs.opacity !== '0';
    };
    const scroller = el => {
      for (let n = el; n && n !== document.body; n = n.parentElement) {
        const cs = getComputedStyle(n);
        if (/(auto|scroll)/.test(cs.overflowY) && n.scrollHeight > n.clientHeight + 4) return n;
      }
      return document.scrollingElement;
    };

    window.__promo = {
      find(sel) { return [...document.querySelectorAll(sel)].find(visible) || null; },
      reveal(sel) {
        const el = this.find(sel);
        if (!el) return;
        const r = el.getBoundingClientRect();
        if (r.top < 70 || r.bottom > innerHeight - 90) el.scrollIntoView({behavior: 'smooth', block: 'center'});
      },
      center(sel) {
        const r = this.find(sel).getBoundingClientRect();
        return {x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2)};
      },
      moveTo(x, y, ms) {
        c.style.transitionDuration = `${ms}ms, ${ms}ms, 250ms, 140ms`;
        c.style.opacity = '1'; c.style.left = x + 'px'; c.style.top = y + 'px';
      },
      tap() {
        c.style.transform = 'scale(0.72)';
        setTimeout(() => { c.style.transform = 'scale(1)'; }, 170);
        const r = document.createElement('div');
        Object.assign(r.style, {
          position: 'fixed', left: c.style.left, top: c.style.top, width: '46px', height: '46px',
          margin: '-23px 0 0 -23px', borderRadius: '50%', border: '2px solid rgba(255,255,255,0.8)',
          pointerEvents: 'none', zIndex: '2147483646', transition: 'transform 450ms ease-out, opacity 450ms ease-out'
        });
        document.documentElement.appendChild(r);
        requestAnimationFrame(() => { r.style.transform = 'scale(2.2)'; r.style.opacity = '0'; });
        setTimeout(() => r.remove(), 500);
      },
      hide() { c.style.opacity = '0'; },
      glide(px, ms, containerSel) {
        let box = containerSel ? document.querySelector(containerSel) : null;
        if (box) box = (box.scrollHeight > box.clientHeight + 4) ? box : scroller(box.firstElementChild || box);
        if (!box) {
          const candidates = [document.scrollingElement, ...document.querySelectorAll('*')]
            .filter(n => n && n.scrollHeight > n.clientHeight + 40 && /(auto|scroll)/.test(getComputedStyle(n).overflowY) || n === document.scrollingElement);
          box = candidates.sort((a, b) => (b.scrollHeight - b.clientHeight) - (a.scrollHeight - a.clientHeight))[0];
        }
        const from = box.scrollTop, t0 = performance.now();
        const ease = t => t < .5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
        const step = now => {
          const t = Math.min(1, (now - t0) / ms);
          box.scrollTop = from + px * ease(t);
          if (t < 1) requestAnimationFrame(step);
        };
        requestAnimationFrame(step);
      }
    };
    return true;
    """
  end
end
