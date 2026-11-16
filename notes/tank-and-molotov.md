# T-26 tank and Molotov cocktail (T1, T2, T3), armour (T5), climbing out of the trench (C1), running tracks (T6)

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
  `TerrainGenerator.get_height()` under 4 track points (smoothed). Routes end at z = 49 (owner:
  3 m closer than the first 46; nose at 51.3; trench front edge ≈ 57) and avoid the lone trees (test_t1 rebuilds their positions with
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
- Turret traverse: see "Turret feel (T4)" below (the old flat 24°/s is gone).
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

## Armour stops enemy bullets, sight and blasts (T5)
- Owner 2026-11-13: "bullets should not go through tanks" – the player's own bullets already
  stopped (mask world + players + enemies), but every ENEMY ray left layer 3 out, so soldiers and
  tanks shot and saw straight through tanks and wrecks.
- The tank body is now on layer 3 AND the new layer 5 "armour" (`collision_layer` 20 in
  `soviet_tank.tscn` + the builder; layer name in `project.godot` + `setup_project.gd`). Constants
  in `tank.gd`: `ARMOUR_LAYER`, `SIGHT_MASK` (world + armour), `BULLET_MASK` (world + players +
  armour). Used by `Enemy._has_line_of_sight`, `Enemy._shoot`, `Tank._clear_line` (sight AND the
  45 mm blast line), `Tank._shoot_dt`, `Tank._fire_main_gun` (each tank excludes itself). A hit on
  armour shows the "metal" sparks through the usual `surface_of`.
- Unchanged on purpose: soldiers still walk through tanks (their body mask has no layer 3 or 5);
  artillery and bombs use the position rule `ArtilleryBarrage.is_covered`, not rays, so a wreck
  does NOT shield from those. The collision is still a box (0.2–1.6 m high) + turret cylinder:
  shots under the belly or past the gun barrel go through.
- `tools/test_t5.gd`: soldier / tank / wreck / blast lines with a tank parked in between.

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
  BURNING counts as stopped). Bailed-out crew DO count (fix 2026-11-01; they used to be left
  out, survived into the next battle and could break the line – on Hard 3 crew = the limit):
  `Tank._bail_out()` → `WaveSpawner.add_enemy(e)` (alive_count + died signal, HUD "Enemies"),
  and `tanks_in_fight()` also counts burning tanks with `Tank.crew_still_inside() > 0`, so the
  battle can't end in the 2–4 s before the crew climb out. Checked in test_t3.
- Route (fix 2026-11-09): `TankSpawner._pick_route()` = a random route with NO tank on it, not even a wreck or burning tank
  (new tanks used to drive into old wrecks and were hard to hit). If every route holds a wreck, the route with the
  oldest wreck is cleared (`queue_free`) and used. Test in test_t3.
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

## Tank 3 m closer + Molotov hint (after T3, owner's request)
- `TANK_ROUTES` last points z 46 → 49 (all three routes). From there a man standing in the trench
  right in front of the tank was below the gun's lowest angle, so the tank never fired:
  `Tank.gun_min_deg` −10° → −14° (test_t1 "fires into the trench" caught it).
- First battle with tanks (normally battle 4; in Test Mode the first one played): `HUD.TankHint`
  (where the BATTLE banner was) shows "TANKS ARE COMING!" + where the Molotov boxes are and the
  keys (read from the Input Map via `ControlsPanel.key_text`). It waits until the banner has
  faded, stays `tank_hint_time` 14 s, once per match (`_tank_hint_shown`). Local UI only.

## Climbing out of the trench (C1) – how it is built
- `ClimbHandler` (`scripts/player/climb_handler.gd`, Player child `Climb`, no nodes of its own).
  `Player._apply_gravity_and_jump`: on the floor, a jump request first asks `climb.try_start()`;
  only if that says no does the normal jump happen (not while crouching, as before).
