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
