# Helper tools and tests

Moved from CLAUDE.md (2026-11-01). Read when working on this area; keep it up to date.

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
  `shots_w1.gd [prefix]` (weapons + Maxim screenshots), `test_w2.gd`, `shots_w2.gd`, `test_g1.gd`,
  `soak_g1.gd`, `shots_g1.gd`, `test_g2.gd`, `soak_g2.gd`, `shots_g2.gd`, `make_whistle.py`, `shots_reports.gd [days…]` (day screen: completed banner, title, typing, read), `test_background.gd`, `test_artillery.gd`, `shots_artillery.gd`, `shots_drum.gd`,
  `_model_shots.gd` (renders imported
  models from 4 sides), `import_weapons.py` (unpacks weapon downloads),
  `make_textures.py` (regenerates `assets/textures/`), `test_p2.gd`, `shots_p2.gd` (soldier
  poses, sprays), `shots_battle.gd` (a wave from the trench), `make_buses.gd` (audio buses),
  `check_web_pack.gd` (checks the exported pck, see gotchas),
  `test_t1.gd`, `shots_t1.gd` (tank), `make_tank_sounds.py` (tank sounds from assets_source/),
  `test_t2.gd`, `shots_t2.gd` (Molotov cocktail), `make_molotov_sounds.py`,
  `test_t3.gd`, `shots_t3.gd` (tanks in the waves, forest lane),
  `test_turret.gd` (T4 turret speeds / delays), `make_turret_sounds.py`,
  `test_b3.gd` (weather per battle), `shots_weather.gd` (all ten looks), `make_weather.gd` (writes resources/weather/), `test_b1.gd` (loading-screen briefing + march), `shots_briefing.gd` (loading screen for battles 1, 7, 9), `test_controls.gd`, `shots_controls.gd` (Controls screen, tank route ends, Molotov hint),
  `shots_l2.gd` (bunker views), `test_l1.gd`, `shots_l1.gd` (trench line, exits, the 4 firing positions; top views + player views),
  `web_guard_test.py` (web export: Leave-site warning, fullscreen "hold Esc" notice),
  `soak_m3.gd`: automated checks. `shots*.gd`: screenshots (need a GL window).
  Run all tests before every commit.
