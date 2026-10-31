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
- **Privacy:** never write the owner's real name, e-mail or other personal details into any
  project file, comment, commit message or build. Commits in this repo use the pseudonym
  `WonderPepe` (repo-local git config). The public version is published under a pseudonym.
- Total beginner with coding and with Godot: explain important concepts briefly, in plain words.
- Before writing code for a milestone: show a short plan + node tree and **wait for approval**.
- Work in milestones; stop after each so he can test in Godot. Give exact test steps.
- After each milestone: make a git commit with a clear message. He pushes with GitHub Desktop
  ("Push origin"). Check `git status` before writing files – never overwrite his own edits.
- If something can't be done well in the web export, say so and suggest an alternative.

## Starting a new chat (how Claude sessions work on this project)
- Each milestone gets its own chat. The owner connects this folder and says what to do;
  this file is the memory between chats – keep it up to date at the end of every milestone.
- Setup used so far (Cowork, cloud workspace + the owner's computer):
  - Godot 4.7.2 Linux binary (official release) + Web export templates in
	`~/.local/share/godot/export_templates/4.7.2.stable/`; xvfb for screenshots / GL tests;
	Python Playwright (Chromium, SwiftShader) for `tools/web_smoke_test.py`.
  - Work on a copy of the project in the cloud workspace (run the builder, tests, exports there),
	then deliver changed files as a zip → copy into the folder → unzip → `git status`.
  - Scene files rebuilt by `build_scenes.gd` get new random `unique_id`s: restore files whose only
	change is `unique_id` lines (`git show HEAD:file > file`) – but NEVER binary files
	(`git diff --numstat` shows `-`), or the new baked meshes / navmesh are lost.
  - Commit on the owner's computer (repo-local git identity `WonderPepe`); the owner pushes with
    GitHub Desktop. Releases: see RELEASES.md (only when the owner asks for one).
  - Fastest way to get the project into the cloud: `git bundle create "Claude outputs/repo.bundle"
    --all` on the owner's computer → stage it → `git clone` it in the cloud. Godot 4.7.2 + export
    templates download from github.com/godotengine/godot/releases (4.7.2-stable). freesound.org
    is NOT reachable from the cloud workspace – the owner downloads sounds into `assets_source/`.
  - Git in the owner's folder needs delete permission (git removes its own .lock / tmp_obj files):
    ask for it once per chat (device_request_delete_permission) before committing, otherwise a
    `.git/HEAD.lock` is left behind and the next git command fails. `git fsck` there reports
    "unable to mmap … Invalid argument" – a quirk of the folder mount, the objects are fine.
  - Commits made in the cloud copy are scratch only (never pushed). A stop hook may ask to re-author
    them as "Claude" – don't: the repo's commits use the owner's pseudonym `WonderPepe` (owner's
    privacy rule above).
  - Clean up your own temporary files in `Claude outputs/` (bundles, staged copies) at the end.

