# Weapons, Maxim, first-person arms (W1, W2, W3)

Moved from CLAUDE.md (2026-11-01). Read when working on this area; keep it up to date.

## Weapons (W1) – how it is built
- Downloads (Sketchfab glTF zips) stay in `assets_source/` (git-ignored); `tools/import_weapons.py`
  writes `assets/models/weapons/<name>/model.gltf` + textures shrunk to ≤1024 px.
  All three models are CC-BY 4.0 → `CREDITS.md` (shown in the main menu via the builder).
- View models: `_place_gun_mesh()` in the builder puts the glTF under `Model/Mesh`, turned and
  scaled so the model's rear sight lands on `AimPoint` (Mosin model points +z → yaw PI, scale
  0.774; Suomi is in cm → 0.0094). `ViewModel` gathers `bolt_part_names` into a Bolt node and
  hides `hidden_part_names` at runtime (names from the glTF). Per-gun `hip_offset`.
- Maxim = `MountedGun` (StaticBody3D, group `mounted_guns`): host owns `user_id`, `ammo`,
  `is_reloading` (GunSync). `Player.mounted_gun_path` (StateSync) links player → gun; host
  pins the player to `SeatPoint` and handles F (`request_interact`/`consume_interact`).
  `WeaponController` routes trigger/ammo/reload to the gun while mounted; the host's bullet
  logic is shared: `WeaponController.resolve_shot()`. `PlayerInput.add_look()` clamps the view
  with `MountedGun.clamp_look()` (left/right traverse separate). Turning model parts are
  reparented under `Pivot` at runtime (`turning_part_names`); the glTF animation is unused.
- Maxim placement: barrel at y 0.2 in the 0.5 m firing slit (y 0.1–0.6, made taller in W1),
  gun at x = 0 behind the funnel hole of the front wall (L2; pivot 0.6 m behind the outer face, muzzle flush with the hole). Limits ±21°,
  -7°…+4°: `test_w1.gd` checks every allowed aim fits through the slit.

## Arms and Maxim polish (W2) – how it is built
- `FirstPersonArms` (Camera3D/Arms, `process_priority = 100` so it runs after the guns moved):
  6 root bones (upper arm, forearm, hand × 2), one skinned mesh built with SoldierMesh's public
  helpers (`begin_build/use_bone/frustum/sphere/finish_build`), soldier shader. Rest pose =
  arms hanging down, so the MeshInstance needs a `custom_aabb` (else culled when raised).
  IK: hand bone = grip marker basis; wrist = marker − basis·`PALM_CONTACT`; elbow by law of
  cosines; bend direction from `elbow_pole_right` with `bend.z >= 0` (an elbow swinging forward
  folds the arm up in front of the eye when aiming). Out of reach → the shoulder moves forward.
  Separate shoulders: right high/back (at the butt), left low (arm comes up from below).
- Grip markers (`_grip()` in the builder): marker axes are hand axes – fingers along −Y, palm
  along −X (right hand) / +X (left), thumb side −Z. `WeaponController.get_hand_grips()` returns
  [right, left] global transforms (view model or mounted gun). ViewModel blends the right hand
  to `BoltGrip` (re-parented into the runtime Bolt node) with `bolt_hand`, and one hand to the
  pouch with `reload_hand` (`reload_with_right_hand`). MountedGun blends the right hand to
  `BeltGrip` during a new belt.
- Hand-weapon grip lessons: fingers of the right hand point forward-DOWN (thumb over the top);
  pointing them up put the mitten right in front of the eye when aiming.
- Maxim: turning parts now go under a `TurnPivot` INSIDE the glTF (same units as the parts),
  which copies `Pivot` every frame (`pivot.global_transform * _turn_offset`). The glTF animation
  is duplicated, its tracks re-pointed to the moved parts, position keys shifted by
  `TurnPivot.position`, the model's own library REMOVED (otherwise AnimationMixer warns about
  unresolved tracks), and it plays once per shot (`speed_scale = length / shot interval`).
- Heat (host, synced on GunSync with `delta_interval = 0.1`): +`heat_per_shot` per round,
  cooling `heat * cooling_rate` per second (×0.4 while firing), overheated at 1.0 until
  `overheat_recover_heat`. Steam (`make_steam_emitter`, web_fallback) + `steam_hiss.wav` loop
  above `steam_heat`. Owner side: `_can_fire_now` never fires while overheated (click instead).
- Mounted ADS moves the CAMERA to `Pivot/SightEye` (camera.position in Head space × aim
  amount); `_update_view` resets it to zero off the gun.
