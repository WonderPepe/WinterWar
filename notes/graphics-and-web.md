# Web export, graphics settings, P1 graphics

Moved from CLAUDE.md (2026-11-01). Read when working on this area; keep it up to date.

## Web export limits (Compatibility renderer) – decisions already made
- No volumetric fog → depth + height fog. No Decal node → pooled quads (`ImpactEffects`).
- Crouch is **C** (Ctrl also bound, but Ctrl+W closes browser tabs).
- Ctrl+W guard (2026-11-02, owner: "warning + true blocking in fullscreen"). A page can't cancel
  Ctrl+W / Ctrl+T / Ctrl+N in a normal window, so:
  - `export_presets.cfg` `html/head_include` (one line, single quotes only – the value sits in
    double quotes) adds a `beforeunload` handler that asks "Leave site?" while
    `window.summaLeaveWarning` is true. `Game.set_leave_warning()` (static) sets it: on in
    `Game._ready()`, off in `Game._exit_tree()` and when `MatchDirector.result` ends the match.
    Browsers only ask after the player has clicked/typed on the page (always true in a battle)
    and choose the dialog text themselves.
  - The same script calls `navigator.keyboard.lock()` (all keys) on `fullscreenchange` when the
    page is fullscreen (Keyboard Lock: Chrome / Edge only; Firefox/Safari: Esc works as usual)
    and `unlock()` when it leaves. Locked: Ctrl+W goes to the game, a short Esc goes to the game
    (pause menu), the browser leaves fullscreen only when Esc is HELD.
  - `scripts/ui/fullscreen_notice.gd` (CanvasLayer 100, made by the Settings autoload, polls
    `document.fullscreenElement` 4×/s): entering fullscreen where Keyboard Lock exists shows
    "FULLSCREEN / Hold [Esc] down to leave fullscreen. / (A short press opens the pause menu.)"
    for 6 s; leaving fullscreen unticks `Settings.fullscreen`. On the web a saved
    "fullscreen on" is ignored at start-up (browsers need a click for fullscreen).
  - Test: `python3 tools/web_guard_test.py` after the web export (menu: no warning; battle:
    warning on and `beforeunload` fires on leaving; fullscreen → notice). Real Ctrl+W can't be
    pressed from Playwright – try it by hand in Chrome.
- Snow = CPUParticles3D following the local player only. Trees = MultiMesh chunks with
  visibility ranges. One shadowed sun, short shadow distance. Only the local muzzle flash has
  a light (plus 2 pooled tiny glows for enemy flashes in the dark, V1; blasts/tank/Molotov have their own). Export without threads. Navigation mesh is pre-baked (no runtime baking).
- CSG trench/bunker should be converted to static meshes before the web export (M5).
- Max 16 enemies alive; enemy senses run ~5×/s; no RVO avoidance.

## Weather and time of day (B3) – how it is built
- Every battle has its own look: `WeatherData` (`scripts/game/weather_data.gd`) in
  `resources/weather/battle_01…10.tres`, written by `tools/make_weather.gd` (the table `LOOKS` is
  the place to tune; run `godot --headless --path . --script tools/make_weather.gd`; the builder
  calls it too). Anything not listed = the old clear freezing day (battle 3 is exactly that).
  Fields: sun/moon (the level's one DirectionalLight3D: pitch, yaw, colour, energy), ambient, sky
  colours + `cloud_cover` + `sun_brightness` (0 = no disc) + `star_strength` (new in winter_sky),
  fog (`fog_scale` × the quality preset density: ~5 → 120 m view, ~8 → 80 m, ~11 → 60 m), snow
  (`snowfall` × preset amount, `snow_wind` sideways gravity, `drift_scale`), `wind_db` (Ambience).
- Owner's choices: battles 1 and 2 (06:45, 05:30) are lit by the MOON (dim bluish light, stars in 1,
  clouded moon + heavy snow in 2) – readable, not truly dark; weather changes the LOOK only, enemy
  vision/ranges are unchanged (fog does not hide soldiers from the AI – maybe a later step);
  battle 8 starts in dense fog that clears (`end_look`, 75 s); battle 10 is dusk WITHOUT snowfall,
  orange → violet and dark over 200 s. Times are not shown in the game (owner), only used as mood.
  L3 (owner 2026-11-11): battle 6 (the counterattack to retake the trench) is in the DARK of the
  morning – overcast, no moon or stars, light snow, a little darker than battle 2 (measured mean
  brightness of the weather shot: battle 2 ≈ 95, battle 6 ≈ 81) but less fog, enemy sight 90 m.
  The briefing's weather line ("Overcast") is the owner's text and was left as it is.
