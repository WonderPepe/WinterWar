# Battle, waves, enemy pressure, artillery (G1, G2)

Moved from CLAUDE.md (2026-11-01). Read when working on this area; keep it up to date.

## The battle (G1) – how it is built
- `MatchDirector` (Game/MatchDirector, group `match_director`, synced by MatchSync with
  `delta_interval = 0.25`): host applies `DifficultyData` (`Settings.difficulty`, chosen in the
  main menu) to WaveSpawner (`base_enemies`, `enemies_added_per_wave`, `max_waves`),
  `Game.respawn_time`, `Enemy.spread_multiplier` and `Enemy.damage_multiplier` (static). Counts living enemies with
  `is_in_trench()` (y < -0.85 and z > 48) 4×/s → `in_trench`; ≥ `trench_limit` → DEFEAT.
  `wave_cleared(n)` → heal all players, n ≥ `waves_to_win` → VICTORY. `end_match()` stops the
  spawner (`active = false`) and `freeze()`s enemies. HUD opens `EndScreen` when `is_over()`;
  single player pauses the tree; PauseMenu stays closed while the match is over.
  The benchmark disables the director (`set_process(false)`, `max_waves = 0`, spread 1.0).
- Enemy `State.ASSAULT` (added at the END of the enum – it is synced as a number): PATROL/ALERT/
  ATTACK at the attack point → `_hold_at_goal()` for `assault_hold_min…max` s → `_begin_assault()`
  picks the nearest `trench_entry` NavigationLink3D (10 of them, one per ~20 m of trench, chosen by `_entry_legs()`: ground → floor, one-way;
  the navmesh already had the trench floor as its own island) → runs there, the link makes the path
  drop into the trench → `_trench_fight()`: nearest living player, shoot when in sight (no spotting
  delay, `trench_fire_interval_*`), else follow the navmesh. Stuck > 1 s → step aside (landed on
  someone). `hear_noise` / `take_damage` don't pull an assaulting soldier out of ASSAULT.
- Navmesh vertices sit ~0.4 m above the surface: the trench floor shows up at y ≈ -1.0, not -1.4.
- Ammo crates: `scenes/props/ammo_crate.tscn` (group `ammo_crates`): one in a CSG niche
  (`AmmoNiche`, `_ammo_niche()` in the builder) next to the first spawn, one in the bunker.
  F (Player `_handle_mounted_gun`): a usable gun wins, else the nearest crate → `resupply()` →
  `refill_reserve()` + bandages, `notify_resupplied` RPC → HUD message.
- Bandages: Player `bandages` / `is_bandaging` (StateSync), `request_bandage` (B) on PlayerInput;
  WeaponController can't fire/aim while bandaging and lowers the gun.
- StateSync now also syncs `is_dead`, `kills`, `deaths` (were missing – would have broken co-op),
  WeaponSync `shots_fired` / `shots_hit` (end-screen statistics, counted in `resolve_shot`).
- `DuskLight` (Game/Dusk) – since B3 it applies the WEATHER of the current battle, not a slow sunset:
  see `graphics-and-web.md` ("Weather and time of day (B3)"). It still duplicates the Environment,
  Sky and sky ShaderMaterial at start (never edit the saved resources at runtime – they are cached
  across "Play again"), and changes the look while the day screen is black (`DayScreen.is_black()`).
- `tools/test_g1.gd`, `tools/soak_g1.gd` (real waves at 3× speed vs a god-mode player: with nobody
  shooting, wave 1 breaks the line after ~2.5 min), `tools/shots_g1.gd`.
- Measured (G1, xvfb): ~177 draw calls average (crates add a few).

## Pressure (G2) – how it is built
- Three enemy scenes (all `enemy.gd`, `MultiplayerSpawner` lists all three): `soviet_rifleman`,
  `soviet_officer`, `soviet_mg_gunner`. `EnemyData.kind` (RIFLEMAN / OFFICER / MG_GUNNER) picks the
  body: `SoldierMesh.get_mesh(kind)` (cached per kind; officer = peaked cap, strap, holster, map
  case, TT pistol; gunner = DP-27 on the rifle bone) and `SoldierMesh.muzzle_for(kind)`.
  `EnemyData.fire_sound` (+ pitch) / `fire_sound_recording` ("dp27") override the scene's shot sound.
- **G2 timers use the soldier's own game clock** (`_clock += delta`, `_now()`), not
  `Time.get_ticks_msec()` (the older shot timers still do) – so tests at `Engine.time_scale` work.
