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
- [ ] M4 HUD, death/respawn (5 s), main menu (Single Player; greyed-out Host/Join Co-op)
- [ ] M5 web export test and performance check

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
- No "the player" singleton: use the `players` group. Only autoload: `NetworkManager`.

## Conventions
- Folders: `scenes/`, `scripts/` (player, weapons, enemies, world, game), `resources/`
  (materials, weapons, enemies), `levels/`, `ui/`, `autoload/`, `assets/`, `tools/` (helpers,
  ignored by Godot via `.gdignore`).
- Static typing everywhere, `@export` for tunables (with `##` doc comments), signals between
  systems, short commented scripts. Input actions live in Project Settings (physical keys).
- Data-driven: `WeaponData` (`resources/weapons/*.tres`), `EnemyData` (`resources/enemies/*.tres`).
- Damage interface: `take_damage(amount: float, attacker_id: int, hit_position: Vector3,
  hit_normal: Vector3) -> bool` (returns true if the hit killed). Enemies use attacker_id -1.
- Groups: `players`, `enemies`, `terrain`, `impact_effects`, `wave_spawner`, `player_spawn`,
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

## Gotchas learned
- UI Controls catch mouse events by default: HUD elements must use `mouse_filter = IGNORE`.
  Mouse look is read in `PlayerInput._input()` for that reason.
- CSG subtraction faces take the material of the subtracting shape (trench walls = log material).
- Additive-blend effects are invisible against bright snow; use normal alpha blending.
- Terrain and forest are generated at runtime by `@tool` scripts (not saved in the scene).
- After changing the level geometry, re-bake: select `Navigation` in `levels/test_level.tscn`
  → Bake NavigationMesh (saves `levels/test_level_navmesh.res`).

## Helper tools (`tools/`, not part of the game)
Run with a Godot 4.7.2 binary from the project folder, e.g.
`godot --headless --path . --script tools/test_m3.gd`.
- `setup_project.gd` writes project settings + input map. `build_scenes.gd` generated the
  scenes/materials/weapon & enemy data. **It overwrites scenes** – once the owner edits scenes in the
  editor, edit the .tscn files (or the editor) instead of regenerating, unless he agrees.
- `bake_nav.gd` bakes the navmesh; `make_sounds.py` synthesizes the placeholder sounds.
- `test_m1.gd`, `test_m2.gd`, `test_m3.gd`, `test_mouse.gd` (needs a real window, e.g. xvfb),
  `soak_m3.gd`: automated checks. `shots*.gd`: screenshots (need a GL window).
  Run all tests before every commit.