- `DuskLight` (class and node name kept): battle = `waves_cleared + 1`; a new battle's look is set
  when the day screen is black (or after `wait_for_black` 6 s; test mode / joining late: at once).
  `battle_clock` runs while `WaveSpawner.wave_number >= battle`; with an `end_look` the shown look is
  `base.mixed(end_look, clock / change_seconds)`, re-applied every `step` 0.01 (re-lighting the sky
  is the costly part). `apply_quality()` (also called by QualityApplier, Settings.changed and each
  new Player) sets fog density and the players' snow amount / wind / drift = preset × weather; the
  flake amount is only touched when it changes (that restarts the particles).
- Fog limits the ENEMY's sight (owner, B3b): `WeatherData.visibility_m` (1000+ = no limit) →
  `DuskLight._apply` sets the static `Enemy.visibility_limit` (INF = none; reset in
  `DuskLight._exit_tree`, like the other statics). Soldiers (`_find_visible_player`) and tanks
  (`Tank._can_see`) see `min(own range, limit)`; the spot-time scale and the trench fight (< 60 m)
  are unchanged; gunshots still make noise (`hear_noise`). Values: battle 1 150 m, 2 80, 5 110, 6 90 (dark),
  7 60, 8 60 → none as the fog clears (blends with the look), 9 120, the rest none. MG teams only
  fire at a Finn they can see, so in dense fog they stay quiet until their final position.
  Possible tuning: battle 7 may now be easier than 6 and 8.
- Heavy snowfall is ×1.2 of the preset (battle 2): 1080 flakes on High (was 900); Low 300.
- Tests: `test_b3.gd`; screenshots of all ten looks: `shots_weather.gd`.

