# Battle briefings (B1) and the day screen

**B1 (2026-11-08, owner):** the ten battles have REAL DATES now (30 Nov, 17 Dec, 19 Dec, 22 Dec 1939,
1 Feb, 6 Feb, 11 Feb, 12 Feb, 13 Feb, 15 Feb 1940), weather lines and a briefing text – the owner's
table, no place names, no times (his choice: only date, weather, briefing). Battle 9 (13 Feb) has a
COPY of battle 8's text until the owner writes his own. Data: `MISSIONS` in `tools/build_scenes.gd`
→ `resources/front_reports.tres` (class `FrontReports` kept: `dates`, `texts`, `weathers`,
`photos`; `get_report(n)` / `get_weather(n)` / `get_photo(n)` for BATTLE n). Photos are the old
order (battle n = the old day n's photo). Gameplay/wave lists unchanged.
- Battle 1: the briefing is on the loading screen (`LoadingScreen._add_briefing()`, built in code
  under the title: old-print photo, date, weather, text; also for the Test Mode battle; none for
  the benchmark). Battles 2+: after battle n is cleared the day screen shows the briefing of
  battle n+1 (`DayScreen.open(cleared)` reads n+1; title "B A T T L E n", header "B R I E F I N G",
  weather lines + text typed out, "[Space] Continue", English). The after-battle front reports
  are not shown any more; the victory screen shows only the date of the last battle.
- The owner's ten Finnish front reports (21.12.1939 … 01.01.1940) are kept unchanged as
  `OLD_FRONT_REPORTS` in the builder – NEVER reword them; they can come back, e.g. with new dates.
- Weather/time are TEXT only for now (the scene is the same clear day turning to dusk) – next
  milestone: weather + time of day per battle. Tests: `test_b1.gd`, `test_g2.gd`;
  screenshots `shots_briefing.gd`, `shots_reports.gd`.

**B2 (loading screen march):** everything is built in `loading_screen.gd` (no scene change, no new
class): `_add_march()` adds `Root/Snow` (40 flakes, normalised positions, drawn by the `draw` signal),
`Root/Center/VBox/MarchPath` (96 px tall, soldier drawn in a 50 × 100 box with `Transform2D` helpers
`_soldier_rect` / `_turn_about`, colours from the owner's HTML example) and `Percent`; the old
`ProgressBar` stays (hidden) and counts, `_shown = min(bar.value, elapsed / MIN_MARCH * 100)` is what
the soldier, the percentage and the phrase use. `_step()` no longer writes the status text while
marching. Photo box 520 × 300 so the whole stack (706 px with the click prompt) fits 720.
Tests in `test_b1.gd`, screenshots `shots_briefing.gd` (`march_5/50/100.png`).

# (older) Front reports and the day screen (before B1)

Moved from CLAUDE.md (2026-11-01). Read when working on this area; keep it up to date.

## Front reports / day screen – how it is built
- `FrontReports` resource (`scripts/game/front_reports.gd`, `resources/front_reports.tres`, written
  by the builder from `FRONT_REPORTS` = [date, owner's text, photo file]): `dates`, `texts`,
  `photos` (res paths, `PackedStringArray()` defaults because of the export bug).
  `get_report(wave)` → [date, text] or empty; `get_photo(wave)` loads the photo on demand.
- Photos: `assets/photos/sa_kuva_*.jpg` (SA-kuva, CC BY 4.0, credited in CREDITS.md and on screen
  "Kuva: SA-kuva"), made from the owner's originals in `assets_source/` (≈5000 px) → greyscale,
  1280 px, JPG q86. Import: lossy WebP (`compress/mode=1`, quality 0.85), no mipmaps ≈ 150 kB each.
  Day → photo (owner's order, changed after T2): 21.12 144612 (anti-tank rocks), 22.12 117623
  (frosted wire / spruce), 23.12 a_4 (misty field, fence), 24.12 a_511 (captured tank), 25.12 a_126,
  26.12 a_125 (officers), 27.12 a_8 (trench, upright photo), 28.12 a_123 (dark foxhole),
  31.12 144607, 01.01 a_129. Spares (originals in assets_source/ only): 144608, a_128, 144616,
  144609, a_127, 144604, 2224, 129503. The owner rewrote all ten front-report texts at the same time.
- `DayScreen` (HUD/DayScreen, `scripts/ui/day_screen.gd`, built by `_build_day_screen()`): HUD
  `_update_day_screen()` watches the synced `MatchDirector.waves_cleared` (co-op clients too, no RPC)
  and calls `open(wave, reports)`; not after the last wave (end screen takes over, `close_now()`).
  Timeline: `_t` starts at −`intro_delay` (2.5 s: HUD wave banner "WAVE n COMPLETED", screen still
  clear, countdown already held; static starts at `_t` = 0), black 0–1 s, photo 1–2.2 s, title ~2 s, telegram types from `type_start` 3 s at
  `type_speed` 28/s, then `read_time` 7 s; photo zooms `zoom` 6 % over the screen; Space (jump) /
  Enter after `skip_after` 1.5 s; a new wave starting also closes it. Not paused: SFX + Ambience
  buses are ducked `duck_db` −20 dB (Ambience keeps Settings' formula). Host: `WaveSpawner.hold`
  stops the WAITING countdown while it is open. Static = `RecordedSounds "radio_static"` (silent
  if missing), clatter = `"telegraph"`. `Content` hangs from the screen centre (photo area centred
  at (−300, 30), telegram at (50, −140), 530 px wide).
- `resources/shaders/old_photo.gdshader` (canvas_item): warm grey tone, 18 fps film grain,
  vignette, flicker; writes `COLOR = vec4(g * tone, COLOR.a)`.
- Victory: `EndScreen.open(director, player, reports)` shows the last day's report.
- `tools/shots_reports.gd [days…]` (screenshots, xvfb), checks in `test_g2.gd`, `test_m3.gd`,
  `check_web_pack.gd`.
