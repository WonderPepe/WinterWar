# Gotchas learned (full list)

Moved from CLAUDE.md (2026-11-01). Read when working on this area; keep it up to date.

## Gotchas learned
- **Export bug:** `@export var x: PackedStringArray = []` loses the scene's values when the export
  converts scenes to binary (web build showed hidden Mosin parts, Maxim didn't turn). Use
  `= PackedStringArray()` as the default. Check exports with `tools/check_web_pack.gd`. The
  export also caches converted scenes in `.godot/exported/` – delete it if in doubt.
- **Particle colour bug:** CPUParticles3D colours (`vertex_color_use_as_albedo` + `color` /
  `color_ramp`) render BLACK in WebGL AND on the owner's Windows/AMD desktop (dark haze from breath and
  Maxim smoke). `ImpactEffects.web_fallback(p)` now ALWAYS turns them into a fixed material colour
  + shrink-away curve. Every new particle effect must call it; set strength via the material's
  `albedo_color.a`. (MultiMesh instance colours on the trees are fine.)
- Shader warm-up effects must be hidden afterwards (`ImpactEffects.hide_all()`), or the warm-up
  smoke hangs in front of the camera when the game starts.
- Editor re-imports: the owner's editor switched the imported weapon textures to VRAM compressed +
  mipmaps (normal maps as normal maps). Keep those `.import` files. The Web preset exports only
  desktop formats (`for_mobile=false`), otherwise the textures are stored twice.
- SurfaceTool: `set_skin_weight_count()` must be called BEFORE `begin()`.
- A child's `_ready()` runs before its parent's `@onready` variables are set (PlayerFX can't use
  `player.camera` in `_ready`; use the node path).
- CPUParticles3D `direction` is in the emitter's own space (rotated emitters: use local axes).
- Headless tests run frames very fast (tiny delta): wait with timers, not frame counts, when
  something is smoothed over time.
- A new `class_name` (e.g. `MountedGun`) or new audio files: run `godot --headless --import`
  once before the builder/tests, or scripts using the name fail to parse.
- Compatibility renderer: a MultiMesh with `use_custom_data` but without `use_colors` made
  `COLOR` zero in the shader. Use instance colours instead of custom data.
- Shader files use `//` comments – `##` is a GDScript thing and breaks shader compilation.
- GLSL reserved words (e.g. `patch`) can't be variable names in shaders.
- Headless runs use a dummy renderer: shader errors only show up with a real GL window
  (xvfb + `--rendering-driver opengl3`), e.g. `tools/shots_p1.gd`.
- UI Controls catch mouse events by default: HUD elements must use `mouse_filter = IGNORE`.
  Mouse look is read in `PlayerInput._input()` for that reason.
- CSG subtraction faces take the material of the subtracting shape (trench walls = log material).
- Additive-blend effects are invisible against bright snow; use normal alpha blending.
- Terrain and forest are generated at runtime by `@tool` scripts (not saved in the scene).
- `--script` files compile before autoloads exist, so any script that (indirectly) uses an
  autoload name can't be referenced from them. Tests are therefore plain Nodes started by the
  launcher: `godot --headless --path . --script tools/run.gd -- tools/test_m1.gd`.
  The builder uses `_initialize()` and only `load()`s game scripts at runtime.
- Tests that clear a wave by hand (`director._on_wave_cleared(n)`): set `spawner.wave_number = n`
  and wait 2 frames FIRST – otherwise the HUD sees "battle n started" after the day screen opened
  and closes it at once.