- `find_ledge()` (host, rays on the world layer 1 only – so never onto a tank): a near-vertical
  wall within `reach` 0.5 m of the body, faced within `max_angle_deg` 60°; ground on top
  `step_in` 0.5 m behind the wall face, `min_height` 0.9 … `max_height` 1.7 m above the feet
  (lower = a normal jump can do it); nothing over the head, nothing between him and the spot,
  and room for a standing capsule there (world + tanks). The 0.84 m sandbag wall on top of a
  firing position's front makes that ledge 2.24 m → no climbing out through a firing position.
- Refused while dead, bandaging, on the Maxim, or `MolotovHandler.can_climb()` is false
  (IGNITING / LIT / THROWING). Starting drops a reload, un-crouches, stops sprinting.
- `update()` (host, from `Player._physics_process` while `is_climbing`; normal movement is
  skipped): the position is set directly – `up_share` 0.6 of `climb_time` 1.0 s straight up, then
  forward to the spot (smoothstep, overlapping a little). Jump / F / B presses are swallowed.
  Death or respawn → `cancel()` (a dead man falls back in).
- `Player.is_climbing` is in StateSync (ON_CHANGE). WeaponController: no firing, aiming or
  reload start, gun lowered out of view; MolotovHandler: HELD can't go to IGNITING; the head
  leans a little (`Player._process`). No sound and no HUD text of its own.
