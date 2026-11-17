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

## Arms: winter clothing (AR1)
- Plan + owner decisions for AR1–AR6: project doc `claude/plan-arms-winter-clothing.md`.
- Mesh (`FirstPersonArms._build_mesh`, still ONE skinned surface, 6 bones, ~6300 triangles):
  sleeves are `_tube()`s – rings of points whose radius comes from a shape function (folds =
  sums of sines; per-arm phases so left and right differ), normals from the neighbouring points.
  Upper arm 12×18, forearm 20×22. The fold terms fade out at the tube ends so the ends match the
  round elbow spheres (one on EACH bone – a sharply bent elbow showed an open tube otherwise).
  Sleeve end = a hem turned in towards the tunic (`SMOCK_INSIDE`). Mitten: ribbed knitted cuff
  (`_tube`, 18 ribs) with a closed rolled top, bigger pouch; `PALM_CONTACT.x` −0.027 → −0.03.
- Colours: alpha = cloth code for `fp_arms.gdshader` (0.5 smock, 0.65 tunic, 0.8 mitten).
  `_bake_wear()` paints dirt/snow into the vertex colours once (rest pose): sleeve underside
  (`UNDERSIDE`, per arm, in bone space – MEASURED from the hip/ADS poses of both guns; if AR2
  changes how the sleeves roll, measure again), elbows, cuff edge; faint snow patches on the top
  side; mitten palms, fingertips, oily trigger finger + thumb tip.
- Shader `resources/shaders/fp_arms.gdshader` (the soldier shader is untouched): `cull_disabled`
  (open cuffs show their shaded inside, never a paper-thin edge; back faces ×0.45), grain from
  `snow_mask.png` b channel (fine for the smock, coarser two-size mix for wool), broad variation
  from r; roughness 0.9–0.97, specular 0.1–0.2. Warmed up by `ShaderWarmup` like before (the
  arms are drawn while the view models are shown behind the cover).
- AR1b thumbs + wrist: bones 6/7 = `ThumbL`/`ThumbR` (root bones like the rest), hinged at
  `THUMB_BASE` (hand space, x mirrored for the left). `ViewModel.thumb_right_deg` /
  `thumb_left_deg` (Euler, Godot's YXZ order, hand space: x lifts the thumb from along the
  fingers towards the thumb side, y swings it to/away from the palm, z for the left hand swings
  it towards the palm). `get_thumb_turns()` relaxes a thumb back to the built pose while its
  hand is off the grip (bolt, cocking knob, pouch, drum change); Maxim + bottle: built pose.
  Values: Mosin left (0, −30, 50) = up along the fore-end's left side; Suomi right (64, 58, 15) =
  straight across the gun (hinge and tip both at z ≈ 0.123) over the stock top, right against the
  back of the receiver's end cap (z ≤ 0.105) and just behind the cocking handle (z ≤ 0.095, knob
  at x 0.05) – owner 17 Nov: "straight across the gun, not bent towards the shooter, closer to
  the cocking handle" (first try 100, 62, 0 leaned 3.4 cm back). It can't go further forward:
  the cap is in the way. Found by measuring the glTF parts (AABBs / a slice of the
  triangles at one z) – the Mosin's fore-end wood starts at y 0.014 at z −0.27, so GripL went
  from y −0.012 (palm 2.6 cm below the wood) to 0.015.
- Wrist: the tunic cuff and the mitten's knitted cuff use `SoldierMesh.use_bone_fn()` – weight
  forearm → hand from `WRIST_BLEND_TOP` (6 cm above the wrist) to `WRIST_BLEND_BOTTOM` (2 cm
  below), smoothstep. Both layers share the same weights at the same height, so the grey sleeve
  stays inside the mitten cuff (tunic tapers to r 0.034 inside it). The smock sleeve and the
  mitten hand are still 100 % one bone (AR2: elbow blend, twist spread).
- Tests (`test_w2.gd`): Mosin left thumb tip up beside the fore-end; Suomi right thumb behind the
  cap/handle and crossing over the stock.

## Arms: bending and the trigger finger (AR2)
- Elbow: the upper-arm tube, both elbow spheres and the forearm tube use one blend function –
  weight upper → forearm over `ELBOW_BLEND` (3.5 cm) above → below the elbow point.
  `_bake_wear` takes the bone with the bigger weight.
- Twist spread (`_solve_arm`): upper arm rolled towards the elbow's bend (`bend * sgn`, so the
  left arm's hint points the same way as its palm-up hand), forearm half-way
  (`upper.x + hand.x`), the wrist cuffs blend the rest. `UNDERSIDE` was measured again and is
  now per bone [L upper, L fore, R upper, R fore] – measure again if the twist changes.
