# Promo videos (Reels / TikTok): the reusable recorder

A scripted screen recording of the **real app** driven like a person would use it,
recorded straight to a vertical video for social media. The first video built with it
(the "new user" story, Greek and English cuts, 2026-11-24) is:

1. landing page → sign up (typed at human speed)
2. onboarding wizard (language, diet, calorie target, country)
3. calendar → **Plan with AI** → full-screen loader → the generated week
4. **Shopping list** built from that week, a few items ticked off

Nothing is mocked. The plan is a real `UserMealPlanAgent` run against a fresh **snapshot
of production data**, so the recipes, photos and nutrition on screen are the real catalogue.

Format: **vertical 9:16, 1080×1920, 30 fps, H.264**, which posts as-is to Reels and TikTok.
A horizontal cut is one flag (`--size 1920x1080`, see *Flags*).

This page is the runbook: use it to re-record this video, or to build a new one on the
same setup.

---

## 1. One-time setup

```bash
# System tools: the virtual screen, the encoder, and Chrome's WebDriver
sudo apt install -y xvfb ffmpeg
# chromedriver must be on PATH and match your Chrome's major version
# (same requirement as the Wallaby feature tests — see infrastructure/operations.md)
chromedriver --version; google-chrome --version
```

- **API keys:** the recorder uses the real AI, so `.env` needs `ANTHROPIC_API_KEY` and
  `OPENAI_API_KEY` (recipe search embeddings).
- **Prod snapshot access:** put the prod DB URL in `~/.config/mehungry/prod_db_url`
  (`chmod 600`), or export `PROD_DATABASE_URL`. Only `snapshot_prod.sh` reads it, read-only.
- **Restart a running dev server once** after pulling this: `apps/mehungry_web/mix.exs`
  compiles `dev/` and makes Wallaby a `[:dev, :test]` dependency.

## 2. Record a video

```bash
cd ~/git/mehungry_umbrella

# (a) Fresh prod snapshot into a SEPARATE local DB, `mehungry_promo`.
#     Only needed when you want newer data; the DB survives reboots.
scripts/promo/snapshot_prod.sh

# (b) Environment for every take
set -a; source .env; set +a
unset WAYLAND_DISPLAY XDG_SESSION_TYPE        # belt and braces; the task also does this
export MIX_BUILD_ROOT=$PWD/_build_promo
mix compile                                   # ALWAYS: Mix loads the task module before it
                                              # recompiles, so a stale build runs otherwise

# (c) Optional dry run: headless, a screenshot per scene, no video (~3 min, 1 AI plan)
mix do --app mehungry_web promo.record --rehearse --out /tmp/promo_rehearsal

# (d) The real take — Greek (default) and English
mix do --app mehungry_web promo.record
mix do --app mehungry_web promo.record --locale en
```

Run it from the **umbrella root** with `mix do --app mehungry_web …`. Running it from inside
`apps/mehungry_web` fails with "dependency not locked".

A take is about 2–3 minutes of wall time, mostly the AI plan. **Don't save source files
while a take runs**; live-reload is disabled for the take, but it's a good habit anyway.

### Output

Each take writes to `~/Videos/mehungry_promo/<timestamp>/`:

| File | What |
|---|---|
| `final.mp4` | The take with the dead time cut out (email confirm + login, and the AI wait), joined by 0.4 s crossfades. **Ready to post.** |
| `raw.mp4` | The whole uncut take. |
| `markers.txt` | Scene timestamps (into `raw.mp4`), for re-cutting by hand in an editor. |

Takes recorded so far (pace 0.65): `20261124-181044` (Greek, 68 s) and
`20261124-181852` (English, 66.5 s).

### Check a take before posting

`final.mp4` can come out black or clipped while the task still reports success (see
*Troubleshooting*), so look at it, or pull a frame strip:

```bash
d=$(ls -td ~/Videos/mehungry_promo/*/ | head -1); f=$d/final.mp4
dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 $f)
for i in 0 1 2 3 4 5 6 7; do
  ffmpeg -v error -y -ss $(echo "$dur*($i*0.13+0.03)" | bc) -i $f -frames:v 1 -vf scale=240:427 /tmp/f$i.png
done
ffmpeg -v error -y $(for i in 0 1 2 3 4 5 6 7; do echo -i /tmp/f$i.png; done) \
  -filter_complex hstack=inputs=8 /tmp/strip.png && xdg-open /tmp/strip.png
```

## 3. Flags

