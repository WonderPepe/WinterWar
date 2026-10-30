# CLAUDE.md – Winter War: Summa

Notes for Claude (and any other AI assistant) working on this project. Read this first.

## The project
- First-person shooter, Winter War 1939–40, Battle of Summa (Mannerheim Line). Player is a
  Finnish soldier defending a trench against Soviet attacks across open frozen ground.
- Godot **4.7.2**, **GDScript only** (no C#), **Compatibility renderer** (must export to web/HTML5).
- Physics: Jolt. Window 1280×720, stretch aspect "expand".
- Long-term goals: real elevation data for terrain (Copernicus GLO-30 DEM; Summa is in today's
  Russia so Finnish NLS data does not cover it), peer-to-peer co-op (WebRTC) for 2–4 players.

## Working with the owner
- Total beginner with coding and with Godot: explain important concepts briefly, in plain words.
- Before writing code for a milestone: show a short plan + node tree and **wait for approval**.
- Work in milestones; stop after each so he can test in Godot. Give exact test steps.
- After each milestone: make a git commit with a clear message. He pushes with GitHub Desktop
  ("Push origin"). Check `git status` before writing files – never overwrite his own edits.
- If something can't be done well in the web export, say so and suggest an alternative.

## Milestones
- [x] M1 project setup, input map, test level, player movement
- [x] M2 weapons and shooting
- [x] M3 enemy AI (state machine) and wave spawner
- [x] M4 HUD, death/respawn (5 s), main menu (Single Player; greyed-out Host/Join Co-op), pause menu
- [x] M5 web export test and performance check (Settings menu, benchmark, baked CSG)
- [x] P1 graphics: clear freezing day (sky shader, snow shader, log walls, spruce LOD forest, tree line)
- Next: weapons milestone (real Mosin/Suomi models from `assets_source/`, Maxim mounted in the
  bunker, Lahti-Saloranta; CREDITS.md for CC-BY models), then P2 (effects, sound, soldiers),
  real Summa terrain, co-op (WebRTC).

## Multiplayer-ready architecture (mandatory)
- Single player = host with no clients (OfflineMultiplayerPeer, peer id 1). Code everything
  through the high-level multiplayer API; check `multiplayer.is_server()` for authority.
- Host is authority for enemy AI, hit detection, damage, deaths, spawning, game state.
- Player nodes are named after their peer id. `PlayerInput` (authority = owning peer) reads
  devices; `Player` only reads `PlayerInput`. One-shot actions are RPCs to peer 1
  (`request_jump/reload/switch/god_mode`), consumed on the host (`consume_*`).
- Shooting: owner's `WeaponController` decides trigger timing + plays effects locally, then
  `server_fire.rpc_id(1, origin, dir)`; host validates (ammo, fire rate, origin), raycasts,
  calls `take_damage()`, broadcasts `show_impact`, sends `confirm_hit` to the shooter.
- Spawning via `MultiplayerSpawner` (players → `Players`, enemies → `Enemies`); synced state via
  `MultiplayerSynchronizer` (InputSync, StateSync, WeaponSync, WaveSync, DummySync).
- No "the player" singleton: use the `players` group. Autoloads: `NetworkManager` (connection)
  and `Settings` (user preferences + quality presets; signal `changed`). Neither holds game state.
- Death: host sets `Player.is_dead` (synced), emits `died`; `Game` respawns after `respawn_time`
  via `Player.respawn()`, which tells the owner's PlayerInput the new view with `set_look` RPC.
- UI only reads state: `HUD` finds the local player and listens to signals. Pause menu (Esc)
  pauses only in single player (`NetworkManager.is_single_player()`), and opens itself whenever
  the mouse is not captured (browser pointer lock needs a click).

## Conventions
- Folders: `scenes/`, `scripts/` (player, weapons, enemies, world, game), `resources/`
  (materials, weapons, enemies), `levels/`, `ui/`, `autoload/`, `assets/`, `tools/` (helpers,
  ignored by Godot via `.gdignore`).
- Static typing everywhere, `@export` for tunables (with `##` doc comments), signals between
  systems, short commented scripts. Input actions live in Project Settings (physical keys).
- Data-driven: `WeaponData` (`resources/weapons/*.tres`), `EnemyData` (`resources/enemies/*.tres`).
- Damage interface: `take_damage(amount: float, attacker_id: int, hit_position: Vector3,
  hit_normal: Vector3) -> bool` (returns true if the hit killed). Enemies use attacker_id -1.
- Groups: `game`, `players`, `enemies`, `terrain`, `impact_effects`, `wave_spawner`, `player_spawn`,
  `enemy_spawn`, `attack_point`, `deep_snow`, `navigation_source`.
- Physics layers: 1 world, 2 players, 3 enemies, 4 triggers.
- Surface metadata `surface` = `snow` (default) / `wood` / `earthwork` / `cloth`; meta
  `attach_holes` makes bullet holes stick to moving targets.
- Hearing: `get_tree().call_group("enemies", "hear_noise", source, interest, radius)`.
- Map: 300 × 300 m, origin in the centre. Finnish trench at z ≈ 52–70 (floor y = -1.4,
  ground y = 0); enemies come from the south forest (z ≈ -118) towards +z. Forward is -z.

## Web export limits (Compatibility renderer) – decisions already made
- No volumetric fog → depth + height fog. No Decal node → pooled quads (`ImpactEffects`).
- Crouch is **C** (Ctrl also bound, but Ctrl+W closes browser tabs).
- Snow = CPUParticles3D following the local player only. Trees = MultiMesh chunks with
  visibility ranges. One shadowed sun, short shadow distance. Only the local muzzle flash has
  a light. Export without threads. Navigation mesh is pre-baked (no runtime baking).
- CSG trench/bunker should be converted to static meshes before the web export (M5).
- Max 16 enemies alive; enemy senses run ~5×/s; no RVO avoidance.

## Graphics settings & web build
- Quality presets live in `autoload/settings.gd` (`PRESETS`); `scripts/game/quality_applier.gd`
  applies them (groups `sun`, `forest`, `world_environment`, players' snow).
- Tonemapper is **Linear** on purpose: in Compatibility, Filmic looks different when
  `scaling_3d_scale` < 1, so presets would change the colours.
- `display/window/stretch/mode = canvas_items` so UI scales with the browser window.
- Terrain mesh does not cast shadows (it doubled the triangle count for nothing).
- Web export preset "Web" (no threads) → `export/web/` (git-ignored). Export from the command
  line: `godot --headless --path . --export-release "Web" export/web/index.html` (needs the
  4.7.2 export templates). `python3 tools/web_smoke_test.py` checks it in headless Chromium.
- Measured budget (High, after P1): ~185 draw calls (255 max), ~250k triangles/frame, CPU scripts
  1–2 ms + physics 2.5–4 ms with 16 enemies (native). Keep new art within the README's budget table.

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
- Forest: per chunk `Near0/Near1_*` (detailed, no shadow), `Shadow_*` (simple tree, shadows
  only), `Far_*` (simple tree beyond `detail_distance`), `TreeLine` ring (radius 330/520 m).
  Per-tree values go in the MultiMesh **instance colour** (B = snow, A = tint); spruce vertex
  colour R = can hold snow, G = AO, B/A = 1; UV.x = 0 at trunk … 1 at branch tips.
  Tree *look* uses its own RNG so positions (and the baked navmesh) stay unchanged.
- Quality presets also set `tree_detail_distance` (35/50/70 m).

## Gotchas learned
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
- Headless tests must free `Game/PauseMenu` (the mouse can't be captured, so it would pause).
- The navigation map needs a few physics frames after loading before paths are returned.
- After delivering files that change `project.godot` (new autoloads, settings, input actions) or
  add `class_name`s, tell the owner to use **Project → Reload Current Project**: an editor that was
  open keeps the old project settings and shows "Parse error" for scripts using the new names.
- The desktop app may create a `Claude outputs/` folder in the project: it is git-ignored and
  has a `.gdignore`.
- After changing the level geometry, re-bake: select `Navigation` in `levels/test_level.tscn`
  → Bake NavigationMesh (saves `levels/test_level_navmesh.res`).

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
  `shots_p1.gd <prefix> [views]` (graphics screenshots, needs xvfb),
  `make_textures.py` (regenerates `assets/textures/`),
  `soak_m3.gd`: automated checks. `shots*.gd`: screenshots (need a GL window).
  Run all tests before every commit.
