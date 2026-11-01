# Soldiers, effects, sound (P2), background sounds

Moved from CLAUDE.md (2026-11-01). Read when working on this area; keep it up to date.

## Effects, sound, soldiers (P2) – how it is built
- Soldier = `SoldierVisual` (Enemy's `Visual`): builds a Skeleton3D (12 bones, `SoldierMesh.Bone`)
  and one shared skinned ArrayMesh (`SoldierMesh.get_mesh()`, ~780 tris, vertex colours; alpha =
  cloth type for `soldier.gdshader`). Poses are set in code every frame from synced state
  (position delta → walk speed, `state`, `is_kneeling`); arms use 2-bone IK to grip the rifle.
  Muzzle = BoneAttachment3D on the rifle bone (`visual.muzzle`; it lags the bone by one frame).
  Per-soldier material copy (coat tint) and size. Death fall direction comes from `hash(name)`
  so all computers agree. Enemy RPCs: `show_shot_effects`, `show_hit` (flinch),
  `bullet_passed` (sent only to the peer whose head the bullet passed within 3 m).
- `ImpactEffects` pools: holes, sprays per surface (snow/wood/cloth), smoke, flashes, crack
  sounds. `make_smoke_emitter()` / `make_soft_texture()` are static (Maxim, breath reuse them).
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