| Flag | Default | What |
|---|---|---|
| `--locale el\|en` | `el` | UI language. Also picks the default prompt. |
| `--prompt "…"` | per locale | What gets typed into Plan with AI. EL: "Μεσογειακή εβδομάδα, πλούσια σε πρωτεΐνη, γρήγορα πρωινά"; EN: "Mediterranean week, high protein, quick breakfasts". |
| `--diet` | `omnivore` | Picked in onboarding: omnivore / vegetarian / vegan / pescatarian. |
| `--calories N` | `1800` | Typed into onboarding's daily target. The plan aims for ±10% of it. |
| `--pace F` | `0.65` | Speed of everything on camera: pauses, cursor travel, typing, scrolls. `1.0` is the original slower pace; `0.5` is snappier. Technical waits (app boot, the AI) are not scaled. |
| `--size WxH` | `1080x1920` | Physical video size. |
| `--scale F` | `2.16` | Device scale factor. CSS viewport = size ÷ scale (500×889 by default = the mobile layout). Must leave the viewport **≥ 500 CSS px wide** (see *Troubleshooting*). For a horizontal cut: `--size 1920x1080 --scale 1.5`. |
| `--db NAME` | `mehungry_promo` | Database to run against. `--db mehungry_server_dev` is handy with `--rehearse` to dry-run selectors. |
| `--port N` | `4100` | Port the task's own app instance listens on. |
| `--out DIR` | `~/Videos/mehungry_promo/<ts>` | Output directory. |
| `--rehearse` | off | Headless, no video, a screenshot per scene into `--out`. |
| `--keep-user` | off | Keep the demo user afterwards (it's kept anyway on `mehungry_promo`). |

## 4. Making a new video

Everything lives in one file: **`apps/mehungry_web/dev/mix/tasks/promo.record.ex`**
(`Mix.Tasks.Promo.Record`). It's dev-only (`elixirc_paths(:dev)`), so it never ships in
the release. A new video is a new sequence of **scenes**; the setup (app boot, Xvfb,
Chrome, ffmpeg, auto-cut) is reused as-is.

### The pipeline (`run/1`)

```elixir
state
|> prepare_offcamera()          # dismiss cookie banner etc. BEFORE recording starts
|> start_recording()            # ffmpeg x11grab starts here; t0 = 0:00
|> scene_landing_and_signup()
|> scene_onboarding()
|> scene_ai_plan()
|> scene_shopping_list()
|> stop_recording()
|> finish()                     # writes markers.txt + cuts final.mp4
```

Each scene takes and returns the state map `%{cfg, session, marks, …}`. For a new video,
write new `scene_*` functions and change this pipe. Copying the file to a new task
(e.g. `promo.record_nutritionist`) works too, if you want both videos available.

### Helpers to build scenes with

| Helper | Use |
|---|---|
| `touch(s, selector)` | Wait for the element, glide the on-screen "finger" to it, pulse, click. Use this for **every** on-camera click. WebDriver clicks draw no pointer. |
| `type(s, selector, text)` | Touch the field, then type one character at a time (70–140 ms × pace). |
| `retype_number(s, selector, value)` | Clear a number input with visible backspaces, then type. |
| `glide(s, px, ms, container \\ nil)` | Eased scroll by `px` over `ms`. Pass a CSS selector to scroll an inner scroll container rather than the page. |
| `linger(ms)` | An on-camera pause (scaled by `--pace`). Use this, **not** `Process.sleep`, for any wait the viewer sees. |
| `wait_visible/2`, `wait_gone/3`, `wait_js/5` | Wait for UI state. `wait_js` polls a JS expression, e.g. "button re-enabled". |
| `mark(st, name)` | Write a scene timestamp to `markers.txt`. |
| `mark(st, "cut_in:X")` … `mark(st, "cut_out:X")` | Everything between the pair is **removed from `final.mp4`** (crossfaded). Use it for any dead time: waiting on the AI, an email round-trip. |
| `shot(st, name)` | Rehearsal-only screenshot named `NN_name.png`. A no-op in a real take. |
| `js/3`, `safe_js/3` | Run page JS (e.g. hide a widget for the take). |

Example of a scene with a cut:

```elixir
defp scene_example(%{session: s} = st) do
  st = mark(st, "example")
  touch(s, ~s|a[href$="/#{st.cfg.locale}/foods"]|)
  wait_visible(s, "#foods-grid")
  linger(1_200)
  glide(s, 600, 3_000)
  st = st |> mark("cut_in:slow_thing") |> shot("example")
  wait_js(s, "return !!document.querySelector('#done')", 60_000)
  mark(st, "cut_out:slow_thing")
end
```

Tips:
- Prefer stable `id`s / `phx-*` attributes as selectors. Text selectors break across locales.
- Anything that must not appear on camera (banners, popups) goes in `prepare_offcamera/1`,
  or gets hidden with `js/3` right before the scene.
- Rehearse first: it catches selector breaks in ~3 minutes without needing Xvfb.

## 5. How it works

- **Boots its own app instance** on port 4100 against `--db`, with **Oban cron removed**:
  prod data must never fire prod's crons (social publishing, token refreshes). The queues
  stay up so the meal-plan job runs. Turnstile is unset, and the **code reloader and
  live-reload are off**, so saving a file can't refresh the page mid-take.
- **`MIX_BUILD_ROOT=_build_promo`** keeps the recorder's build separate. A running
  `iex -S mix phx.server` would otherwise recompile `_build/dev` with its old dependency set
  and delete the task's beam.
- **Chrome on a private Xvfb screen** (`:99`, 1080×1920), kiosk mode, device scale 2.16
  → a 500×889 CSS viewport (the mobile layout). Chrome is forced onto **X11**
  (`--ozone-platform=x11`, Wayland env vars removed). Before recording, the task checks
  that the page width × pixel ratio fits the screen, and aborts if not. **ffmpeg
  `x11grab`** records only that screen; your real desktop is never captured.
- **Human pacing:** the finger overlay, per-character typing and eased scrolls, all scaled
  by `--pace`. The floating mobile "Feedback" pill (it covers the wizard's Next button) is
  hidden every time the finger overlay is drawn. A page that renders it after the last touch
  (the shopping list's closing shot) can still show it.
- **Demo user:** a fresh `maria<4 digits>@m3hungry.com`. Don't use a `+` alias: the signup
  canonical-email dedupe strips it, so a second run would collide. The task confirms the
  account directly in the DB (the confirmation email is dead air) and grants it
  `m3hungry_plus`, because the free tier has 0 AI plans a month.
- **Auto-cut:** each `cut_in:X` / `cut_out:X` pair is removed from `final.mp4`. The AI wait
  shows about 3.5 s of the full-screen loader, then cuts to 1 s before the result.
- **AI failures:** when a plan fails, the calendar shows no error on mobile (the loader just
  closes), so the task reads the reason from the job's `api_meal_plan_jobs` row and prints it.

## 6. Snapshot safety (`scripts/promo/snapshot_prod.sh`)

- It only reads prod (pg_dump), and the URL is split into libpq env vars so the password
  never appears in `ps`.
- It restores into `mehungry_promo`, and refuses `mehungry_server_dev`/`_test`.
- **Not copied** (schema only, no data):
  - `oban_jobs`/`oban_peers`: prod's queued jobs must never replay locally.
  - `users_tokens`, `user_devices`, `professional_google_accounts`: live credentials.
  - The bulky research/literature corpus (`*_responses`, `study_*`, `scientific_studies`,
    `*_mined_facts`, …), which the consumer flow never shows.
- The Supabase pooler drops long COPY streams, so the script dumps the schema once, then
  the data in short connections: big tables one per connection, small ones 40 per
  connection, each retried up to 4×. It then resets sequences and **refreshes the
  materialized views** (`recipe_search`, `research_search`), which data dumps leave empty.
- The script is ignored by `.gitignore`'s `*.sh` rule. Commit it with `git add -f`.

## 7. Troubleshooting

| Symptom | Cause → fix |
|---|---|
| `final.mp4` is **all black**, but the task said "Done". | Chrome opened on your real (Wayland) desktop instead of Xvfb. Fixed in the task (`--ozone-platform=x11`, Wayland vars removed). If it recurs, check that `unset WAYLAND_DISPLAY` ran and that `--kiosk` is followed by `--ozone-platform=x11` in `start_browser/1`. |
| The **right edge is cut off**. | Chrome won't make a window narrower than 500 CSS px; a scale that asks for less overflows the screen. Keep `width ÷ scale ≥ 500`. The task now aborts with the right maximum `--scale`. |
| The page **reloads mid-take**. | Live-reload refreshed it after a file save. It's disabled in the task now; don't edit files during a take anyway. |
| `AI plan failed: "HTTP request failed: :nxdomain"` | DNS failure reaching the AI APIs. Check `getent hosts api.anthropic.com api.openai.com`, then retry. |
| `AI plan failed: … max_iterations_reached` and the model says the catalog is empty | The planner found no recipes. Before 2026-11-24 the consumer planner only searched the user's own recipes (a new user has none); it now ranks own → saved → public. Also check the snapshot has recipes with embeddings. |
| `materialized view "recipe_search" has not been populated` | Old snapshot. `psql -d mehungry_promo -c "refresh materialized view recipe_search"` (the script does this now). |
| `AI plan failed: {"generating", nil}` | The task saw the Generate button re-enable while the job was still running; in practice that was a mid-take page reload. See the live-reload row above. |
| `AI quota exceeded` | The demo user lacks `m3hungry_plus`. Check `confirm_demo_user/1`. |
| The run executes old code. | You skipped `mix compile` with `MIX_BUILD_ROOT=_build_promo` set. |
| `final.mp4 cut failed` / an unreadable `final.mp4` ("moov atom not found") | ffmpeg was OOM-killed while cutting a long take (an older version trimmed one input and buffered every frame until the last segment). Fixed: each segment is now its own seeked input (`-ss/-to -i raw.mp4`), ~1.8 GB peak. To re-cut an old take, rebuild the command from `markers.txt` the same way. |
| "dependency not locked" | You ran it from inside `apps/mehungry_web`. Run it from the umbrella root with `mix do --app mehungry_web …`. |