## Graphics settings & web build
- Quality presets live in `autoload/settings.gd` (`PRESETS`); `scripts/game/quality_applier.gd`
  applies them (groups `sun`, `forest`, `world_environment`, players' snow).
- Tonemapper is **Linear** on purpose: in Compatibility, Filmic looks different when
  `scaling_3d_scale` < 1, so presets would change the colours.
- `display/window/stretch/mode = canvas_items` so UI scales with the browser window.
- Terrain mesh does not cast shadows (it doubled the triangle count for nothing).
- 3D resolution cap (P3, review item P1): `Settings.resolution` = `Resolution.AUTO` (default) or
  `FULL`, saved as `graphics/resolution`. Each preset has `max_lines` (720 / 900 / 1080). Auto:
  3D picture height = min(window height × `render_scale`, `max_lines`); `Settings.scale_for()`
  (static, pure maths) → `root.scaling_3d_scale`, never below Godot's 0.25. Re-applied on
  `root.size_changed` (resize, fullscreen, browser canvas). Use `Settings.render_scale()` /
  `render_size()` for the real values, not `preset().render_scale`. `render_size_changed` updates
  the Settings menu hint ("3D picture: 1920 × 1080"); the benchmark prints the real size. The
  HUD and menus are 2D and stay at full window resolution. Test: `tools/test_p3.gd`.
- Web export preset "Web" (no threads) → `export/web/` (git-ignored). Export from the command
  line: `godot --headless --path . --export-release "Web" export/web/index.html` (needs the
  4.7.2 export templates). `python3 tools/web_smoke_test.py` checks it in headless Chromium.
- Measured budget (High, after P1): ~190 draw calls (260 max), ~255k triangles/frame, CPU scripts
  1–2 ms + physics 2.5–4 ms with 16 enemies (native). Keep new art within the README's budget table.

## Soft snow on the earthworks (V2) – how it is built
- `tools/earthwork_snow.gd` (helper of the builder, static functions) makes the meshes;
  `build_scenes.gd` (`_build_earthwork_snow`, `_heap_mesh`) saves them in `levels/baked/`
  (`snow_*_mesh.res`, `heap_*_mesh.res`) and links them in `levels/test_level.tscn`. Re-run the
  builder after changing the trench line – the snow follows it. No CSG or navmesh re-bake is needed:
  nothing here has collision.
- The trench outline is read from the CSG source: every box SUBTRACTED over the full slab height
  (size.y ≥ 3.5) is joined with `Geometry2D.merge_polygons` → polygons → edges cut into ≤ 0.6 m
  pieces. A cross-section (7 points for the lip, 4 for the drift) is swept along the outline;
  height and width vary with noise (fixed seeds, so the result is the same every build).
- Places that must stay clear: `no_lip` rectangles (the sandbag walls – their loopholes start at
  the ground – and the bunker); on the ramps the lips and drifts fade out and `RampSnow` takes over.
- Bunker sizes are written out in `bunker_mesh()` (roof 6.8 × 6.3 m, old snow slab top 1.745 m,
  walls 6 × 5.5 m). The old flat `RoofSnow` CSG box is still there (hidden inside the cap, part of
  the baked collision). If the bunker CSG changes, change these numbers too (`test_v2.gd` checks
  that the cap covers the slab and that nothing lies in front of the Maxim's hole).
- Vertex colour green < 1 = trampled / earthy (same meaning as on the terrain). Lips, drifts and
  ramp snow cast no shadows; the bunker snow and the heaps do.
- Smooth normals are computed in the helper (`Builder.add_grid`, `_smooth`); the outer edge of
  lips/drifts has its normal forced straight up and sits 2 cm under the surface, so it melts into
  the ground without a visible seam.

## Graphics (P1) – how it is built
- Look: stylized-realistic, clear freezing day, low warm sun in the SSW (in front-left of the
  trench), blue sky ambient → blue shadows. Linear tonemap, exposure 0.85, sun energy 1.25.
- Shaders in `resources/shaders/`; materials (`resources/materials/*.tres`) are written by
  `build_scenes.gd` (`_shader_mat`). Textures in `assets/textures/` come from
  `tools/make_textures.py` (FFT noise → tileable). Import settings: VRAM compressed + mipmaps
  (`snow_mask.png` lossless: it holds data, sparkle dots), normal-map detection disabled –
  shaders decode normals themselves (`xy * 2 - 1`).
- Snow/log shaders map textures by **world position** (CSG UVs are stretched).
- Terrain vertex colour for the snow shader: R < 1 = ice (bog), G < 1 = trampled snow
  (trench floor). Meshes without vertex colours read as white = plain snow.
- Forest LOD is decided **per tree in the spruce shader** (dithered cross-fade over
  `fade_band` m), not per chunk – whole 50 m chunks switching at once looked like random
  popping. `ForestScatter._process` passes the camera position (`lod_camera`) to its own copies
  of the tree materials (near = `lod_mode` 0, far = 1); shadow pass can't use the shader's camera.
  Chunk visibility ranges are only coarse culling, widened by the chunk radius.
  Per chunk: `Near0_*`/`Near1_*` (detailed; neighbouring chunks alternate the two shapes, one
  draw call each), `Shadow_*` (simple tree, shadows only, near range), `Far_*` (simple tree, no
  shadows – sun shadows end before it starts). `TreeLine` ring (radius 330/520 m).
  Trunk material is the same shader with `trunk = true` (bark texture).
  Per-tree values go in the MultiMesh **instance colour** (B = snow, A = tint); spruce vertex
  colour R = can hold snow, G = AO, B/A = 1; UV.x = 0 at trunk … 1 at branch tips.
  Tree *look* uses its own RNG so positions (and the baked navmesh) stay unchanged.
- Quality presets also set `tree_detail_distance` (35/50/70 m).
- Benchmark turns V-Sync off on desktop (else FPS is capped at the monitor rate). Godot's
  TIME_PROCESS includes CPU-side rendering, so the benchmark shows physics time only.