- Suppression (host only, not synced): `WeaponController.resolve_shot` calls
  `call_group("enemies", "bullet_near", origin, end, w.suppression)` (WeaponData `suppression`:
  Mosin 0.45, Suomi 0.16, Maxim 0.3). Gain falls off with distance (`suppression_radius_m` 3 m),
  × `nerve`, × 0.6 near a living officer, × 0.5 for 4 s after a whistle, × 1.6 while leaderless;
  ignored near the shooter (< 4 m) and in the trench fight. Wounds add `wounded_suppression`.
  Recovers `suppression_recovery`/s after `recovery_delay`. ≥ `prone_threshold` (0.35) → prone,
  < half of it → up again; ≥ `pinned_threshold` (0.8) → no firing, aim resets. Spread and shot
  interval scale with suppression. Prone + not pinned for `_prone_patience` (6–10 s) → a 3–5 s dash
  (`_dash_until`), otherwise a lone soldier lay pinned for ever in the soak test.
- `is_prone` is synced (StateSync, ON_CHANGE). Prone: capsule rotated to lie along the body
  (height 1.7, centre y 0.3, z -0.15), eyes at (0, 0.5, -0.7). `_move_to()` refuses to move while
  prone; `_hold_at_goal` doesn't count while prone (no rush). Killed while prone: no fall tween.
- SoldierVisual prone pose: hips at y 0.2 pitched -1.45 rad, chest up 0.3, head up 0.75; the weapon
  target is worked out in SKELETON space (right shoulder + offset, level) and converted into spine
  space with the target hips/spine transforms. Officer: pistol held out / down by his side; left hand
  to the mouth while `_whistle` > 0 (`play_whistle`). Gunner prone: left hand on the butt.
- Officer: `_officer_think` (senses tick) whistles when a comrade within `rally_radius_m` is prone
  (cooldown 9–15 s) → `rally()`; also when he first goes to ATTACK. At his jump-off point
  `_order_assault()` whistles and sends everyone within 1.4 × radius who `can_join_assault()`.
  Death → `lose_leader()` on comrades within 1.5 × radius (+8 s before the rush, more suppression).
  Pistol only within `max_fire_distance_m` (45 m). `play_whistle` RPC (reliable) plays
  `RecordedSounds.pick("officer_whistle")` or `assets/audio/officer_whistle_placeholder.wav`
  (`tools/make_whistle.py`, own RNG – make_sounds.py untouched).
- MG team: the spawner links `gunner.mg_assistant` / `helper.mg_gunner` (host-only references; the
  helper is a rifleman scene). Final gun position (`_mg_final_goal`) = attack point − 5…10 m in z
  (`mg_position_back_min_m` / `_max_m`; was 35 m). "Fire, then move up" (owner 2026-11-02, replaced
  the old "lie down at first sight ≤ 170 m"): `_mg_follow()` (~1×/s) keeps the team
  `mg_follow_back_min/max_m` (5–10 m, random per team) behind the nearest living rifleman/officer
  outside the trench (`_mg_leader()`), never past the final position, never back towards the
  forest, hurrying (`_mg_hurry`) when > 8 m behind. ATTACK + sees a Finn + within its fire range
  of the trench (`mg_fire_range_min/max_m` 80–130 m, random per team; `distance_to_trench()`) →
  `_deploy()`. Deployed: after ≥ `mg_min_fire_time` 8 s (and not changing the pan), once the
  leader is `mg_move_up_m` 20 m further on, the team gets up, catches up (no redeploy before
  `_mg_no_deploy_before_z`) and sets up again. No leader → stays put / walks to the final
  position; at the final position it deploys even without a target. Deployed → own branch
  `_mg_deployed()` in `_physics_process` (bursts `mg_burst_min…max` at `mg_shot_interval`, pause,
  47-round pan, reload 3.5 s helped / 6 s alone). Deploying moves the helper's attack point next to
  the gun; the helper lies down there (`_deployed`) and never assaults while the gunner lives;
  gunner dead → `_gunner_lost()` → helper goes to his `home_point` as a normal rifleman.
