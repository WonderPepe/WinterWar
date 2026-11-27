# Soldiers, effects, sound (P2), background sounds

Moved from CLAUDE.md (2026-11-01). Read when working on this area; keep it up to date.

## Effects, sound, soldiers (P2) – how it is built
- Soldier = `SoldierVisual` (Enemy's `Visual`): builds a Skeleton3D (16 bones, `SoldierMesh.Bone`;
  SV1 added hands + feet at the end) and one shared skinned ArrayMesh (`SoldierMesh.get_mesh()`,
  ~1 310 tris (MG gunner 1 420; SV1b rounder shapes: `_lathe`, `_grid`, `_brim`, `_band`,
  `_rounded_foot`), vertex colours; alpha = cloth type for `soldier.gdshader`, 0.15 = face).
  SV1 face: shaped head + `soldier_face.png` (made by `tools/make_soldier_face.gd`) painted on the face
  corners (UV = `SoldierMesh.face_uv`); feet bend at the ankle (`SoldierMesh.foot_pose`) – see
  milestones.md "SV1". Poses are set in code every frame from synced state
  (position delta → walk speed, `state`, `is_kneeling`); arms use 2-bone IK to grip the rifle.
  Muzzle = BoneAttachment3D on the rifle bone (`visual.muzzle`; it lags the bone by one frame).
  Per-soldier material copy (coat tint) and size. Death fall direction comes from `hash(name)`
  so all computers agree. Enemy RPCs: `show_shot_effects`, `show_hit` (flinch),
  `bullet_passed` (sent only to the peer whose head the bullet passed within 3 m).
- `ImpactEffects` pools: holes, sprays per surface (snow/wood/cloth), smoke, flashes, crack
  sounds. `make_smoke_emitter()` / `make_soft_texture()` are static (Maxim, breath reuse them).
- Muzzle flashes in the dark (V1): `spawn_flash()` (enemies, tanks, other players) – 50 ms, one
  shared QuadMesh + material for all 12 pooled flashes. `WeatherData.darkness()` (0 day … 1 night,
  from sun/moon + ambient light; smooth step 1.1 → 0.4) is put into the static
  `ImpactEffects.darkness` by `DuskLight._apply` (reset in `_exit_tree`), so battle 10 darkens as
  its dusk deepens. Values: battles 3/4/7/8 = 0, 9 ≈ 0.07, 5 ≈ 0.28, 1 ≈ 0.44, 10 ≈ 0.52 → 0.98,
  2 ≈ 0.94, 6 = 1. The flash look is updated only when the darkness changed: size 0.35 m ×
  (1 + `night_size_gain` 0.1 × d), colour × (1 + `night_brightness_gain` 0.12 × d) (above 1.0 =
  whiter core, shows through fog). Darkness ≥ 0.3 and within 80 m of this computer's camera: one of
  2 pooled OmniLights (range 3.5 m, energy 0.4 × d, no shadow/specular) glows for the 50 ms; if both
  are on, no glow. Day = exactly as before. Measured with `shots_flash.gd` (brightness change
  around a flash at 60 / 120 m vs. before V1): day 0 %, battle 1 / 10 start about +25–65 %,
  night (2, 6, 10 end) about +50–60 %. (Battle 5 at 60 m reads +170 % only because the old orange
  flash had almost the same brightness as the hazy background there.) Tune the @exports in
  `impact_effects.gd`.
- Footsteps: generated ones were removed (owner: "very bad"). `FootstepSounds` loads real
  recordings by name from `assets/audio/footsteps/` (snow / trench|gravel / wood; trench falls
  back to snow) with `ResourceLoader.list_directory` (works in exports). No files = silent.
  Wind loop is at -14 dB (owner: wind too loud).
