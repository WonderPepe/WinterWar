# T-26 tank and Molotov cocktail (T1, T2, T3)

Moved from CLAUDE.md (2026-11-01). Read when working on this area; keep it up to date.

## Tank (T1) – how it is built
- `Tank` (`scripts/enemies/tank.gd`, scene `scenes/enemies/soviet_tank.tscn` from the builder's
  `_build_tank()`): AnimatableBody3D, layer 3 (bullets hit it, players bump into it; soldiers
  pass through – their mask has no layer 3), meta `surface = "metal"`, `sync_to_physics = false`
  (with Jolt, `true` kept the body at 0,0,0). Group `tanks` – NOT `enemies` (it is no soldier:
  the wave counter, suppression, hearing, officers ignore it). `MatchDirector.end_match` freezes tanks.
- Model: Sketchfab "Т-26 SD" (MMD_SonicNewYear, CC-BY 4.0, in CREDITS.md) →
  `assets/models/vehicles/t26/` by `tools/import_weapons.py` (zip `-26_sd.zip`, the Cyrillic T is
  lost in the file name; vehicles drop their specular maps). Metres, front = -z, 8.7k tris,
  7 materials. Parts: `vertices` hull, `vertices_001` turret, `gun_08Shape` gun, tracks, chassis.
  `_split_model()` makes turret + gun `top_level` and copies `TurretPivot` / `GunPivot` every
  frame (offsets taken at rest). Builder constants `T26_TURRET` (ring centre), `T26_TRUNNION`,
  `T26_MUZZLE`; `DtMuzzle` right of the gun, `Eye` above the turret (line-of-sight checks).