- Suomi drum (owner's wish: the left hand went through the drum): `GripL` is UNDER the drum (palm up
  on its rim). `ViewModel.magazine_part_name` ("SuomiKP31_Drum") moves the part into a runtime
  `Model/Magazine` node at its centre. Reload = `magazine_progress` 0..1 (tween_method over the
  reload time; key times `MAG_STEPS`): pull down `magazine_pull_m` with the hand → drop (a
  RigidBody3D copy, layer 0 / mask 1, local only, max 4, freed after 15 s) → pouch → new drum
  comes back with the hand → pushed in. The left hand comes from `_left_hand_on_magazine()` (Model
  space) so hand and drum always agree. Per-gun `reload_offset` / `reload_rotation_deg` (Suomi
  lifts and rolls the gun −60° so the change is in view). `tools/shots_drum.gd`, checks in test_w2.
- `tools/shots_w2.gd [prefix] [side]` (the "side" option adds a camera beside the player to
  check the grips), `tools/test_w2.gd`.

## Mosin bolt cycle (after each shot)
- `ViewModel.play_bolt_cycle()`: handle rolls up (`bolt_roll_deg` 80°, around the bolt axis
  `bolt_roll_pivot`, measured from the glTF parts), bolt slides back `bolt_travel`, forward, handle
  rolls down. Right hand rides on `BoltGrip`. Timings are fractions of `bolt_cycle_time` (1.25 s),
  matched to the clicks of `assets/audio/recorded/bolt_mosin.ogg` (0.78 s, cut from
  `assets_source/370345…mosin-nagant-bolt-action-cycle.wav` at 13.38 s; the sound starts at 25 % of the cycle).

## Suomi cocking handle and cases (W3, W3b)
- Open bolt, non-reciprocating handle: the bolt is NOT animated (owner: not visible), and the
  handle (`SuomiKP31_Handle`, the lever under the rear of the receiver) never moves when firing.
- WHEN it is cocked (owner, W3b): first time the gun is taken out in each life (also after a
  respawn), and a reload of an EMPTY drum. A tactical reload (rounds left) does not cock and is
  exactly the W2 drum change. `ViewModel.is_cocked` (false for a fresh gun, set true at the snap,
  false again on respawn – WeaponController `_was_dead`); `needs_cocking()`.
  `WeaponController._raise_current()` raises + cocks and blocks firing for `cock_time()`;
  no aiming while `is_cocking`. `_set_is_reloading` passes `cock = mag empty or not cocked`.
- `ViewModel.cocking_handle_part_name` moves the part into a runtime `Model/CockingHandle` node;
  `BoltGrip` (the knob) is re-parented onto it, so the right hand (`bolt_hand`) rides along.
  `_add_cocking(start)` adds to the parallel tween (times in seconds, `COCK_*`): the gun turns
  to `cock_offset` / `cock_rotation_deg` in `COCK_POSE_TIME` so the handle is in view, the hand
  goes to the knob, the handle is pulled back `cocking_travel` (0.045 m – limited by the slot
  under the end cap in this model; ease-out), let go at `COCK_RELEASE_AT`, snaps forward in 0.06 s
  (ease-in), a small knock (`_cock_knock`, sets `is_cocked`), hand and gun back to rest
  (`COCK_END` ≈ 0.96 s after `start`, plus the 0.25 s pose = `cock_time()` ≈ 1.2 s). In an empty
  reload the cocking ends just before the reload time and the drum change runs a little faster
  (`mag_time`) so the drum is in before the gun turns. `_restart_tween()` resets the handle.
- Sound: `assets/audio/recorded/cock_suomi.ogg` (0.48 s, cut from freesound 676588 "Colt SMG -
  Firing, Handling" by hyperix6, CC0, 0.47–0.95 s of the file: scrape, clack, rattle; the rattle
  ×2.5 louder; its gunshot at 1.10 s is NOT used). `WeaponData.get_cock_sound()` →
  `cock_<recording_name>…`. The ViewModel emits `cock_sound_cue` so the clack
  (`COCK_SOUND_CLACK_AT` 0.12 s in) lands when the handle is fully back – the rattle then falls on
  the snap forward. WeaponController plays it on its own `CockAudio` player (never cuts a reload
  sound), only for the player on this computer.
- Empty cases: `eject_case_part_name` ("9mm_Case", still hidden on the gun; the bullet child is
  removed from the copy) → a pool of `CASE_POOL_SIZE` (12) holders made once at start and reused
  round-robin. They fly in the space of the WeaponHolder (camera-fixed; `_case_xform`), NOT the
  world (W3b: in world space walking right made them fly left, and jumping bent their arc).
  `play_fire()` throws the next one out of `Model/EjectionPort` (right side, in front of the drum)
  to the right, a little up and back, spinning; plain maths in `_process` (gravity = view's down),
  hidden after `CASE_LIFETIME` 0.5 s. No physics bodies, no particles (so no web_fallback).
  Local only, like the rest of the view model.
- Tests in `test_w2.gd` (W3 blocks: first equip, cases while moving, tactical vs empty reload,
  respawn); screenshots `tools/shots_w3.gd [prefix]` (reload frozen at several moments of the
  cocking, cases in the air – also while running right; each also from the side).
