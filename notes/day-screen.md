# Front reports and the day screen

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
