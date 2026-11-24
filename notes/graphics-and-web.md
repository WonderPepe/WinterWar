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
- **Loading the battle in the web build (P4, 2026-11-16).** Without threads,
  `ResourceLoader.load_threaded_request()` does the whole load at once on the page's only thread
  – and was also very slow there: measured in the live v0.9.0 on a real GPU, ONE frozen stretch of
  10.3 s after "Single Player" (browsers then say "Page unresponsive"); in cloud Chromium
  (software GL) 19.9 s. Now `LoadingScreen.piecewise_loading()` (web + no "threads" feature)
  makes `_run()` load the battle's parts one by one: `LoadingScreen.dependency_order()` walks
  `ResourceLoader.get_dependencies()` (deepest first, the scene last – 125 files), `load()`s them
  and draws a frame every `LOAD_SLICE` (0.04 s) of work; then `load(game.tscn)` takes ~70 ms
  because every part is cached. Cloud Chromium: the read step 20 s → ~1 s, progress now real.
  Desktop keeps the threaded loading. What is still left: the FIRST frame of the battle (behind
  the loading screen) compiles every shader at once – in software GL that is ~15 s, on a real
  GPU much less; not measured on the owner's PC yet. If it is still too long, the next step is to
  show the scene / warm-up effects in groups over several frames.
- Click prompt (P4, owner): when the battle is ready the photo and briefing fade away
  (`_hide_briefing()`, `BRIEFING_FADE` 0.6 s, layout kept so nothing jumps); march, ALARM line and
  "CLICK TO START THE BATTLE" stay over the dimmed battlefield.
- CSG trench/bunker should be converted to static meshes before the web export (M5).
- Max 24 enemies alive (V10c; was 16); enemy senses run ~5×/s with a random start; no RVO avoidance.
  Soldiers beyond 60 m are posed every 2nd frame, beyond 120 m every 3rd (`SoldierVisual.far_pose_distance`).
  Bodies are baked into batches (V10c): 24 bodies ≈ 5 draw calls.

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