- Trigger finger: bone 8 `IndexR` (right mitten only; the left index stays on the hand bone),
  hinged at `INDEX_BASE`. `ViewModel.index_outside_deg` / `index_trigger_deg` per gun (Euler,
  hand space); `WeaponController.trigger_finger` (local picture only, moved at 6/s towards
  `_trigger_finger_target()`): 0 outside the guard (reloading, sprinting, bandaging, climbing,
  raising the gun incl. Suomi cocking), 0.6 resting on the guard (hip), 1 on the trigger (aiming,
  firing, 0.6 s after a shot), 1.15 for 0.08 s after a shot (the squeeze). On a bolt / cocking
  knob (`bolt_hand`) it curls to `ViewModel.INDEX_KNOB_DEG`.
  Values from the model's trigger + guard shapes (side cut through x ≈ 0): Mosin blade front
  z ≈ 0.115, guard z 0.085–0.147, bottom y −0.045; Suomi blade z 0.017–0.027, guard z
  −0.007–0.04. Mosin (18, −6, 36) / (−9, 0, 6); Suomi (30, −3, 30) / (9, 3, 3). The Suomi hand
  sits far back (for the thumb, AR1b), so its finger only reaches the blade's back edge (5 cm
  finger, 6.6 cm to the front) – seen from the side it looks right.
- `WeaponController.get_finger_turns()` → [right thumb, left thumb, right index] (replaces
  AR1b's `get_thumb_turns`). Maxim: both thumbs press its trigger while firing –
  `MountedGun.thumb_press_right_deg` / `_left_deg` (−10, 0, ∓25), blended by `trigger_finger`.
- No mitten "compression" (bone scale) – not needed in the close-ups.
- Tests (`test_w2.gd`): finger 0.6 at the hip / 1 aiming / 0 sprinting, tip within 2 cm of the
  trigger when aiming, >100 elbow vertices shared, forearm roll between upper arm and hand,
  Maxim thumbs press while firing.

## Arms: hand positions (AR3)
- Mosin `BoltGrip`: palm down towards the rifle, fingers forward over the knob (was the firing
  grip's angle). `ViewModel._hand_to_knob()`: on the knob the hand turns only
  `bolt_hand_roll_share` (Mosin 0.35 → 28° of the handle's 80°; its turn before the handle moves
  is `_bolt_grip_rest`, saved in `_ready` before BoltGrip is re-parented into the Bolt node);
  on the way it follows a curve bowed out by `bolt_hand_lift` (Mosin (0.03, 0.03, 0) Model
  space = up and out, over the receiver). Suomi: share 1, no lift (the cocking handle slides,
  it doesn't turn).
- Suomi `GripL` (owner: "the left hand keeps the gun up when aimed and pulls it slightly back to
  the shooter"): stays on the drum; palm on the drum's FRONT-lower edge – z −0.163 (drum
  −0.17 … −0.121, centre z −0.145), 0.081 from the drum's axis (r 0.077), palm tilted back
  towards the shooter (palm (0.3, 1, 0.45)). Wrist 37°. The drum change starts/ends there.
- Right wrists measured (forearm ↔ hand): Mosin 75°, Suomi 59°. The right forearm comes up
  steeply from the fixed shoulder below the gun; straightening the hand was tried (Suomi 36–44°)
  but then the thumb (owner-approved) moves back and the trigger finger loses 1–2 cm of reach –
  NOT done. The cure would be the shoulder position, which is out of scope (owner's brief).
- Tests (`test_w2.gd`, AR3): hand turn on the knob 15–40°, palm stays on the knob, curve up and
  out at half-way, the palm never inside the receiver box on the way, left palm on the drum's
  front-lower edge, left wrist < 45°.
  Old, not AR1: on the Suomi the right upper arm passes the camera's near plane at the screen edge.
- Daylight screenshots: `MatchDirector.test_start_wave = 4` before loading the game, with the
  enemies / air raid / artillery disabled (battle 1 is night – colours can't be judged there).

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

## Hit zones (D9)
- `WeaponController.resolve_shot` (host): if the bullet hit an `Enemy`, `hit_zone_at()` gives
  `Enemy.HitZone` (BODY / HEAD / LEGS) and `zone_damage_multiplier()` scales the damage (after the
  distance falloff). Numbers per enemy type: `EnemyData` → Combat → head 4, legs 0.6.
- Zone limits are constants at "damage & death" in `enemy.gd` (`HEAD_LENGTH`, `LEGS_STANDING`,
  `LEGS_KNEELING`, `LEGS_PRONE`). They follow the capsule sizes in `_update_visuals()` (1.8 / 1.2 m,
  prone 1.7 m lying along the body) – change both together.
- Result with 100 health: Mosin / Maxim – head and body kill, legs 60. Suomi – head kills (to 60 m,
  less with falloff), body 25, legs 15. Beyond 400 m the Mosin's falloff already left a body hit
  short of a kill before D9; a head shot now kills at any range.
- Signal `hit_confirmed(killed, zone)`: anything listening must take both arguments.
- Not zoned: `take_damage()` called directly (fire, shells, bombs), the tank, the target dummy,
  and damage to players.