- Headless tests must free `Game/PauseMenu` (the mouse can't be captured, so it would pause).
- The navigation map needs a few physics frames after loading before paths are returned.
- After delivering files that change `project.godot` (new autoloads, settings, input actions) or
  add `class_name`s, tell the owner to use **Project → Reload Current Project**: an editor that was
  open keeps the old project settings and shows "Parse error" for scripts using the new names.
- The desktop app may create a `Claude outputs/` folder in the project: it is git-ignored and
  has a `.gdignore`.
- After changing the level geometry, re-bake: select `Navigation` in `levels/test_level.tscn`
  → Bake NavigationMesh (saves `levels/test_level_navmesh.res`).
- `test_artillery.gd` "out in the open: GET INTO THE TRENCH!" is flaky (fails ~1 run in 2, also
  before T3): only 0.3 s after moving the player; a re-run passes.
- `JavaScriptBridge.eval()` in the web export did not return a JavaScript true/false as a
  GDScript bool: comparing the result (`== true`) silently stopped the function (no error in the
  console). Ask for a string instead: `FullscreenNotice._js_yes()` evaluates `(expr) ? 'yes' : 'no'`.
- Playwright: `page.close(run_before_unload=True)` showed no `beforeunload` dialog here; navigating
  away (`page.goto("about:blank")`) after a click does. Software WebGL is slow: give it 30 s.
- `test_t1.gd` "DT bullets hurt the player" can miss once under load (random spread); re-run.
- `test_m1.gd` deep-snow / exit-ramp checks failed once (3 FAILs) under heavy load in the cloud,
  then passed 4× in a row (also without the change being tested) – re-run before suspecting code.
- **Trench line (L1):** many tests teleport the player / soldiers to fixed trench spots
  ((-30, 61), (-10, 61), (10, 61), (50/70/90, 61), bunker front x = -6…6 at z = 64, exits at
  x = ±40 / ±80 at z = 64; L3: at ±40 the communication trenches start, the exit ramps are only at ±80). The line in `TRENCH_XZ` deliberately passes all of them – keep that
  when editing it (`test_l1.gd` checks the rest). The 6 m straight at x = -34…-28 is the
  longest straight the walking-speed test can use; the targets of `test_m2.gd` are shot from x = -10
  because the firing position at x = -23.5 blocks the line from the spawn at x = -30.
- (L2) The bunker now faces the enemy on open ground (no pit); test_w1 rays from the gunner's eye are
  only 2 m long (the ground in front would stop a longer -7° ray). Tests that shoot from / stand at
  x = 0 on the ground (test_m2, test_p2) must stay out of the bunker (x -3…3, z 56.75…62.25).
- (L2) A `CSGPolygon3D` used as a SUBTRACTION did NOT cut in the headless bake (no error, hole just
  missing) – the funnel hole is made of three `CSGBox3D` steps instead.
- A `MultiMesh` built in a headless builder run is saved WITHOUT its instance transforms (the
  dummy renderer has no buffer) – the sandbags would be invisible. Merge meshes into one `ArrayMesh`
  instead (`_bags_mesh()`).
- `build_scenes.gd` also rewrites `scenes/game.tscn`, `player.tscn`, `suomi_viewmodel.tscn` and
  `ui/main_menu.tscn` with real differences from the committed versions (hand edits / newer credits
  text): after a build `git checkout` them – only `levels/` and the new materials should change.
- (L3) The navmesh bake box (`filter_baking_aabb`) is stored in `test_level_navmesh.res`: once that file
  exists the builder reuses it, so changing the box in `build_scenes.gd` alone does nothing – `bake_nav.gd`
  sets it before baking (keep both the same). It now reaches z = 118 (communication trenches), which
  also covers the forest behind the line: ~5300 navmesh vertices (was ~3000).
- (L3) The builder re-saves `resources/difficulty/*.tres` WITHOUT their uids – edit those by hand
  (keep the uid lines) and restore the builder's versions; same for `muzzle_flash.tres`,
  `winter_sky.tres`, `winter_theme.tres` (only noise). `scenes/game.tscn` is hand-edited too (WaveSync
  got `retaking`).
- (L3) Soldiers standing in the trench see over the edge (eyes ~0.2 m above the ground): across the
  flat ground a head is visible far away. That is why HOLD sight is short (30/40 m) – the rear spawns
  would otherwise be shot at from the line.