## Milestones
- [x] M1 project setup, input map, test level, player movement
- [x] M2 weapons and shooting
- [x] M3 enemy AI (state machine) and wave spawner
- [x] M4 HUD, death/respawn (5 s), main menu (Single Player; greyed-out Host/Join Co-op), pause menu
- [x] M5 web export test and performance check (Settings menu, benchmark, baked CSG)
- [x] P1 graphics: clear freezing day (sky shader, snow shader, log walls, spruce LOD forest, tree line)
- [x] W1 weapons: imported Mosin/Suomi view models, Maxim M/09-21 mounted in the bunker (F),
  CREDITS.md + Credits menu. Lahti-Saloranta left out (no usable model; the owner's choice) –
  weapon slot 3 is free for it.
- [x] P2 effects, sound, soldiers (skinned code-built soldier, code animation, sprays/smoke/breath/
  drift, audio buses, ambience, footsteps, bullet cracks, damage indicator, hit flinch).
- [x] W2 arms + Maxim polish (first-person arms with snow-camo sleeves and mittens on grip
  markers, closer ADS, Maxim sights / belt-feed animation / heat, steam, overheating).
- [x] G1 a real battle (MatchDirector win/lose, ASSAULT into the trench, ammo crates, bandages,
  dusk, end screen, Easy/Normal/Hard).
- [x] Release v0.1.0: first playable browser version, GitHub Pages from `docs/` on main
  (https://wonderpepe.github.io/WinterWar/). See RELEASES.md: version in setup_project.gd, copy
  export/web into docs/ (keep .nojekyll + .gdignore), zip in git-ignored releases/, git tag per
  release. Only replace docs/ when the owner wants a new public release.
- [x] v0.1.1: loading screen (`ui/loading_screen.tscn`, `LoadingScreen.go(tree, scene)`):
  threaded load request + progress bar, then instantiates the game itself, stays on top
  (CanvasLayer 60, PROCESS_MODE_ALWAYS) until `ShaderWarmup` (group `shader_warmup`, `progress`)
  is done. Menu, benchmark and "Play again" go through it; tests wait for `current_scene`.
- [x] v0.1.2: in the browser the mouse can only be locked after a click, so the loading screen
  ends with "CLICK TO START THE BATTLE" (pauses single player, locks the mouse in `_input` on the
  click) instead of the old paused pause menu. PauseMenu stays closed while `LoadingScreen` exists.
  Benchmark: `LoadingScreen.go(tree, scene, false)` (no click).
- [x] G2 "pressure" (owner chose parts 1, 3, 4 of the plan): enemy suppression + prone, officer
  with whistle, DP-27 MG teams, wave composition list (needed to send officers/MG teams).
  Artillery was dropped by the owner. Field cover (rocks, wire, craters, cover points) was
  skipped for now – still open, see development ideas.
- [x] Front reports: after each cleared wave the owner's Finnish front report for that day
  (21.12.1939 … 28.12.1939, then 31.12.1939 and 01.01.1940 for Hard's waves 9–10; in order,
  wave n → report n) – now shown on the day screen (see below); the victory screen shows the
  report of the last day held. Texts are the owner's own – never reword them.
- [x] v0.1.3 aiming fixes (players: "ADS ends for a moment and comes back"), merged by hand later:
  Maxim new belt no longer ends ADS (hand-weapon reloads only); Maxim ADS camera follows only
  `sight_kick_share` 0.25 of the recoil push (`MountedGun.get_sight_eye_position()`); recoil
  recovery brings back only the applied kick (no downward drag at the elevation limit). The aimed
  Mosin bolt-cycle change (hand below the knob, 6° tilt) was REVERTED on the owner's request –
  the bolt cycle is the original one (−20° tilt, hand on the knob) whether aiming or not.
- [x] Day screen ("a new day" after each wave, owner's design): "WAVE n COMPLETED" banner over the
  battlefield first (`intro_delay` 2.5 s), then black screen, SA-kuva photo as an
  old print, Finnish date title, the telegram types out, optional radio static for 5 s, Space /
  Enter continues. Front reports are ALWAYS shown now (the Settings switch was removed – owner).
  Owner's choices: same lighting as before (dusk over the whole battle; weather/day-night later),
  no spoken voice for now (later: the owner may record one sentence per day himself).
  Day-screen texts are Finnish ("PÄIVÄ n", "22. joulukuuta 1939", "[Välilyönti] Jatka",
  "Kuva: SA-kuva"); the in-game HUD stays English ("WAVE n COMPLETED").
  Radio static: recommended CC0 Freesound 199438 "Radio Fuzz for Old Radio Broadcast"
  (martinimeniscus) – the cloud workspace can't reach freesound.org, so the owner downloads it
  into `assets_source/`; then trim/convert it to `assets/audio/recorded/radio_static.ogg`.

## Development ideas (not yet approved)
0. G2 leftovers: field cover (granite rocks / anti-tank rocks, old shell craters in
   TerrainGenerator heights, barbed-wire belts with gaps via NavigationObstacle3D carving, cover
   points that soldiers bound between); MG fire suppressing the player (screen effect).
1. (done in W2) Maxim sights/belt/heat. Still open: better Maxim sound, water can + hose.
2. (done in W2) First-person arms. Still open: arms for co-op players' third-person bodies
   (players are capsules now), a Mosin reload that really moves the stripper clip (the Suomi
   drum change is done).
3. Real Summa terrain from the owner's maps + Copernicus DEM; real trench line, the big concrete
   bunkers (e.g. Sj5 "Millionaire"), anti-tank rocks, barbed wire, shell craters.
4. Soviet attack variety: tanks (T-26/T-28) with infantry behind them, artillery barrages
   (craters, camera shake), enemies using cover, grenades, smoke screens, officers.
5. Player options: Molotov cocktails / satchel charges against tanks, grenades, bandages,
   ammo crate in the trench, a firing step, prone, leaning.
6. Game structure: hold for N waves → victory/defeat screen, difficulty levels, short winter day
   turning to dusk/night with flares, scores.
7. Finnish comrades: AI riflemen in the trench (later replaced by co-op players).
8. Co-op over WebRTC (needs a small signaling server) with a lobby code.
9. Real sound recordings (CC0) to replace the generated ones; shouts; menu music.
10. Options: field of view, key rebinding, gamepad.
11. Lahti-Saloranta (slot 3) if a usable model turns up, or built from shapes.

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
  `enemy_spawn`, `attack_point`, `deep_snow`, `navigation_source`, `match_director`, `ammo_crates`,
  `trench_entry`.
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
- Measured budget (High, after P1): ~190 draw calls (260 max), ~255k triangles/frame, CPU scripts
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
- Forest LOD is decided **per tree in the spruce shader** (dithered cross-fade over
  `fade_band` m), not per chunk – whole 50 m chunks switching at once looked like random
  popping. `ForestScatter._process` passes the camera position (`lod_camera`) to its own copies
  of the tree materials (near = `lod_mode` 0, far = 1); shadow pass can't use the shader's camera.
  Chunk visibility ranges are only coarse culling, widened by the chunk radius.
  Per chunk: `Near0_*`/`Near1_*` (detailed; neighbouring chunks alternate the two shapes, one
  draw call each), `Shadow_*` (simple tree, shadows only, near range), `Far_*` (simple tree, no
  shadows – sun shadows end before it starts). `TreeLine` ring (radius 330/520 m).
  Trunk material is the same shader with `trunk = true` (bark texture).
  Per-tree values go in the MultiMesh **instance colour** (B = snow, A = tint); spruce vertex
  colour R = can hold snow, G = AO, B/A = 1; UV.x = 0 at trunk … 1 at branch tips.
  Tree *look* uses its own RNG so positions (and the baked navmesh) stay unchanged.
- Quality presets also set `tree_detail_distance` (35/50/70 m).
- Benchmark turns V-Sync off on desktop (else FPS is capped at the monitor rate). Godot's
  TIME_PROCESS includes CPU-side rendering, so the benchmark shows physics time only.

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
  gun at x = -1.0 so the bunker entrance stays free (test_m1 crouch test). Limits 14° L / 40° R,
  -7°…+4°: `test_w1.gd` checks every allowed aim fits through the slit.

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

## The battle (G1) – how it is built
- `MatchDirector` (Game/MatchDirector, group `match_director`, synced by MatchSync with
  `delta_interval = 0.25`): host applies `DifficultyData` (`Settings.difficulty`, chosen in the
  main menu) to WaveSpawner (`base_enemies`, `enemies_added_per_wave`, `max_waves`),
  `Game.respawn_time` and `Enemy.spread_multiplier` (static). Counts living enemies with
  `is_in_trench()` (y < -0.85 and z > 48) 4×/s → `in_trench`; ≥ `trench_limit` → DEFEAT.
  `wave_cleared(n)` → heal all players, n ≥ `waves_to_win` → VICTORY. `end_match()` stops the
  spawner (`active = false`) and `freeze()`s enemies. HUD opens `EndScreen` when `is_over()`;
  single player pauses the tree; PauseMenu stays closed while the match is over.
  The benchmark disables the director (`set_process(false)`, `max_waves = 0`, spread 1.0).
- Enemy `State.ASSAULT` (added at the END of the enum – it is synced as a number): PATROL/ALERT/
  ATTACK at the attack point → `_hold_at_goal()` for `assault_hold_min…max` s → `_begin_assault()`
  picks the nearest `trench_entry` NavigationLink3D (one per zigzag leg, ground → floor, one-way;
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
- `DuskLight` (Game/Dusk) duplicates the Environment, Sky and sky ShaderMaterial at start
  (never edit the saved resources at runtime – they are cached across "Play again"), then lerps
  sun pitch/yaw/colour/energy, ambient, fog colour and sky colours by `waves_cleared/waves_to_win`,
  `transition_time` s per wave, only re-applying when it changed > 0.004 (sky re-draws are costly).
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
  helper is a rifleman scene). Gun goal = attack point − `mg_position_back_m` (35 m) in z. Gunner
  `_deploy()`s at his goal or when he sees a target ≤ `mg_deploy_range_m`; deployed → own branch
  `_mg_deployed()` in `_physics_process` (bursts `mg_burst_min…max` at `mg_shot_interval`, pause,
  47-round pan, reload 3.5 s helped / 6 s alone). Deploying moves the helper's attack point next to
  the gun; the helper lies down there (`_deployed`) and never assaults while the gunner lives;
  gunner dead → `_gunner_lost()` → helper goes to his `home_point` as a normal rifleman.
  Enemy smoke puffs at most every 0.25 s (bursts).
- Waves: `WaveData` (riflemen, officers, mg_teams); `DifficultyData.waves` (builder `WAVE_LISTS`);
  `MatchDirector` copies it to `WaveSpawner.wave_list` (empty = old riflemen formula; the
  benchmark empties it). `_make_groups()`: rifle groups, officers in the middle of groups, MG
  teams after every second group; a group only spawns when it fits under `max_alive`.
  WaveSync also syncs `wave_riflemen/officers/mg_teams`; the HUD banner shows `WaveData.describe()`.
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
- HUD `ArtilleryWarning` label (top centre): warning / "stay down" or "GET INTO THE TRENCH!" /
  "The barrage lifts". `tools/test_artillery.gd`, `tools/shots_artillery.gd`.
- Sound: Freesound 486086 "Artillery Barrage" by Mozfoo (explosion by Steveygos93), CC-BY 4.0;
  mono, −4 dB + limiter, 1.3 s fade. Original WAV in `assets_source/`.

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

## Front reports / day screen – how it is built
- `FrontReports` resource (`scripts/game/front_reports.gd`, `resources/front_reports.tres`, written
  by the builder from `FRONT_REPORTS` = [date, owner's text, photo file]): `dates`, `texts`,
  `photos` (res paths, `PackedStringArray()` defaults because of the export bug).
  `get_report(wave)` → [date, text] or empty; `get_photo(wave)` loads the photo on demand.
- Photos: `assets/photos/sa_kuva_*.jpg` (SA-kuva, CC BY 4.0, credited in CREDITS.md and on screen
  "Kuva: SA-kuva"), made from the owner's originals in `assets_source/` (≈5000 px) → greyscale,
  1280 px, JPG q86. Import: lossy WebP (`compress/mode=1`, quality 0.85), no mipmaps ≈ 150 kB each.
  Day → photo: 21.12 144612 (anti-tank rocks), 22.12 a_511 (captured tank), 23.12 144608,
  24.12 a_128 (dugout), 25.12 a_126, 26.12 a_125 (officers), 27.12 a_8 (trench, upright photo),
  28.12 a_123 (dark foxhole), 31.12 144607, 01.01 a_129. Spares: 144616, 144609, a_4, a_127.
- `DayScreen` (HUD/DayScreen, `scripts/ui/day_screen.gd`, built by `_build_day_screen()`): HUD
  `_update_day_screen()` watches the synced `MatchDirector.waves_cleared` (co-op clients too, no RPC)
  and calls `open(wave, reports)`; not after the last wave (end screen takes over, `close_now()`).
  Timeline: `_t` starts at −`intro_delay` (2.5 s: HUD wave banner "WAVE n COMPLETED", screen still
  clear, countdown already held; static starts at `_t` = 0), black 0–1 s, photo 1–2.2 s, title ~2 s, telegram types from `type_start` 3 s at
  `type_speed` 28/s, then `read_time` 7 s; photo zooms `zoom` 6 % over the screen; Space (jump) /
  Enter after `skip_after` 1.5 s; a new wave starting also closes it. Not paused: SFX + Ambience
  buses are ducked `duck_db` −20 dB (Ambience keeps Settings' formula). Host: `WaveSpawner.hold`
  stops the WAITING countdown while it is open. Static = `RecordedSounds "radio_static"` (silent
  if missing), clatter = `"telegraph"`. `Content` hangs from the screen centre (photo area centred
  at (−300, 30), telegram at (50, −140), 530 px wide).
- `resources/shaders/old_photo.gdshader` (canvas_item): warm grey tone, 18 fps film grain,
  vignette, flicker; writes `COLOR = vec4(g * tone, COLOR.a)`.
- Victory: `EndScreen.open(director, player, reports)` shows the last day's report.
- `tools/shots_reports.gd [days…]` (screenshots, xvfb), checks in `test_g2.gd`, `test_m3.gd`,
  `check_web_pack.gd`.

## Gotchas learned
- **Export bug:** `@export var x: PackedStringArray = []` loses the scene's values when the export
  converts scenes to binary (web build showed hidden Mosin parts, Maxim didn't turn). Use
  `= PackedStringArray()` as the default. Check exports with `tools/check_web_pack.gd`. The
  export also caches converted scenes in `.godot/exported/` – delete it if in doubt.
- **Particle colour bug:** CPUParticles3D colours (`vertex_color_use_as_albedo` + `color` /
  `color_ramp`) render BLACK in WebGL AND on the owner's Windows/AMD desktop (dark haze from breath and
  Maxim smoke). `ImpactEffects.web_fallback(p)` now ALWAYS turns them into a fixed material colour
  + shrink-away curve. Every new particle effect must call it; set strength via the material's
  `albedo_color.a`. (MultiMesh instance colours on the trees are fine.)
- Shader warm-up effects must be hidden afterwards (`ImpactEffects.hide_all()`), or the warm-up
  smoke hangs in front of the camera when the game starts.
- Editor re-imports: the owner's editor switched the imported weapon textures to VRAM compressed +
  mipmaps (normal maps as normal maps). Keep those `.import` files. The Web preset exports only
  desktop formats (`for_mobile=false`), otherwise the textures are stored twice.
- SurfaceTool: `set_skin_weight_count()` must be called BEFORE `begin()`.
- A child's `_ready()` runs before its parent's `@onready` variables are set (PlayerFX can't use
  `player.camera` in `_ready`; use the node path).
- CPUParticles3D `direction` is in the emitter's own space (rotated emitters: use local axes).
- Headless tests run frames very fast (tiny delta): wait with timers, not frame counts, when
  something is smoothed over time.
- A new `class_name` (e.g. `MountedGun`) or new audio files: run `godot --headless --import`
  once before the builder/tests, or scripts using the name fail to parse.
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
  `shots_p1.gd <prefix> [views]` (graphics screenshots, needs xvfb), `test_w1.gd`,
  `shots_w1.gd [prefix]` (weapons + Maxim screenshots), `test_w2.gd`, `shots_w2.gd`, `test_g1.gd`,
  `soak_g1.gd`, `shots_g1.gd`, `test_g2.gd`, `soak_g2.gd`, `shots_g2.gd`, `make_whistle.py`, `shots_reports.gd [days…]` (day screen: completed banner, title, typing, read), `test_background.gd`, `test_artillery.gd`, `shots_artillery.gd`, `shots_drum.gd`,
  `_model_shots.gd` (renders imported
  models from 4 sides), `import_weapons.py` (unpacks weapon downloads),
  `make_textures.py` (regenerates `assets/textures/`), `test_p2.gd`, `shots_p2.gd` (soldier
  poses, sprays), `shots_battle.gd` (a wave from the trench), `make_buses.gd` (audio buses),
  `check_web_pack.gd` (checks the exported pck, see gotchas),
  `soak_m3.gd`: automated checks. `shots*.gd`: screenshots (need a GL window).
  Run all tests before every commit.
