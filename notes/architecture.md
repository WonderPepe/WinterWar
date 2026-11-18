# Multiplayer architecture and code conventions

Moved from CLAUDE.md (2026-11-01). Read when working on this area; keep it up to date.

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

## Co-op connection (NET1)
- `NetworkManager`: `host_coop(port)` / `join_coop(address, port)` make an `ENetMultiplayerPeer`
  (port 7777, `MAX_PLAYERS` 4); `coop_available()` is false in the browser. Lobby list
  `lobby_peers` (host 1 first), kept by the host and sent with `_lobby_list` RPC; signals
  `lobby_changed`, `joined`, `connection_lost(text)`, `all_loaded`.
- `begin_battle(test_wave)` (host): `refuse_new_connections`, then `_load_battle` RPC (call_local)
  → everyone sets `coop_battle`, `RunSave.active = false`, `MatchDirector.test_start_wave`, and
  `LoadingScreen.go(game)`.
- **Load gate** (`Game._start_coop`): a client's Game calls `report_loaded()` from `_ready`; the
  host pauses the tree (so no spawns / syncs go to a computer still loading), and on `all_loaded`
  spawns one player per battle peer and unpauses. `ShaderWarmup` waits (up to ~2 min in co-op) for
  the local player; the loading screen shows "Waiting for the other soldiers...".
- `leave_game()` disables the current scene before closing the connection: an offline peer counts
  as the server, so host-only code would otherwise run on a client's battle for one frame.
- Godot prints "Co-op: ..." lines (joined / everyone loaded / left) to the Output panel.

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
  `enemy_spawn`, `attack_point`, `deep_snow`, `navigation_source`, `match_director`, `ammo_crates`,
  `trench_entry`, `day_screen`, `tanks`, `tank_route`, `tank_spawner`, `tank_wrecks`, `molotovs`,
  `molotov_crates`, `fire_post`, `body_keeper`, `tank_tracks`, `grenades` (GR1).
- Physics layers: 1 world, 2 players, 3 enemies, 4 triggers, 5 armour (T5: tanks and wrecks are on
  3 AND 5; enemy rays use `Tank.SIGHT_MASK` world + armour / `Tank.BULLET_MASK` world + players +
  armour – never layer 3, or soldiers would shoot and hide each other).
- Surface metadata `surface` = `snow` (default) / `wood` / `earthwork` / `cloth`; meta
  `attach_holes` makes bullet holes stick to moving targets.
- Hearing: `get_tree().call_group("enemies", "hear_noise", source, interest, radius)`.
- Map: 300 × 300 m, origin in the centre. Finnish trench at z ≈ 52–70 (floor y = -1.4,
  ground y = 0; the centre line is `TRENCH_XZ` in `tools/build_scenes.gd`, z ≈ 58–64, see L1 in milestones.md); enemies come from the south forest (z ≈ -118) towards +z. Forward is -z.
  L3: two communication trenches zigzag back from the line at x = -40 / +40 to z ≈ 107 (ramp out to
  z ≈ 113), `COMM_XZ` (west; east = mirror) and `COMM_AREAS` in the builder; the same rects are
  `TerrainGenerator.extra_trench_areas` (ground lowered to the floor), `ArtilleryBarrage.COMM_TRENCH_AREAS`
  (shelter, no shells/bombs land there) and keep_clear rects in `ForestScatter` – keep all four in step.
  Groups: `rear_spawn` (8 Marker3D, meta `side` west/east, respawns), `retake_point` (10 spots in the
  west half for battle 6's occupiers).