- Reload and hurt sounds: the generated reload.wav / belt_reload.wav / hurt_thump.wav were removed
  (owner: "sounding bad"). `RecordedSounds` (scripts/game/recorded_sounds.gd) loads real files by
  name prefix from `assets/audio/recorded/` (`reload_<WeaponData.recording_name>…`, `hurt…`);
  `WeaponData.get_reload_sound()` = `reload_sound` if set, else a recording, else null (silent).
  make_sounds.py still runs those generators without saving (keeps the random numbers the same).
  The generated Mosin bolt click (bolt_cycle.wav) was removed too (owner): `WeaponData.get_cycle_sound()`
  = `cycle_sound` if set, else a recording `bolt_<recording_name>…`, else silent.
  The hit tick (hit_tick.wav, HUD HitSound) was removed too (owner) – hits only show the marker.
  Placeholder sounds that remain: shots, empty click, ambience, cracks, steam.
- The shooting-range practice targets were removed from the level (owner); navmesh re-baked.
  `scenes/props/target_dummy.tscn` stays only for tests (test_m2 / test_w1 / shots_m2 place their own).
- Breath vapour: faint (alpha ~0.1), below the line of sight; Settings `show_breath` (menu
  "Breath vapour") switches it off for you and the soldiers. Maxim smoke: thin, pushed out of
  the slit.
- `PlayerFX` (child of Player): footsteps (surface from a ray down: wood meta / trench y < -0.8 /
  snow), breath (child of the camera, local only), drift (top_level, local only, preset
  `drift_amount`). Player `notify_hurt` RPC → `hurt_from` signal → HUD `DamageIndicator`.
- Buses: Master → SFX (Reverb + HardLimiter), Ambience (LowPass used for muffling; volume from
  Settings `ambience_volume`), UI. Made by `tools/make_buses.gd`. Set `bus` on every new player.
- Measured (High, P2): ~165 draw calls (220 max) – fewer than before thanks to one-draw-call
  soldiers – ~275k triangles. Web download ~50 MB.

## Background sounds – how it is built
- `BackgroundSounds` (Game/BackgroundSounds, `scripts/game/background_sounds.gd`): `sounds` +
  `overhead_at` (seconds into the file when it is loudest). Host picks, at wave 1, a wave
  between 2 and waves_to_win−1 and a moment 15–60 s into it (only while enemies are alive), then
  `play_flyover.rpc(index, heading, side_m)`; every computer spawns an AudioStreamPlayer3D
  around its own camera, 80 m up, moving at 50 m/s so it passes overhead at `overhead_at`.
  `unit_size` 120 and no attenuation filter / doppler (the recording has its own approach),
  bus SFX (not Ambience: that one is muffled in the trench).
- Plane: `assets/audio/background/plane_flyover_viima.ogg` from Freesound 254511 (YleArkisto,
  CC-BY 4.0; credited) – trimmed 1.5 s + 39.3 s, mono, -3 dB + limiter (the stereo mix clipped),
  fades. Original WAV in `assets_source/` (git-ignored). `tools/test_background.gd`.

## Bodies stay (V10b) – how it is built
- `BodyKeeper` (`scripts/enemies/body_keeper.gd`, node `Game/Bodies`, group `body_keeper`).
  `SoldierVisual` counts the seconds since its soldier fell (`body_after` 3 s: the fall takes
  0.55 s, the pose settles in ~1 s) and then calls `BodyKeeper.take(self)`: the Visual node is
  re-parented from the Enemy to `Bodies` (keeping its place) and `become_body()` makes it a plain
  picture – `_process` off, footstep player and breath freed, no shadow, `visibility_range_end`
  170 m. The Enemy node is removed by the host as before (`corpse_time`, now 6 s; `_remove_dead`
  hands the body over first if that has not happened yet).
- So nothing else changed: bodies are NOT in the `enemies` group, have no collision, no nav
  agent and no network sync. Every computer keeps the bodies it saw fall (a late joiner sees
  none from before). Without a BodyKeeper in the scene (some tests, the benchmark) a body goes
  with its soldier node after `corpse_time`, as before.
- `Enemy._update_visuals()` leaves a kept body alone (`visual.is_body`) – a late synced pose
  change must not start the fall tween on a node that now lives under `Bodies`.
- The corpse timer and the body clock both stop while the game is paused
  (`create_timer(corpse_time, false)`): before, a pause right after a kill let the soldier node go
  while the body was not handed over yet.