- Enemies and tanks need no change: they see / shoot the climber like anyone in the open
  (test_c1 checks the line from a parked tank's eye height).

## Turret feel (T4) – how it is built
- `Tank._aim()` → `_traverse()`: the host keeps a signed `_turret_vel` (rad/s). Top speed:
  `turret_idle_deg` 4 (no target / trench sweep, whose swing peaks at exactly 4), `turret_track_deg` 8,
  `turret_emergency_deg` 12 when the target is closer than `emergency_range_m` 25 (hard cap 12).
  Inside `close_range_m` 10 the top speed scales down to `close_efficiency` 0.5 at point-blank.
  Speed changes by at most top / `turret_ramp_time` (1.5 s) per second; the wanted speed is
  min(top, sqrt(2·a·error)) so it brakes in time and stops on the mark; a reversal passes through zero.
- Reaction (`_update_reaction`): a NEW target → hold `react_min..max` 0.3–0.6 s (turret coasts to a
  stop, no cranking); if he is further round than `behind_angle_deg` 100° (from the hull's front, or
  from the turret) add `reacquire_min..max` 0.8–1.5 s. The same target slipping behind the hull
  triggers the reacquire delay once (20° hysteresis). `_turret_hold_until` is in `_clock` time.
- Consequences: the hull turns under the turret (up to 22°/s) and the turret can't follow, so the DT
  often loses the aim on bends; a sprinter circling inside 10 m can't be tracked. Gun elevation
  speed is unchanged (14°/s). "Emergency after a Molotov hit" was NOT built (emergency = range only).
- Sounds (`assets/audio/tank/`, made by `tools/make_turret_sounds.py`, players built in code by
  `_setup_turret_sounds()` under `TurretPivot`, NOT in the scene): `turret_gear.ogg` (336328
  newagesoup, loop), `turret_crank.ogg` (395041 aslakhostaker, loop), `turret_clunk_1..3.ogg` +
  `turret_stop.ogg` (144824 zabuhailo "doorlatch": three clunks; the stop clunk is the end of the
  recording). Every computer works out the speed from the synced `turret_yaw` (smoothed), so
  volume/pitch follow the real speed; a clunk at start, a stop clunk (after > 0.8 s of turning) and a
  random clunk every 2–5 s. Loops are set in code (`.loop = true`). `RecordedSounds` prefixes
  `tank_turret` (gear loop) / `tank_clunk` (clunks) override them.
- `tools/test_turret.gd` (speeds, ramp, delays, behind, close range, reversal smoothness, sprinter).
  Flaky BEFORE T4 too (random): test_t1 "DT bullets hurt" / "HALT_FIRE", test_m3 "soldiers advance".

## Tank tracks in the snow (V10b) – how it is built
- `TankTracks` (`scripts/enemies/tank_tracks.gd`, node `Game/TankTracks`, group `tank_tracks`).
  Picture only, made on every computer from the `tanks` group (nothing synced, `tank.gd`
  untouched): it remembers where each tank's last strip ended and lays a new one when the tank
  has moved `strip_length` (1.5 m) on. A jump of more than 3 strips (spawn, tests) lays nothing.
- All strips are ONE MultiMesh (child `Strips`, `top_level`, 1 draw call, 2 triangles per
  strip): a pool of `pool_size` 640 (≈ four tanks driving the whole field); when full the oldest
  strip is reused (`visible_instance_count` grows to the pool size, then stays). `custom_aabb` =
  the whole map, so Godot doesn't work the box out again for every strip.
- A strip is a flat 2.6 × 1.5 m PlaneMesh with a generated 128 × 64 texture (`make_texture()`:
  two ruts 1.02 m either side of the centre line, 0.34 m wide, 12 cross-bars, see-through
  elsewhere, mipmaps). It lies on the ground: four `TerrainGenerator.get_height()` samples
  (front, back, under each rut) give its tilt, `lift` 5 cm keeps it from flickering. It is
  stretched to reach exactly from the last strip's end to the tank (no gaps on bends).
- Material: StandardMaterial3D, alpha, LIT (not unshaded like the scorch marks) – so the ruts
  are dark at night and fogged like the snow; `color` × `strength` (0.8) to tune,
  `render_priority` -1 (under smoke and scorch marks). No shadows cast.
- New day: cleared behind the black day screen (same poll as the bodies). Old wrecks then stand
  without tracks (owner: OK).
- Headless gotcha: `MultiMesh.get_instance_transform()` returns identity without a renderer, so
  the script keeps its own copy (`_placed`, `strip_transform()`) for the tests.

## Running tracks and turning wheels (T6) – how it is built
Checked 2026-11-16 (Godot 4.7.2): test, all other tests, GL window (no shader errors), pictures
for battles 4 (daylight) and 6 (darkest), web export, smoke test and a browser run into the game.
From 55 m (the trench) the tank is ~30 pixels wide: the running links cannot be made out there,
close up they can – also in battle 6, where the lit snow patches show the movement.
- `TrackAnimator` (`scripts/enemies/track_animator.gd`, tank child node `TrackAnimator`, in the
  builder's `_build_tank()` and in `soviet_tank.tscn`). Picture only, nothing synced, `tank.gd`
  untouched and unaware (like `TankTracks`): every computer works it out from where it sees the hull.
- Each PHYSICS step (the tank is moved in physics steps, so one step = one clean measurement):
  `forward` = the hull's movement since the last step along its nose, `turn` = how far it turned
  (left = +, read from where the old nose points in the new hull's space) × `half_track_gauge`
  1.03 m (track centres are at x = ±1.027 in the model). **left = forward − turn, right =
  forward + turn.** Straight 2 m/s → 2 / 2; the tightest bend (22°/s) → 1.6 / 2.4; on the spot at
  22°/s → −0.4 / +0.4; reverse → both negative. It measures DISTANCE, not a smoothed speed, so the
  links on the ground stay put on the snow and the tracks stop the moment the hull stops.
- "Believable" rules (`_believable`): under `dead_zone_speed` 0.02 m/s = exactly 0; never over
  `max_track_speed` 4 m/s; a step of more than `teleport_distance` 2 m (spawn, tests setting
  `_distance`) moves nothing. A wreck (`tank_wrecks` group) switches its animator off for good.
  Read-only for tests / future use (track sound, snow spray): `left_speed`, `right_speed`,
  `left_travel`, `right_travel`, `is_moving()`, `scroll_of(side)`.
- **Today's `tank.gd` only drives forwards and only turns while driving** – reverse and turning on
  the spot work in the animator (test_t6 moves a parked tank by hand) but are never seen in play.
- Tracks: the model's two belt meshes (`track_LShape…`, one material each) already have a link
  picture that repeats 12× around the belt (UV.y −5.5…6.5; belt 9.73 m → `metres_per_repeat`
  0.81). `resources/shaders/tank_track.gdshader`: `UV.y += scroll` (repeats run, wrapped at 12).
  Driving forwards `scroll` grows = the picture moves backwards on the ground run.
- Snow and dirt: `TrackAnimator.grime_texture()` – ONE 16 × 256 picture made in code at the first
  use (in ShaderWarmup, behind the loading screen; ~4 000 pixels, seed 1940, shared by all tanks):
  R = snow patches, G = frozen dirt, B = the snow patches grown (used in the dark gaps between
  links). It goes once round the whole belt and slides with it, so the 12 repeats differ.
  The masks are stored ready-made (not thresholded in the shader) so far away they blend to their
  average instead of vanishing. Uniforms `snow_amount` 0.6, `dirt_amount` 0.45, `snow_color`,
  `dirt_color`, `steel_brightness` 1.5 (the model's steel is nearly black: linear 0.02);
  `grime_shift` from the tank's name + side. Low light: nothing glows – the snow is LIT like the
  ground snow and is what shows the movement at dusk.
- Wheels: sprocket, idler, 8 road wheels and 4 return rollers per side are welded into ONE
  `chassis_RShape…` mesh per side (83 loose pieces each). `tools/import_weapons.py`
  `bake_t26_wheels()` (also alone: `python3 tools/import_weapons.py --t26-wheels`; safe to repeat)
  finds the pieces of each wheel (table `T26_WHEELS`) and writes the axle into glTF TEXCOORD_1 =
  Godot **UV2**: x = axle along the tank (mesh +y = nose), y = axle height + 2 × kind (1 sprocket /
  idler, 2 road wheel, 3 return roller), (0, 0) = fixed. 1 470 of 3 096 vertices per side turn.
  Sprocket / idler take everything inside their circle (teeth, spokes, hub, bolts); road wheels and
  rollers only the disc (the pin through the hub is a few mm off-centre in the model and would
  wobble). `model.gltf` + `scene.bin` changed (+50 kB) – CREDITS.md says so (CC-BY).
- `resources/shaders/tank_wheels.gdshader` turns each wheel vertex (and its normal) around its
  axle in `vertex()`; uniform `wheel_angles` (x sprocket/idler, y road wheels, z rollers; radians,
  wrapped at a full turn) = travel ÷ radius (`sprocket_radius` 0.322, `road_wheel_radius` 0.161,
  `roller_radius` 0.142). Same single draw call per side as before.
- Materials: at `_ready` the animator gives the 4 meshes their own `ShaderMaterial`
  (`set_surface_override_material`; left/right from where the mesh sits, not from its name; the
  picture and roughness are taken from the model's own material). 4 small materials per tank, two
  shared shaders. The wreck's dark `material_overlay` still works on top.
- Cost: 0 new draw calls, 0 new triangles, no per-frame allocation; per moving tank and physics
  step 2–4 `set_shader_parameter` calls, none while it stands.
- Known limits: the road wheels are plain dark discs in the model's picture, so their turning is
  hard to see (sprocket teeth and idler spokes show it well) – idea: a faint snow smear on the
  wheel faces. The belt's top run does not sag or bounce.
- `tools/test_t6.gd`, `tools/shots_t6.gd [battle]` (camera rides beside the tank; flip through
  the `side_0..5` pictures; `far_0..1` = from 55 m, 4 m beside the route – a lone spruce hid the
  tank from the first camera spot). `check_web_pack.gd` T6 checks. `web_smoke_test.py` stops
  while the loading screen is still up (software WebGL is slow): to see the warm-up shaders
  compile in the browser, run a copy with the last wait raised to ~200 s.