- Driving (host): `route` (Path3D, group `tank_route`, `Level/TankRoutes/TankRoute1..3`, builder
  `TANK_ROUTES` → `_smooth_curve()` Catmull-Rom handles) – `_distance` along the baked curve,
  hull yaw turns towards a point `look_ahead_m` ahead, height/pitch/roll from
  `TerrainGenerator.get_height()` under 4 track points (smoothed). Routes end at z = 46 (nose at
  48.3; trench front edge ≈ 57) and avoid the lone trees (test_t1 rebuilds their positions with
  ForestScatter's random numbers). Synced (StateSync): position, rotation, `turret_yaw`,
  `gun_pitch` (ALWAYS), `drive_speed`, `state` (ON_CHANGE). State enum: new values at the END.
- States: ADVANCE (2 m/s) / SUPPRESS (player seen: 1.2 m/s + DT) / HALT_FIRE (every 15–25 s if a
  target ≥ 20 m: brake, aim `gun_aim_time` 1.2 s, one HE shell, 1.5 s, drive on; gives up after
  8 s) / AT_TRENCH (end of route: parked, DT + a shell every 6–10 s, turret sweeps ±55° when
  nobody is seen) / DESTROYED (`destroy()`: `_become_wreck()` on every computer – engine off,
  dark `material_overlay`, `WreckSmoke` particles, group `tank_wrecks`; it stays on the field).
- Senses 4×/s: players in `vision_range_m` 260 with a clear line (world layer) from `Eye` to head
  or chest, noticed after `spot_time` 1.5 s (×2 crouching, ×0.5 once fighting), forgotten after
  4 s out of sight. Gun depression −10° (real T-26 ≈ −6°; needed to reach into the trench from the
  edge). A crouching player in the trench is out of sight; standing up he is seen.
- DT: bursts 5–12 at 0.1 s, 63-round pan, 5 s reload, fires when the turret is within 3° of the
  target; spread like the soldiers (× `Enemy.spread_multiplier`, wider while driving), damage
  25 × `Enemy.damage_multiplier`, `bullet_passed` cracks. RPC `show_dt_effects` (unreliable).
- 45 mm HE: ray (world + players) with 0.5° spread; burst damages players within 6 m (dead within
  1.5 m) whom the blast can reach (clear line from the burst – a trench wall shields you).
  RPCs `show_gun_fire` (flash, big smoke, shake) and `show_shell_burst` (uses the new
  `ArtilleryBarrage.show_explosion(pos, strength)` = explode's visuals without the barrage
  bookkeeping; outside a barrage its scorch fades after `scorch_fade_time`).
- Bullets on the armour: `WeaponController.resolve_shot` skips damage + hit marker for anything
  with `deflects_bullets()`; `ImpactEffects` has a "metal" spray (sparks; also in ShaderWarmup)
  and plays a `ricochet…` recording from `assets/audio/recorded/` if there is one (none yet).
- Sounds (`assets/audio/tank/`, made by `tools/make_tank_sounds.py` from `assets_source/`, all
  CC-BY 4.0 and credited): `engine_a.ogg` (joniheinonen 161894) / `engine_b.ogg` (greatmganga
  329800, a real T-26) – seamless loops (`loop=true` in the .import), one per tank by name,
  pitch/volume follow `drive_speed`; `dt_shot.ogg` = one round of soundscalpel.com 110622, played
  per round; `gun_bang.ogg` = the loudest bang of the barrage recording (also the shell burst,
  pitched 0.8). `RecordedSounds` prefixes `tank_gun` / `tank_dt` override them.
- `TankSpawner` (Game/TankSpawner, group `tank_spawner`, `scripts/enemies/tank_spawner.gd`):
  `spawn_tank(route_index = -1)`, `destroy_nearest(pos)`, `get_routes()`. Tanks go under
  `Game/Tanks`, replicated by `Game/TankNodeSpawner` (MultiplayerSpawner). Debug keys F9/F10
  (`debug_spawn_tank` / `debug_destroy_tank`, only `OS.has_feature("editor")`) →
  `PlayerInput.request_debug_tank` RPC to the host.
- `tools/test_t1.gd`, `tools/shots_t1.gd` (approach, side, front, trench edge, wreck; xvfb).

## Molotov cocktail (T2) – how it is built
- `MolotovHandler` (`scripts/player/molotov_handler.gd`, Player child `Molotov` + `MolotovSync`:
  `count`, `phase` ON_CHANGE). Phases NONE / HELD / IGNITING / LIT / THROWING (new ones at the
  END). Host rules in `_physics_process`: `PlayerInput.request_molotov` (G) / `request_throw`
  (left mouse while `is_selected()`; PlayerInput sends it) → `consume_molotov/consume_throw`;
  right mouse = the synced `aim_held` (lighting needs a FRESH press: `_rmb_released`, so holding it
  through a throw doesn't light the next bottle). `ignite_time` 1 s, `warn_time` 5, `danger_time` 8
  (then `hand_burn_damage` per 0.5 s and `drop_chance` + `drop_chance_growth`·(t−8) → `_drop()`).
  Throw: from the camera, `throw_speed` 11 / `aimed_throw_speed` 16 m/s + `throw_lift` 2.5 up
  (aimed ≈ 22 m on flat ground). Dead with a lit bottle → it drops. `Player.respawn` → `reset()`
  (no bottles). Crates: `MolotovCrate` (`scripts/world/molotov_crate.gd`, group `molotov_crates`,
  `give()` → `refill()` = `max_carry` 2, `notify_picked_up` → HUD message). Player F picks the
  nearer of ammo crate / Molotov box; mounting the Maxim / bandaging need the bottle put away.
- WeaponController with a bottle selected: gun hidden (`holder`), no aiming / firing (and the gun
  waits for the fire button to be let go – `_fire_blocked`), 1/2 put an UNLIT bottle away
  (`can_put_away()`), reload ignored, `get_hand_grips()` → the handler's GripR / GripL; the gun
  plays its raise when the bottle is gone (`_had_bottle`).
- Hand visuals (local player only, built in code under the camera: `MolotovHand`): bottle
  (`MolotovManager.make_bottle()`), rag flame + match flame (`make_flames`, `local_coords` so they
  don't smear when turning), a small OmniLight (local only, like the muzzle flash). Poses in camera
  space per phase (held, lighting = left hand with the match at the rag, aimed = cocked back,
  throw swing); flame size grows after `warn_time` / `danger_time`.
- `MolotovManager` (Game/Molotovs, group `molotovs`): host `throw(origin, velocity, thrower)`
  steps a ballistic arc with rays (mask world+players+enemies, thrower excluded) each physics
  frame; RPCs `flight_started` (every computer draws the same arc, tumbling bottle pool of 6) and
  `shatter(id, pos, normal, hit, tank_path)` (glass burst, fire pool of 8 – on a tank it is
  re-parented to the tank). Hit = GROUND / TANK_ARMOUR / TANK_ENGINE (`Tank.molotov_hit(local)`).
  Ground fires (host list) burn `ground_burn_time` 6 s, radius 1.6 m: every 0.5 s 8 damage to
  players, 25 to soldiers (kill counts for the thrower). `drop_at(pos)` = a bottle at the feet.
  `make_flames()` / `make_black_smoke()` are static (tank engine fire reuses them; web_fallback).
- Tank T2: `State.BURNING` (end of enum). `engine_deck` AABB (model space, rear deck behind the
  turret) → `ignite()`: stops, no firing, `_start_engine_fire()` on every computer (flames over the
  deck, black smoke, flickering OmniLight – the tank's only light), crew bail out 2–4 s later
  (`crew_count` 3, 0.5–1 s apart, rifleman scenes from `TankSpawner.crew_scene` under
  `Game/Enemies`; they do NOT count for the wave) → `Enemy.panic(6–10 s, 35–50 m back south)`
  (runs, never fights or goes prone meanwhile, then normal from its nearest attack point);
  `burn_time` 20 s → `destroy()` (fire removed, wreck smoke). Other hits: `_blind_until` 4 s (no
  DT, no main gun).
- Sounds (`RecordedSounds` prefixes, files in `assets/audio/recorded/`, made by
  `tools/make_molotov_sounds.py` from the owner's downloads in `assets_source/`):
  `molotov_break.ogg` (Freesound 74899 Benboncan; glass + whoosh, 4.5 s), `molotov_ignite.ogg`
  (379108 AdamsArchive; plays when lighting starts, stopped if cancelled; local player only),
  `molotov_throw.ogg` (683101 florianreichelt, CC0), `fire_loop.ogg` (564621 Nox_Sound, CC0;
  `loop=true` in its .import; ground fires, burning tank, rag in the hand at −8 dB). All in
  CREDITS.md (owner confirmed: 74899 "Molotov.wav" CC-BY 4.0, 379108 "match.wav" CC-BY 3.0).
- `tools/test_t2.gd`, `tools/shots_t2.gd` (box, held, lighting, aimed, flight, burning tank,
  crew, ground fire). `check_web_pack.gd` T2 checks.

## Tanks in the battles (T3) – how it is built
- `WaveData.tanks` (builder `WAVE_LISTS` 5th value; owner: 0,0,0,1,1,1,1,1,2,2 on all
  difficulties). `WaveSpawner._start_wave` queues spawn times `first_tank_delay` 12 s +
  i × `tank_interval` 18 s on its own `_wave_clock` (runs while not WAITING); `_send_tanks()` →
  `TankSpawner.spawn_wave_tank()`. WaveSync syncs `wave_tanks` (HUD banner "· 1 tank").
- Wave clear rule (owner): FIGHTING ends only when `alive_count <= 0 and tanks_in_fight() == 0`
  (= queued tanks + `TankSpawner.get_living_tanks()`, i.e. not `Tank.is_knocked_out()` –
  BURNING counts as stopped). Bailed-out crew never count.
- Route: `TankSpawner._pick_route()` = a random route no living tank uses (2 tanks → 2 routes).
  Wave tanks get `Tank.forest_approach_m` = `TankSpawner.forest_approach_m` 40: `_distance` starts
  at −40; `_route_point(d < 0)` = route start + (0, 0, d) (straight south of it, z ≈ −146).
  `is_in_forest()` → no senses (trees don't block rays, so it would see through the forest).
  F9 debug tanks still start at the edge (approach 0).
- Forest lanes: `ForestScatter.keep_clear` default has 3 rects, x = route start ± 6.5,
  z −151…−104 (positions RNG unchanged, trees inside just skipped). Navmesh re-baked after (fewer
  tree holes: 3090 → 2800 vertices). If a route start moves, move its lane too (test_t3 checks).
- Wrecks: `TankSpawner.max_wrecks` 3; host `_process` every 0.5 s calls `clear_old_wrecks()` while
  `DayScreen.is_black()`, also at every wave start as a fallback. Oldest = lowest `TankN` number;
  `queue_free` on the host, the MultiplayerSpawner removes it everywhere.
- MolotovManager: a pooled fire stuck to a freed wreck is skipped in `_update_visuals` and
  re-made in `shatter` (`is_instance_valid(f.node)`).
- `tools/test_t3.gd`, `tools/shots_t3.gd` (tank in its lane, from the trench and up close).
