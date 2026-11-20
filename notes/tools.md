# Helper tools and tests

Moved from CLAUDE.md (2026-11-01). Read when working on this area; keep it up to date.

## Running all tests (A7, 2026-11-20)
- `godot --headless --path . --script tools/run_all.gd` runs every test listed in `tools/tests.cfg`,
  one after another, each in its own fresh Godot (so one test can't spoil the next), and prints a
  table. Options after `--`: `--quick` (skip test_coop, test_net3_coop, test_benchmark),
  `--only t5,d9` (names without `test_` / `.gd`; also runs "manual" ones), `--all` (also "manual"),
  `--no-window` (skip `window` tests). Exit code 1 if any test failed.
- A test FAILS if a line starts with `FAIL`, a line says `RESULT: FAILED` / `BROKEN` or its end line
  has a count above 0 ("2 failure(s)"), Godot prints `SCRIPT ERROR` / `Parse Error` / `Invalid call` /
  `Invalid access` / `Failed to load script` (the test is then stopped 3 s later), it quits with a
  code other than 0, its end line (`end=` in tests.cfg, default `RESULT:`) never comes, or it runs
  past its time limit. The "leaked at exit" ERROR lines at the end are normal and ignored.
- Whole output of each test: `tools/test_logs/<name>.log` (git-ignored).
- `window` tests (`test_mouse`) need a display: on Linux without `DISPLAY` they are skipped, so run
  the whole runner under `xvfb-run -a` in the cloud. On Windows a window opens for a moment.
- `tests.cfg` line: `<script> <limit s> [window] [manual] [args=a,b] [end=TEXT]` (end= last).
  `soak_coop.gd` is `manual`. The other soaks (`soak_m3/g1/g2`) only report, they don't check,
  so they are not in the list.
- GitHub: `.github/workflows/tests.yml` runs it on every push / pull request (not for pushes that
  only change `docs/`, `notes/` or `*.md`) on ubuntu-24.04 with Godot 4.7.2 (cached), a project
  import and xvfb. A failed run keeps `tools/test_logs/` as the "test-logs" download for 14 days.
  By hand: Actions → Tests → Run workflow, tick "all" for the manual tests too.
- `test_benchmark.gd` was flaky ("15 soldiers spawned"): the player fires, so one soldier may just
  have fallen at the end. It now counts the most soldiers at once during the run.

## Helper tools (`tools/`, not part of the game)
Run with a Godot 4.7.2 binary from the project folder, e.g.
`godot --headless --path . --script tools/test_m3.gd`.
- `setup_project.gd` writes project settings + input map. `build_scenes.gd` generated the
  scenes/materials/weapon & enemy data. **It overwrites scenes** – once the owner edits scenes in the
  editor, edit the .tscn files (or the editor) instead of regenerating, unless he agrees.
- `bake_csg.gd` bakes `levels/source/trench_csg.tscn` into `levels/baked/*.res`; then rebuild the
  level (`build_scenes.gd`) and run `bake_nav.gd`. `make_sounds.py` synthesizes placeholder sounds.
- Run tests through `tools/run.gd` (see above): `test_m1.gd` … `test_m5.gd`,
  `test_benchmark.gd`, `test_mouse.gd` (needs a real window, e.g. xvfb),
  `shots_p1.gd <prefix> [views]` (graphics screenshots, needs xvfb), `test_w1.gd`,
  `shots_w1.gd [prefix]` (weapons + Maxim screenshots), `test_w2.gd`, `shots_w2.gd`, `shots_w3.gd` (Suomi cocking handle, cases), `check_web_pack.gd` also checks the W3 parts, `test_g1.gd`,
  `soak_g1.gd`, `shots_g1.gd`, `test_g2.gd`, `soak_g2.gd`, `shots_g2.gd`, `make_whistle.py`, `shots_reports.gd [days…]` (day screen: completed banner, title, typing, read), `test_background.gd`, `test_artillery.gd`, `shots_artillery.gd`, `test_airraid.gd`, `shots_airraid.gd`, `shots_drum.gd`,
  `_model_shots.gd` (renders imported
  models from 4 sides), `import_weapons.py` (unpacks weapon downloads),
  `make_textures.py` (regenerates `assets/textures/`), `test_p2.gd`, `shots_p2.gd` (soldier
  poses, sprays), `shots_battle.gd` (a wave from the trench), `make_buses.gd` (audio buses),
  `check_web_pack.gd` (checks the exported pck, see gotchas),
  `test_t1.gd`, `shots_t1.gd` (tank), `make_tank_sounds.py` (tank sounds from assets_source/),
  `test_t2.gd`, `shots_t2.gd` (Molotov cocktail), `make_molotov_sounds.py`,
  `test_t3.gd`, `shots_t3.gd` (tanks in the waves, forest lane),
  `test_turret.gd` (T4 turret speeds / delays), `make_turret_sounds.py`,
  `test_b3.gd` (weather per battle, fog limits enemy sight), `shots_weather.gd` (all ten looks), `make_weather.gd` (writes resources/weather/), `test_b1.gd` (loading-screen briefing + march), `shots_briefing.gd` (loading screen for battles 1, 7, 9), `test_controls.gd`, `shots_controls.gd` (Controls screen, tank route ends, Molotov hint),
  `shots_l2.gd` (bunker views), `test_l3.gd`, `shots_l3.gd` (communication trenches, rear spawns, battle 6 retake), `test_p3.gd` (P3 3D resolution cap: maths per screen height, a 4K window, saved setting, menu hint; uses user://settings.cfg and puts the earlier file back), `test_d1.gd` (D1 saved run: retry, Continue, new run, victory clears it; uses user://run.cfg and puts an earlier file back), `test_v1.gd`, `shots_flash.gd` (V1 enemy muzzle flashes in the dark: measures how much a flash stands out per look, 60/120 m), `test_l1.gd`, `shots_l1.gd` (trench line, exits, the 4 firing positions; top views + player views),
  `earthwork_snow.gd` (V2: makes the soft snow meshes for the builder), `test_v2.gd`, `shots_v2.gd` (V2 snow lips / drifts / heaps / bunker snow; `shots_v2.gd before_` saves with another file prefix to compare),
  `test_v4.gd`, `shots_v4.gd` (V4 sandbags: nobody sees through the wall – thousands of straight and slanted lines against the bag mesh –, loophole free, collision unchanged; `shots_v4.gd before_` saves with another file prefix),
  `test_t5.gd` (T5 armour: a tank / wreck between a soldier and the player stops his sight and bullets, another tank's sight and fire, and a shell's blast),
  `test_d9.gd` (D9 hit zones: head / body / legs for a standing, kneeling and prone soldier, damage per weapon, head-shot ring, direct damage untouched),
  `test_c1.gd` (C1 climbing out of the trench: front / rear wall, from a crouch, time, no firing, bottle rules, firing position, death on the wall),
  `test_v10b.gd`, `shots_v10b.gd [prefix]` (V10b: bodies handed to the BodyKeeper, caps, pause, new day keeps 12 with snow, a soldier killed in the air comes down; tank track strips on the ground, pool wraps round, cleared at the day change),
  `test_v10a.gd`, `shots_v10a.gd [battle] [frames] [wind]` (V10a: wind per battle reaches the tree materials, cloud drift speed / update rate, no TIME in the sky shader; the shots script needs xvfb and `--fixed-fps 20`),
  `test_t6.gd`, `shots_t6.gd [battle]` (T6 running tracks: track speeds from the hull's movement – straight, reverse, bends, on the spot, standing, teleport, cap –, materials per tank, wheel data in the model's UV2; pictures from a camera riding beside the tank, needs xvfb and `--fixed-fps 30`), `import_weapons.py --t26-wheels` (T6: writes only the wheel axles into the unpacked T-26 model),
  `web_guard_test.py` (web export: Leave-site warning, fullscreen "hold Esc" notice),
  `test_grenades.gd`, `shots_grenades.gd` (GR1 hand grenades: model, throw maths, bounce, blast + cover, limits, when a soldier throws, bunker throws, dropped grenade, HUD icon; GR2 throwing back: grab range, rules, fuse in the hand, kill credit, F key, saved run, end screen; the shots script needs xvfb), `import_weapons.py --f1` (GR1: rebuilds the F-1 grenade model; needs numpy + meshoptimizer),
  `test_coop.gd` (NET1 co-op: starts a second headless copy as the client over ENet on port 7791 – lobby, load gate, players on both, Soviets and wave number on the client, a client shot kills a Soviet and counts for him, his player goes when he leaves; ~40 s),
  `soak_coop.gd [--log=file]` (NET2 co-op scenario: a headless client copy, muted, does everything – walk, fire, reload, Suomi, Maxim, Molotov, grenade throw-back, climb, bandage, death, both die at once, day screen waits for him, defeat, host's retry to battle 2 – and reports what his own screen shows; its output goes to the log file; ~3 min; run before co-op commits),
  `test_net2b.gd` (NET2b Finnish soldier body: Soviet meshes unchanged, low-poly one-draw-call mesh, grime, own body hidden / other shown, turns, pitch, aim, grip, crouch, legs, weapon switch, muzzle flash, bottle, gun on the back, climb, bandage, Maxim grips, dead + respawn, teleport), `shots_net2b.gd [prefix] [battle]` (NET2b screenshots, needs xvfb; fake players "2"… stand in front of the trench),
  `test_net3.gd` (NET3 NetSmoother on made-up updates: even walking on a LAN / bad connection, delay, extrapolation limit, teleport jump, own player not delayed, turning, lag simulator, scenes' sync settings, host copy), `test_net3_coop.gd [--lag] [--log=file]` (NET3 two copies, port 7793: the client measures how evenly walking Soviets move smoothed vs raw, delay, updates/s, jumps, how far behind the host; `--lag` = client with the lag simulator; ~1 min),
  `test_tr1.gd` (TR1 ground tiles: every point drawn at the collision height, edges match, no LOD, drawn surface = collision surface), `bench_tr1.gd [counts]` (TR1: draw calls / triangles per ground tile count, static views + benchmark route; needs xvfb),
  `soak_m3.gd`: automated checks. `shots*.gd`: screenshots (need a GL window).
  Run all tests before every commit (`tools/run_all.gd`, see above).