- A soldier killed in the air (jumping into the trench) used to hang there until he vanished:
  `BodyKeeper._drop_to_ground()` (a ray down on the world layer) brings the body down.
- Limits: `Settings.PRESETS[...].max_bodies` 24 / 24 / 36 (V10c; was 12 on Low; re-checked on
  `Settings.changed`). One body too many: the oldest sinks into the snow (`sink_time` 3 s,
  `sink_depth` 0.7 m), then freed. A baked one first leaves his batch and gets his own plain
  MeshInstance3D "Sinking" for those 3 s (`_show_alone`).
- New day: `BodyKeeper` polls the day screen (`is_black()`, 2×/s, like the tank wrecks). At the
  moment it turns black `new_day()` frees all but the newest `keep_overnight` (24, V10c; was 12) and adds
  `overnight_snow` (0.3, at most 0.9 in all) to the rest: `SoldierVisual.set_snow_cover()` →
  `soldier.gdshader` uniform `snow_cover` (snow on the parts that face up, in patches from
  snow_mask.png). A retry / Continue reloads the scene: no bodies.
- Cost measured (xvfb, High): one body = 1 draw call and ~780 triangles (a living soldier with
  shadows: ~2.6 draw calls, ~2 200 triangles). 36 bodies all in view = +36 draw calls, +28 000
  triangles. With shadows on (`cast_shadows`) it would be up to +95 draw calls – that is why they
  are off. V10c did the "bake and merge" (below).
- **V10c baked batches.** `take()` → `_bake()` (after the drop, if he was killed in the air):
  `SoldierVisual.bake_body()` freezes the pose with `bake_mesh_from_current_skeleton_pose()` (headless,
  without a renderer, that fails – then `_pose_on_cpu()` does the same skinning in GDScript, ~1.4 ms;
  both give the same shape to 0.01 mm), drops indices (`SurfaceTool.deindex`, so arrays can just be
  appended), puts the coat tint into the vertex colours, keeps positions/normals/colours/UV in the
  body node's space in `baked`, and frees the Skeleton. The node stays as a light, empty Node3D (so
  `get_bodies()`, snow cover, sinking keep working). The keeper puts him into the nearest `Batch` with
  room (`batch_size` 6, first body within `batch_radius_m` 35 m) or a new one; `_rebuild()` joins
  the arrays (native `append_array`, transform with `Transform3D * PackedVector3Array`) – only the
  batch that changed. Snow per body goes into UV2.x; `soldier.gdshader` uses it when the batch
  material has `baked_snow` = true. Batches: no shadow, `visibility_range_end` 170 + 17.5 m (from the
  batch's middle). New day: all batches rebuilt behind the black screen.
- Seen while measuring (not caused by V10b): looking south from a firing position on High the
  frame is already ~260 draw calls and ~450k triangles with nobody on the field – above the
  README's budget numbers, which are averages from the benchmark flight.

## Finnish soldier body for the other players (NET2b) – how it is built
- `FinnMesh` (`scripts/player/finn_mesh.gd`) builds the mesh with SoldierMesh's helpers on the same
  skeleton (`SoldierMesh.Bone`); `get_mesh(FinnMesh.Gun.MOSIN / SUOMI)` is cached. Grip / fore-end
  points and muzzles per gun: `grip_for`, `fore_for`, `muzzle_for`. Grime: `_grime()` through
  `SoldierMesh.use_color_fn` (only cloth with alpha > 0.75), `DIRT_STRENGTH` 0.5.
- `PlayerBody` (`scripts/player/player_body.gd`, Player child `Body`, made in `Player._ready`):
  `visible` only when the player is not this computer's (`force_visible` for shots), `_process` off
  when hidden. Poses like SoldierVisual (smoothed bone targets, `pose_speed`), hands by `Hands` enum;
  `muzzle` Marker3D on a BoneAttachment3D (gun bone); `play_fire()` kick; the Molotov bottle is a
  small CylinderMesh on the right forearm. Fall: tween on the Body node from `hash(player.name)`.
- `SoldierMesh.reach(skeleton, upper, fore, target, pole)` = the shared two-bone arm IK (targets in
  chest = spine space). SoldierVisual._reach calls it.