## Motion (V10a): spruce sway and cloud drift – how it is built
- Wind per battle: `WeatherData.wind` (0 = still … 1 = a strong wind … 2 = a storm; table `LOOKS` in
  `tools/make_weather.gd`, values and the owner's decision in `milestones.md`) and the constant
  `WeatherData.WIND_DIRECTION` (world x, z; the same way `apply_quality()` pushes the falling
  snow). `DuskLight._apply()` → `ForestScatter.set_wind(strength, direction)` → uniforms
  `wind_strength` / `wind_direction` on all four tree materials (near / far × branches / trunk).
  A look that changes during the battle blends the wind too (`mixed()` mixes every float);
  `build()` gives rebuilt materials the wind again.
- Sway is in `spruce.gdshader` `vertex()` (TIME, no script work): the whole tree leans downwind,
  `sway_top_m` (0.11 m at strength 1, tree scale 1) × (height / `sway_height`)² × (0.5 + gust),
  gust = three sine waves (a gust wave travelling downwind, the tree's own swing from a hash of
  its position, a slow swell). Branch tips bob `sway_tip_m` (3.5 cm) × UV.x², only near the
  camera (fades out before the LOD change). The foot never moves (trunk collision is static).
- Things that must stay so: `local_pos = VERTEX` is taken BEFORE the wind (the snow pattern is
  mapped by it – otherwise the snow swims over the branches); the lean depends only on the tree's
  place and the height on the tree, so detailed tree, simple tree, trunk and shadow tree move
  together through the LOD cross-fade; the wind direction is turned into the tree's own space
  (`vec4(dir) * MODEL_MATRIX`), because every tree is rotated and scaled.
- S1: the sky noise's `hash()` takes whole-number cells (`ivec2`) and mixes them with uint math
  (exact on every GPU / browser path). Never go back to `fract(p * big numbers)` hashes: on Chrome's
  default path (Windows / AMD) neighbouring cells disagreed and the sky showed straight seams.
- Clouds: `winter_sky.gdshader` uniform `cloud_offset` (the cloud pattern is looked up at
  `uv - cloud_offset`). `DuskLight._drift_clouds()` adds `WIND_DIRECTION × cloud_drift (0.006) ×
  (0.4 + wind)` per second and sends it to the sky `cloud_updates_per_second` (8) times a second:
  steps of well under a pixel. At 1280 × 720 the clouds move about 2.5 px/s on a calm day. Fully
  overcast looks show no drift. The clouds stop while the game is paused (the trees don't).
- Why not TIME in the sky shader – measured under xvfb (software GL, so only the ratios count,
  minimal scene, 1280 × 720): no change 24.5 ms/frame; `cloud_offset` set EVERY frame +1.6 ms;
  TIME in the shader +5.7 ms (Godot then re-lights the sky every frame as a "realtime" sky).
  Every change of a sky uniform re-lights the ambient light (arrives 4–8 frames later). Also
  checked: while the clouds move (every frame … every 15th) a colour change of the sky still
  arrives, and the ambient light stays steady (± 0.4 %) – so the battle looks that change
  (8, 10) keep working. If the browser Benchmark ever shows a cost: lower
  `cloud_updates_per_second` (4 still looks smooth) or set `cloud_drift` 0.
- The engine's shader TIME starts again from 0 once an hour (project setting time rollover):
  the trees twitch for one frame then. TIME also runs in the pause menu.
- Tests: `test_v10a.gd` (headless: wind per battle, materials, blend, rebuild, cloud speed and
  update rate, no TIME in the sky); shader mistakes only show with a GL window:
  `shots_v10a.gd [battle] [frames] [wind]` (a row of frames of trees + the sky 60 s apart).

## Graphics settings & web build
- Quality presets live in `autoload/settings.gd` (`PRESETS`); `scripts/game/quality_applier.gd`
  applies them (groups `sun`, `forest`, `world_environment`, players' snow).
- Tonemapper is **Linear** on purpose: in Compatibility, Filmic looks different when
  `scaling_3d_scale` < 1, so presets would change the colours.
- `display/window/stretch/mode = canvas_items` so UI scales with the browser window.
- Terrain mesh does not cast shadows (it doubled the triangle count for nothing).
- Ground tiles (TR1, review item P3): the drawn ground is 4 × 4 tiles (`TerrainGenerator.tiles_per_side`,
  node `GroundTiles/Tile_x_z`) so tiles outside the view are skipped. **No LOD on the ground, ever**
  (owner): every tile has every 1 m point at the collision height, so far soldiers never look sunk in
  or floating. Each cell is split b→c like Jolt's height field, so even between the points the drawn
  surface is the collision surface. More tiles = fewer triangles but more draw calls (measurements in
  milestones.md, TR1). Bench: `tools/bench_tr1.gd [counts]`.
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

## Sandbags (V4) – how they are built
- One bag = `_bag_mesh()` in `build_scenes.gd` (a 1 × 1 × 1 pillow; `_bag_transform()` squashes it
  to 52 × 21 × 31 cm). `HALF` is its half size: above 0.5 means the bag is bigger than its place and
  overlaps its neighbours – that overlap is what closes the wall. Don't make x much bigger: the
  jamb bags would bulge into the loophole (`test_v4.gd` checks the hole stays free).
- All bags of a wall are merged by `_bags_mesh()` (a MultiMesh is lost in a headless build, see
  gotchas). The scene file holds the mesh as text: `levels/test_level.tscn` grew by ~225 kB.
- Material: `_burlap_mat()` – a `StandardMaterial3D` with `uv1_triplanar` (texture laid on by
  position from three sides, 25 cm per repeat, `uv1_scale` 4), so the bags need no UVs or
  tangents. The texture is light grey (average 0.757) and `albedo_color` = wanted colour / 0.757.
- `SandbagCore`: dark boxes inside the wall so a crack between bags never shows daylight. If the
  wall constants (`POST_WALL_*`, `POST_HOLE_*`) change, the filling follows (built from them);
  `test_v4.gd` has its own copy of the numbers – change them there too.

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