- Owner (2026-11-02): when every soldier of the wave who is NOT in a gun team is dead (riflemen,
  officers, tank crews; whole wave out of the forest), the gun teams go for the trench like
  riflemen: `WaveSpawner.release_mg_teams_if_alone()` (FIGHTING phase, every
  `mg_release_check` 0.5 s) → `Enemy.advance_as_rifleman()`: `mg_released` (host), not
  deployed, `attack_point = home_point` (the riflemen's attack point; spawner sets it for both),
  helper `_gunner_lost()`. A released gunner skips `_mg_attack` / `_mg_deployed` / the deploy in
  `_hold_at_goal`, fires single shots like a rifleman, rushes the trench, `can_join_assault()`.
  `Enemy.is_mg_team_member()`. Checks in test_g2 (4b).
  Enemy smoke puffs at most every 0.25 s (bursts).
- Waves: `WaveData` (riflemen, officers, mg_teams); `DifficultyData.waves` (builder `WAVE_LISTS`);
  `MatchDirector` copies it to `WaveSpawner.wave_list` (empty = old riflemen formula; the
  benchmark empties it). `_make_groups()`: rifle groups, officers in the middle of groups, MG
  teams after every second group; a group only spawns when it fits under `max_alive`.
  WaveSync also syncs `wave_riflemen/officers/mg_teams` (+ T3 `wave_tanks`); the HUD banner shows
  `WaveData.describe()`. T3 tanks in a wave: see `tank-and-molotov.md`.
- `tools/test_g2.gd`, `tools/soak_g2.gd [waves]` (defender bot firing near misses, 3× speed),
  `tools/shots_g2.gd` (poses; needs xvfb). `check_web_pack.gd` checks the wave lists survive export.

## Artillery barrage – how it is built
- `ArtilleryBarrage` (Game/ArtilleryBarrage, `scripts/game/artillery_barrage.gd`, group
  `artillery`). Host: `WaveSpawner.wave_started` → `get_composition(n).barrage` → `start()`:
  WARNING (`warning_time` 4 s) → FIRING (length of the recording) → `_finish()`. Phases are set
  on every computer by RPCs (`begin_warning/begin_firing/end_barrage`); the 2D recording plays
  on every computer (SFX bus). Old G2 plan: artillery was dropped then, added now on request.
- Shells: `shell_times` / `shell_strengths` (builder `BARRAGE_SHELLS`, 47 bangs found in the
  recording with a Python onset detector). Host picks the spot (`_pick_landing`: `aimed_share`
  near exposed players, else `lerp(far_m, near_m, strength)` from a random player; inside
  `zone_min/max`, never in `trench_rect`), damages exposed players (`is_covered()`: y < -0.5,
  48 < z < 76, |x| < 108 → trench/bunker/Maxim are safe), then `explode.rpc(pos, strength)`.
- Visuals per blast (pool of 6): flash quad + OmniLight (0.18 s), earth clods, dark plume, snow
  cloud, smoke (all `ImpactEffects.web_fallback`), scorch quads (pool 30) fade out
  `scorch_fade_time` after the end. Camera shake: `Player.add_shake()` → `camera.rotation`
  jitter in `Player._process` (local only; nothing else sets camera.rotation).
- The wave meanwhile: `Enemy.barrage_hold_z` (static, host) = `hold_z` (0) while it lasts:
  `_move_to` clamps the destination z to `hold_z + _hold_offset` (−8…0) and hurries;
  `_hold_at_goal` only kneels (no assault). End → INF, every living officer `signal_advance()`
  (whistle + rally). Barrage waves always have an officer (builder `WAVE_LISTS` 4th value).
- Fix (2026-11-01): the static hold line outlived the match – leaving (Esc → Main Menu) or
  losing (the end screen pauses before `_finish`) during a barrage kept it at 0, so the next
  match's soldiers stopped ~50 m short and never assaulted until a barrage ended.
  `ArtilleryBarrage._ready()` and `_exit_tree()` now set it back to INF (checked in test_artillery).
- HUD `ArtilleryWarning` label (top centre): warning, then only "GET INTO THE TRENCH!" for
  anyone in the open; no text in the trench/bunker and none when it lifts. `tools/test_artillery.gd`, `tools/shots_artillery.gd`.
- Artillery upgrade (2026-11-05): warning is 6.5 s and plays `guns_distant.ogg` (Freesound 345844,
  distant gunshots, 5.9 s) on every computer so players can get down before the first shell.
  `shell_close.ogg` (Freesound 256297, first 4 s of the loud explosion) plays for the LOCAL
  player when a barrage shell lands within `close_sound_range_m` (28 m), louder when nearer
  (`_play_close_burst`, from `explode()` only – the tank's `show_explosion` call is unchanged).
  Bigger blasts: kill 6 m, harm 35 m (shrapnel; cover only while CROUCHING in the trench/bunker – `is_covered` = `is_in_shelter` + `is_crouching`; no HUD hint for crouching; the whole bunker room (`is_in_bunker`) is safe, standing or crouching, but NOT while mounted on the Maxim (L2d/L2e: gunner is hit by shells landing in front of the bunker); no "stay down" text during the barrage, only the warning and "GET INTO THE TRENCH!" in the open), near_damage 110, aimed_share 0.55, `blast_scale` 1.5
  (bigger flash/particles/scorch) and `shake_range_m` 120. Both sounds are set in
  `scenes/game.tscn` (edited by hand, so rebuilding scenes would need the same two lines in
  `build_scenes.gd`, which now has them). Trench/bunker still fully safe.
- Sound: Freesound 486086 "Artillery Barrage" by Mozfoo (explosion by Steveygos93), CC-BY 4.0;
  mono, −4 dB + limiter, 1.3 s fade. Original WAV in `assets_source/`.

## Air raid (A1, owner 2026-11-08)
- `AirRaid` (Game/AirRaid, `scripts/game/air_raid.gd`, group `air_raid`). Three Tupolev SB-2 bombers in
  waves/battles 4 and 8 (`raid_waves`; battle n = wave n). Owner's choice: same danger as the artillery
  (`ArtilleryBarrage.is_covered`: open ground deadly, crouching in the trench / the bunker safe, the
  Maxim gunner exposed to bombs in front), bigger bombs (kill 9 m, harm 50 m, near_damage 120).
- Those waves also have an artillery barrage on Easy/Normal, so the raid waits for `barrage_ended`
  and starts `after_barrage_delay` (5 s) later WITHOUT a hold line (the attack is already moving).
  A wave without a barrage (Hard): the raid starts at the wave start and holds the Soviets at z 0
  (`Enemy.barrage_hold_z`, reset in `_exit_tree` like the barrage); officers whistle at the end.
- Phases APPROACH (HUD "AIR RAID! GET INTO THE TRENCH!", engines far away) -> BOMBING (first bomb in the
  air, "GET INTO THE TRENCH!" only for people in the open) -> LEAVING -> IDLE. ~38 s.
- Host makes the plan (`_make_plan`) and sends it once (`begin_raid` RPC: plane data + every bomb's
  landing time/position/strength); every computer runs its own clock from it, only the host hurts
  players (`_land`). Plane i flies along x at its lane z (front 24-40, just behind 74-80, far 96-115),
  110 m/s, ~300 m up, direction random; 8 +-1 bombs per plane, 25 m apart, each lands right under its
  plane `fall_time` (6 s) after release; none inside `trench_rect`.
- Looks: the camera far plane is 600 m, so planes and falling bombs are drawn closer and smaller in the
  same direction (`_cheat`, `cheat_distance` 480); the sounds use the real position. Planes are code-built
  (capsules/boxes, unshaded dark, twin fins). Blasts reuse `ArtilleryBarrage.show_explosion` with
  `blast_scale` 2.3 and the new `height_mul` (1.7: earth and snow go higher and stay up longer); the
  barrage's pool is now `pool_size` 12 (was 6; set in game.tscn + builder).
- Sounds (owner's recordings, `assets/audio/recorded/`, originals in `assets_source/`): engine = the
  existing plane recording (`plane_flyover_viima.ogg`, loudest 10.9 s in, started per plane so its peak
  is at the pass; pitches 1.0/0.94/1.07) or any `raid_engine*` (then set `engine_overhead_at`);
  `raid_whistle.ogg` = Freesound 479924 (craigsmith, CC0), 5.5 s cut from the 12.7 s steady whistle,
  fade in, rising level, ends exactly at the impact (length is capped at `fall_time` 6 s, so keep it
  shorter); `raid_boom_1/2.ogg` = Freesound 256297 / 256299 (YleArkisto), first 6 s, mono, a random one
  per bomb (`_boom_sounds`). No generated placeholders any more; no recording = silence. The artillery's
  `shell_close` layer was dropped (it is the same recording as raid_boom_1); `close_sound` is still an
  export if wanted.
- Tests: `tools/test_airraid.gd` (plan, no bomb in the trench, hurt in the open, hold line, after-barrage
  start), `tools/shots_airraid.gd` (xvfb; aims at plane 1).
