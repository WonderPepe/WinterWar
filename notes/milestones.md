# Milestone history and development ideas

Moved from CLAUDE.md (2026-11-01). Read when working on this area; keep it up to date.

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
  2026-11-02 (owner): while it waits for the click, the status line ("The battlefield is ready.")
  and the full 100 % bar are hidden – only the title, the tip and CLICK TO START THE BATTLE.
- [x] G2 "pressure" (owner chose parts 1, 3, 4 of the plan): enemy suppression + prone, officer
  with whistle, DP-27 MG teams, wave composition list (needed to send officers/MG teams).
  Artillery was dropped by the owner. Field cover (rocks, wire, craters, cover points) was
  skipped for now – still open, see development ideas.
- [x] Front reports: after each cleared wave the owner's Finnish front report for that day
  (21.12.1939 … 28.12.1939, then 31.12.1939 and 01.01.1940 for waves 9–10; in order,
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

- [x] 10 waves on every difficulty (owner): the number of waves no longer depends on difficulty.
  Easy = Normal's wave list with fewer RIFLEMEN only (officers, MG teams and barrages the same –
  owner's rule: never change officers/MGs for Easy) and `DifficultyData.enemy_damage_multiplier`
  0.6 (→ static `Enemy.damage_multiplier`, soldiers' bullets only; artillery unchanged – owner).
  Normal got waves 9–10 ([11,2,2,0], [12,2,2,1]); Hard unchanged. test_artillery's "attack goes
  on" check is a little flaky (failed once, then passed 4×; also on the old code).

- [x] Test mode (owner): main menu "Test Mode" button (visible only with `OS.has_feature("editor")`)
  → panel with "Start at wave" SpinBox (1–10) + Start / Back; uses the menu's difficulty.
  Static `MatchDirector.test_start_wave` (kept for "Play again"; Single Player / Benchmark reset it
  to 0). Host `_start_test_mode()`: synced `test_wave`, `waves_cleared = wave − 1`,
  `WaveSpawner.start_at_wave(wave, test_first_wave_delay 3 s)`. Dusk jumps to the right light on
  its first frame; HUD skips banners/day screens for waves < `test_wave` and shows
  `WavePanel/TestTag`. Checks at the end of test_g1.

- [x] Battles instead of waves (owner; replaced an earlier "Day n" wording): everything the
  PLAYER reads says "Battle" – HUD "BATTLE n / 10", banner "BATTLE n" / "BATTLE n COMPLETED",
  "Battle n begins in s", end screen "Battles held", Test Mode "Start at battle", menu tooltips,
  loading tip, debug overlay; day-screen title "TAISTELU n" (was "PÄIVÄ n"). Code names
  (wave_number, WaveData, WaveSpawner, DayScreen…) stay as they are.

- [x] New battle = new day (owner): after a cleared battle (not the last), once the day screen is
  black, every player goes back to the spot they started the match at (`Game._start_points`, by
  player name) with a fresh start: `Game.reset_players_to_start()` → `Player.respawn()` (full
  health, ammo, bandages, off the Maxim, standing; a dead player comes back at once). Host:
  `MatchDirector._reset_players_later()` waits `reset_players_delay` 3.8 s (day screen: 2.5 s
  banner + 1 s fade). `Game._on_player_died` ignores its timer if the player is already alive or
  died again (`deaths` count). The light now JUMPS to the new day's light while
  `DayScreen.is_black()` (group `day_screen`); without a day screen (last battle) it still moves
  slowly. Owner's plan next: own weather + time of day per battle (idea 6). Checks in test_g1.
- [x] Get-ready time between battles 20 s → 5 s (owner): `WaveSpawner.time_between_waves`. The
  countdown is held while the day screen is open, so the 5 s start when it closes.

- [x] T1 tank (owner's plan, step 1 of 3): a Soviet T-26 that drives a drawn route to the trench
  edge, turret + coaxial DT + 45 mm HE gun, armoured (bullets only spark), stops at the trench
  edge and fires from there. Owner's choices: armour instead of hit points (only a Molotov will
  stop it), routes instead of the navmesh, it STOPS at the trench edge (doesn't cross), the wreck
  becomes a cover point (T3). T1 has no waves yet: F9 / F10 (editor only) bring / knock out a tank.
- [x] T2 Molotov cocktail (owner's ignition flow): boxes in the trench (F), G = bottle in the
  hand, RIGHT mouse held ~1 s lights the rag (then right mouse = aim), LEFT mouse throws. Lit
  0–5 s fine, 5–8 s bigger flame + warning, 8+ s burns the hand + may slip at your feet. A lit
  bottle can't be put away. Engine deck hit → BURNING (stops, no fire, 3 crew bail out and run
  in panic) → DESTROYED after 20 s; elsewhere on the tank = crew blinded 4 s; ground = burning
  fuel 6 s (hurts players and soldiers). Sounds: owner's Freesound picks (see T2 section).
- [x] T3 tanks in the battles (owner's numbers): one T-26 in battles 4–8, two in 9–10, the same on
  every difficulty. Owner's choices: a battle only ends when its tanks are stopped too (burning
  counts); wrecks stay as cover but only the newest 3 are kept (older ones vanish behind the black
  day screen); soldiers using wrecks as cover moved to a later milestone (with "field cover",
  idea 0). Tanks start 40 m back in the forest (cleared lanes) – the engine is heard first.
- [x] T4 tank turret feel (owner's numbers): the turret is hand-cranked – idle 4, tracking 8,
  emergency (target < 25 m) 12 deg/s max; 1.5 s from standstill to top speed and the same to
  brake; 0.3–0.6 s reaction after spotting; a target behind the hull (> 100°) costs 0.8–1.5 s more;
  inside 10 m the top speed shrinks to 50 %. Turret sounds from the owner's Freesound picks.
  Details: `tank-and-molotov.md`.
- [x] Controls screen + tank 3 m closer + Molotov hint (owner): a **Controls** button in the
  main menu and the pause menu opens `ui/controls_panel.tscn` (`ControlsPanel`, rows filled from
  the Input Map – change a key there and the list follows; F-key test keys only in the editor;
  Back / Esc close it). Tanks park 3 m closer (routes end at z = 49, gun depression −14°). The
  first tank battle shows a Molotov hint after its banner. Details: `tank-and-molotov.md`.

- [x] L1 trench line + protected firing positions (owner's request 2026-11-07: "more corners, not
  long straight lines" and "around 4 places where the player can shoot, protected with ground and
  sandbags"). The old 10-leg zigzag (21 m legs) is now `TRENCH_XZ` in `tools/build_scenes.gd`:
  43 legs of 3–8 m (the 12 m stretch in front of the bunker is the only long one), 39 real
  corners, jogs and 45° bends, two dead-end branches to the rear (`SPURS`), the Maxim pit
  (`MaximPitCut`) widens the trench in front of the bunker. Exits, spawns (x = -30, -10, 10, 33),
  crates and the 10 trench entries sit on the new line.
  **Firing positions, 2nd version (owner, after the photo SA_Kuva_a_8):** four narrow bays
  (`POST_X` = -64, -23.5, 24, 64; group `fire_post`, nodes `FirePosts/FirePost1…4`) – 1.3 m wide
  (one soldier), 1.6 m deep beyond the trench edge, no firing step. In front a sandbag wall
  0.62 m thick and 0.84 m high with a loophole 0.8 × 0.42 m starting at the ground: the standing
  soldier's eyes (0.2 m above the ground) are at the hole, a lintel of sandbags covers his head, earth
  heaps on both sides. Only a bullet through the hole can hit him (the walls are real collision;
  at ~±22° sideways / ±11° up-down he sees and is seen); crouching = fully hidden. Splash damage
  isn't blocked. (First version: a 3.5 m bay with a log step and a low wall – replaced.)
  Details/gotchas: `gotchas.md` (L1). Tests: `test_l1.gd`, `shots_l1.gd`.
- [x] L2 wooden bunker turned around (owner 2026-11-07): the bunker faces the enemy (front wall at
  z 56.75, open ground in front, no trench there); the trench line runs BEHIND it and a short open
  stub (x = 1.2) leads to a back door (1.4 m wide); the Maxim sits at x = 0 behind a funnel hole
  (1.1 m outside, 1.6 m inside, 0.45 m tall), limited to ±21°; gun pivot 0.6 m behind the outer face so the barrel ends flush with the hole. Artillery bunker corners are now the
  two FRONT corners. Ammo crate in the bunker at (-1.9, 61.2). Constants `BUNKER_Z/DOOR_X/DOOR_W`.
  Tests: `test_m1/w1/artillery/m2/p2` adapted; `shots_l2.gd`.
  L2d (owner tested: died in the bunker during a barrage): the whole bunker room is now a safe zone for
  artillery (`is_covered`; `is_bunker_corner` removed). L2e: except the gunner mounted on the Maxim, who takes damage from shells landing in front.
- [x] Bug fixes from the code review (2026-11-01, owner asked for 1 and 2): artillery hold line
  no longer survives into the next match (`battle.md`); bailed-out tank crews count as soldiers
  of the battle (`tank-and-molotov.md`). Review leftovers (not approved): bandage usable at
  99 HP, Space closes the day screen AND jumps, rifle fire timing / corpse timers use real time, respawn next to Soviets in the trench, soldiers walk through Molotov fires,
  FOV / invert-Y options.

- [x] Ctrl+W guard in the browser (2026-11-02, owner chose the warning + true blocking in
  fullscreen + an info notice): "Leave site?" while a battle runs, Keyboard Lock in fullscreen
  (Chrome/Edge), "hold Esc to leave fullscreen" notice. Crouch keeps Ctrl AND C (owner didn't
  pick the key change). Reaches players only with the next release. See `graphics-and-web.md`.

- [x] DP-27 teams closer + sent forward (2026-11-02, owner, from a player's report "no hunting
  for the last enemy"): gun teams follow their riflemen 5–10 m behind, open fire once they see a
  Finn 80–130 m from the trench, and move up again when the riflemen are 20 m further on ("fire,
  then move up" – owner's choice; last position 5–10 m behind the attack points, was 35 m); when
  all the other soldiers are dead the gun teams advance and assault like riflemen. See `battle.md`.

- [x] B1 battle briefings (owner 2026-11-08, "Prio 1" of idea 6): ten battles with real dates +
  weather + briefing text, shown BEFORE each battle (loading screen for battle 1, the day screen
  for the rest); no place names, no times; wave lists unchanged; the old Finnish front reports are
  no longer shown (kept in the builder). Details: `day-screen.md`. Next (Prio 2): weather and
  time of day per battle (fog, snowfall, light), then different gameplay per battle.

- [x] B2 loading screen march (owner 2026-11-08, his HTML example): the loading bar became a snowy
  marching path with a little code-drawn soldier (legs swing, body bobs, rifle + backpack, a post
  with a pennant as the goal), snow falling over the whole screen, the owner's 18 phrases by
  percentage (`LoadingScreen.PHRASES`, `phrase_for()`), the percentage below, and at 100 % the
  soldier stops and the line turns red "ALARM! TO THE POSITIONS!". Owner's decisions: the soldier
  and the ALARM line STAY visible at "CLICK TO START THE BATTLE" (replaces the old "hide status
  and bar" rule); the march takes at least `MIN_MARCH` 4 s (real game only; benchmark keeps the
  plain bar) and he stands 0.7 s at the end on desktop. Details: `day-screen.md`.

- [x] B3 weather and time of day per battle (owner 2026-11-08, "Prio 2"): ten looks (moon-lit
  battles 1–2, clear 3–4, smoke 5, overcast 6, dense fog 7, fog clearing DURING battle 8, low cloud
  9, dusk without snow deepening during battle 10), snowfall and wind per battle, wind sound. The
  old slow sunset over the ten battles is gone (battle 10 = its end). Visual only – enemy sight and
  ranges unchanged. Details: `graphics-and-web.md`. Next (Prio 3): different gameplay per battle.
- [x] B3b (owner): battle 10's briefing says "Weather: Dusk" (no snowfall); FOG LIMITS ENEMY SIGHT
  (`WeatherData.visibility_m`, `Enemy.visibility_limit`; soldiers and tanks; numbers in
  `graphics-and-web.md`). Tests in `test_b3.gd`.

- [x] A1 air raid (owner 2026-11-08): three Tupolev SB-2 bombers in battles 4 and 8 - distant engines,
  planes overhead, bomb sticks in front of / behind / around the positions, big snow and earth plumes,
  planes leave. Same danger rules as the artillery; after the barrage in those waves. Sounds: the
  existing plane recording for the engines, generated PLACEHOLDERS for whistle and boom until the owner
  adds real `raid_*` recordings. Details: `battle.md`.

- [x] L3 communication trenches + battle 6 "retake the trench" (owner 2026-11-10): two zigzag
  communication trenches leave the line at x = -40 and +40 (they replace those two exit ramps; the
  ramps at ±80 stay) and run ~45 m back into the forest (legs 3–8.5 m with 45° bends, ramp up to the
  ground at z ≈ 107–111.5). Rear spawn points at their far end: players RESPAWN there in every
  battle (the start of a battle is still the trench line). Later: the way up for support / friendly
  soldiers. Battle 6 (owner's choices: "retake, then hold", the WEST half is taken): the Soviets
  hold x -100 … -5 (Easy 7 / Normal 8 / Hard 9 riflemen + 1 officer + 1 DP-27 team – Easy only fewer
  riflemen), the players start at the rear of the west trench; no "line broken" defeat meanwhile;
  when the last one is dead the owner's banner "Trench Retaken! / Prepare for Counterattack!"
  (two lines so it fits), 8 s later the normal battle 6 wave + barrage attacks. Owner's new battle 6
  briefing text. Details: `battle.md` (Retake), `architecture.md` (map). Tests: `test_l3.gd`,
  `shots_l3.gd`.
  L3b (owner 2026-11-11): battle 6 happens in the dark of the morning, a little darker than battle 2
  (`make_weather.gd` look 6, see `graphics-and-web.md`).

- [x] W3 Suomi cocking handle + empty cases (owner 2026-11-11). Owner's decisions: do NOT animate
  the bolt (not visible to the player); the KP/-31's cocking handle does not reciprocate, so it
  never moves when firing – firing is shown by recoil, flash and ejected cases only; a reload
  ends with the right hand pulling the handle back and letting it snap forward (W3b: only when
  needed, see below); reload time stays
  4.5 s (option A: the drum change was squeezed a little to make room). The owner may add a real
  cocking sound later (`assets_source/`). Details: `weapons.md` ("Suomi cocking handle and cases").
  W3b (owner 2026-11-11): cases always fly out to the right – walking or jumping must not change
  them (now in the view's space, not the world). Cocking ONLY when needed: first time the gun is
  taken out (each life) – yes; reload after an empty drum – yes; tactical reload with rounds left –
  no (that reload is the old W2 drum change). No firing / aiming while cocking (~1.2 s).
  Cocking sound from the owner's download (freesound 676588, CC0) → `cock_suomi.ogg`; credited in
  CREDITS.md + the main-menu credits (which were also brought up to date – several sounds added
  since T2 were missing there).

- [x] V1 Enemy muzzle flashes easier to see at dusk / night (owner 2026-11-12). Owner's brief: realistic
  and subtle (no fireballs), day unchanged, ~30–60 % easier to notice in the dark, 40–60 ms, cheap
  for the browser, scaled with how dark it is. Owner approved all three parts: flash a little
  bigger, brighter (HDR colour), and a brief small glow from 2 pooled lights. Details:
  `soldiers-effects-sound.md` ("Muzzle flashes in the dark"). Tests: `test_v1.gd`; measurement:
  `shots_flash.gd`.

- [x] C1 climbing out of the trench (owner 2026-11-13: "player cannot jump out of the trench, this
  is hard when they need to destroy tanks"). A jump lifts ~1.0 m, the trench is 1.4 m deep and all
  exits lead to the rear, but a Molotov must land on the tank's rear engine deck. Now Space in
  front of a wall that is too high to jump onto climbs it (any side, any world ledge 0.9–1.7 m).
  **Owner's decisions:** climb time 1.0 s; NOT with a bottle that is being lit or burning (an
  unlit bottle in the hand comes along, and can't be lit during the climb); Space while crouching
  climbs too (on open ground a crouching player still can't jump); NO help text (no Controls
  row, no line in the tank hint). Rejected: a higher jump, ladders/steps at fixed spots.
  Details: `tank-and-molotov.md` ("Climbing out"). Test: `test_c1.gd`.

- [x] T5 armour stops enemy bullets (owner 2026-11-13: "bullets should not go trough tanks" – his
  own did not, only the enemies'; he chose to include sight and blast too): tanks and wrecks on the
  new physics layer 5 "armour"; soldiers' and tanks' bullets, shells, sight and the 45 mm blast
  stop at them. Wrecks are now real cover for the player. Details: `notes/tank-and-molotov.md`.

- [x] V10b "the battle leaves marks" (review item V10, steps 3 and 4; owner 2026-11-16: bodies and
  tracks first, then V10a trees + clouds). Bodies of the fallen stay on the field instead of
  vanishing after 20 s, and tanks leave tracks in the snow.
  **Owner's decisions:** body caps 36 / 24 / 12 (High / Medium / Low); tracks vanish at the next
  day screen; the newest 12 bodies STAY for the next day "to give a feeling of continuity"; bodies
  should have a bit of snow on them (built: kept bodies get snow at each day change).
  Not built / open: body shadows (off: one more draw call each), fewer draw calls by merging
  bodies, snow that grows during a snowy battle. Details: `soldiers-effects-sound.md` ("Bodies
  stay"), `tank-and-molotov.md` ("Tank tracks"). Test: `test_v10b.gd`; pictures: `shots_v10b.gd`.

- [x] V10a "the world moves" (review item V10, steps 1 and 2; owner 2026-11-16). The spruces lean
  with the gusts and their branch tips bob (vertex shader), and the clouds drift slowly.
  **Owner's decision:** the strength follows each battle's wind – new `WeatherData.wind` (0 still …
  1 strong … 2 storm): where snow falls it is the battle's `snow_wind` (1: 0.4, 2: 1.6, 5: 0.8,
  6: 0.5, 9: 0.3); without snowfall it was chosen from the wind sound (3: 0.3, 4: 0.25, 7 dense
  fog: 0.1, 8: 0.15 → 0.35 as the fog clears, 10: 0.3) – tune in `tools/make_weather.gd` (`LOOKS`).
  Clouds: NOT with TIME in the sky shader (measured: several times dearer) but a `cloud_offset`
  value moved 8 times a second by DuskLight. The fallback (clouds on their own layer) was not
  needed. Details: `graphics-and-web.md` ("Motion"). Test: `test_v10a.gd`; pictures: `shots_v10a.gd`.

- [x] T6 running tracks and turning wheels (owner 2026-11-16). Written in a chat without Godot,
  run the same evening in the next chat: `test_t6.gd` and all other tests green at the first
  run, no shader errors with a GL window, pictures in daylight (battle 4) and the darkest look
  (battle 6), web export + smoke test + a longer browser run past the loading screen (no
  console errors). No game code had to be changed – only the far camera of `shots_t6.gd`.
  A `TrackAnimator` node on the tank reads the hull's real movement (nothing from the AI):
  left track = forward − turn × half gauge, right = forward + turn × half gauge; the belts' link
  picture slides, with a little snow and dirt; sprocket, idler, road wheels and rollers turn on
  the graphics card around axles written into the model. No new draw calls or triangles.
  **Told the owner:** today's tank never reverses or turns on the spot, so those two are built
  and tested but not seen in play (teaching the tank to do them = a driving milestone); the
  road wheels' turning is hard to see (plain dark discs) – a snow smear on them is an idea.
  Changed from the plan: distance is measured each physics step instead of a 0.15 s smoothed
  speed (so the links never slide on the snow); the snow/dirt picture is made in code, not by
  `make_textures.py` (no new import file). Details: `tank-and-molotov.md` ("Running tracks").
  Baselines before V10a (owner's PC, Low and High) are in the project doc
  `claude/review-2026-11-12.md`; the browser run on Medium is still to be compared.

- [x] AR1 first-person arms: winter clothing look (owner 2026-11-17). First of six steps AR1–AR6 in
  the project doc `claude/plan-arms-winter-clothing.md` (findings, plan, owner decisions). Out of
  scope by the owner's brief, for ALL AR steps: state-specific elbow targets, a shoulder-posture
  system, spring-based weapon weight/inertia/lag. Owner decisions (17 Nov): the Suomi's left hand
  STAYS on the drum (it holds the gun up when aiming and pulls it slightly back towards the shooter
  for a steady aim and less muzzle climb – refine, don't move it, AR3); mittens grey-ivory; a
  look-down front torso (smock front, belt, pouches; no legs/boots) – yes (AR6); grey cuff that
  shows more while reaching, with one extra bone – yes (AR4). Order AR1 → AR6.
  AR1 (picture only, no animation change): baggy folded smock sleeves (left/right fold
  differently), hemmed cuff, ~1.5–2 cm grey wool tunic cuff, rounder grey-ivory mittens with a
  ribbed cuff, dirt/wear/snow baked into the vertex colours, own matte shader (both sides drawn).
  Arms 2332 → ~6400 triangles, still one draw call. Details: `weapons.md` ("Arms: winter clothing (AR1)").
  AR1b (owner's test, 17 Nov): "Suomi: right thumb goes through the cocking handle; the left mitten
  goes through the grey sleeve. Mosin: the left thumb doesn't touch – the left hand should hold
  the rifle to control it." → thumb bones (each gun turns the thumbs: `thumb_right_deg` /
  `thumb_left_deg`), wrist shared between forearm and hand, Suomi GripR 1.4 cm back + thumb over
  the stock behind the cap/handle, Mosin GripL raised 2.7 cm (it floated below the fore-end) +
  thumb up its left side. Brought forward from AR2/AR3 (thumbs, wrist blend). Owner's 2nd test:
  the Suomi thumb straight across the gun, closer to the cocking handle (not leaning back).
- [x] AR2 arms: smooth elbow, twist spread down the arm, a moving trigger finger (owner
  2026-11-17). Elbow shared between upper arm and forearm; upper arm rolls with the elbow, forearm
  half-way to the hand (folds stay put); right trigger finger on its own bone – outside the guard
  (sprint, reload, bandage, climb, raise/cock), resting on the guard (hip), on the trigger (aim,
  fire, squeeze at each shot), round the knob (bolt / cocking); Maxim thumbs press while firing.
  No mitten compression (not needed). Still one draw call, 9 bones. Details: `weapons.md` ("AR2").
- [x] AR3 hand positions (owner 2026-11-17): Mosin bolt hand palm-down over the knob, turns a third
  of the handle's turn, curved path over the receiver; Suomi left hand cups the drum's front-lower
  edge (owner: holds the gun up and pulls it back). Right wrists stay as they are (straighter =
  thumb + trigger finger worse; the real fix is the shoulder, out of scope). Details: `weapons.md` ("AR3").

## Development ideas (not yet approved)
0. G2/T3 leftovers: tank wrecks as cover points soldiers run to (T3, owner: later); field cover (granite rocks / anti-tank rocks, old shell craters in
   TerrainGenerator heights, barbed-wire belts with gaps via NavigationObstacle3D carving, cover
   points that soldiers bound between); MG fire suppressing the player (screen effect).
1. (done in W2) Maxim sights/belt/heat. Still open: better Maxim sound, water can + hose.
2. (done in W2) First-person arms. Still open: arms for co-op players' third-person bodies
   (players are capsules now), a Mosin reload that really moves the stripper clip (the Suomi
   drum change is done).
3. Real Summa terrain from the owner's maps + Copernicus DEM; real trench line, the big concrete
   bunkers (e.g. Sj5 "Millionaire"), anti-tank rocks, barbed wire, shell craters.
4. Soviet attack variety: (T-26 tank: T1 done, T2/T3 planned) infantry behind the tanks, T-28, artillery barrages
   (craters, camera shake), enemies using cover, grenades, smoke screens, officers.
5. Player options: Molotov cocktails / satchel charges against tanks, grenades, bandages,
   ammo crate in the trench, a firing step, prone, leaning.
6. (owner's plan) Each battle its own event: real battle dates, realistic photos and info per
   battle (FRONT_REPORTS / day screen), and later a different start for each battle – own
   weather and time of day (instead of one dusk over the whole game).
6b. Game structure: hold for N waves → victory/defeat screen, difficulty levels, short winter day
   turning to dusk/night with flares, scores.
7. Finnish comrades: AI riflemen in the trench (later replaced by co-op players).
8. Co-op over WebRTC (needs a small signaling server) with a lobby code.
9. Real sound recordings (CC0) to replace the generated ones; shouts; menu music.
10. Options: field of view, key rebinding, gamepad.
11. Lahti-Saloranta (slot 3) if a usable model turns up, or built from shapes.

## R1 – battles rebalanced, tank-route fix, release v0.5.0 (2026-11-10)
Owner's new Easy wave lists (Normal +1, Hard +2 riflemen), air raid in battles 4/8/10, tanks in 3/5/7, barrages in 5–8 and 10, new
battle 2 briefing; details in `battle.md` ("Wave lists rebalanced"). Tank routes: see `tank-and-molotov.md` (no tank on a wreck).
All tests pass (tests adjusted to the new lists). Released as v0.5.0.

## D1 – retry the lost battle / continue a run (2026-11-13)
From the v0.6.0 team review (project doc `claude/review-2026-11-12.md`, item D1). Owner's decisions:
defeat screen = "Retry battle n" + "Main menu" (no "Start over" there – a new run starts from
the main menu's Single Player); victory screen = "New run" + "Main menu"; statistics cover the
WHOLE run (saved at each battle held, a failed try's numbers are dropped on retry) + a
"Retries: n" line. Main menu: "Continue – Battle n (Difficulty)" above Single Player, only when a
saved run exists. Details in `battle.md` ("Saved run"). Checks: `test_d1.gd`. All tests pass,
web export + smoke test OK.

## P3 – 3D resolution cap (review item P1) (2026-11-13)
From the v0.6.0 team review (item P1; named P3 here because P1/P2 are the graphics milestones).
Owner approved: caps 1080 / 900 / 720 lines (High / Medium / Low), default Auto, "Full" for
strong machines. Side effect accepted: on a 1080p screen Medium is 900 lines (was 972) and Low
720 (was 810). Details: `graphics-and-web.md` "3D resolution cap".

## V2 – softer earthworks (review item V2) (2026-11-13)
From the v0.6.0 team review (item V2: "trench, bunker and firing positions are clean boxes").
Owner approved the plan as shown, including the bunker side banks as PICTURE ONLY (a soldier walks
through them like knee-deep snow; solid banks would need a navmesh re-bake).
- New node `EarthworkSnow` in the level (4 meshes, no collision, not a navigation source):
  `TrenchLips` (rounded snow lip on every trench edge, 4–15 cm, lower on the enemy side),
  `FloorDrifts` (drifts at the wall foot, clean → trampled), `RampSnow` (snow over the four ramp
  landings), `BunkerSnow` (domed roof cap + banks on the side walls and front corners).
- The earth heaps of the firing positions: rounded mesh, the old wedge stays as the collision.
- Terrain: the ground's normals no longer include the hidden drop to the trench floor (it showed as
  lines along the edges of the earth slabs).
- NOT done on purpose: a raised parapet in front of the trench (would change what both sides see
  and hit – a gameplay decision for its own milestone).
- Cost: +4 draw calls, ~33 000 triangles in total (only what is in view is drawn), +0.4 MB pck.
Details: `graphics-and-web.md` ("Soft snow on the earthworks"). Tests: `test_v2.gd`, `shots_v2.gd`.

## V4 – sandbags (review item V4) (2026-11-13)
Owner: "user should not see through sandbag holes" + the review's three steps (burlap texture and
normal map, smooth sagging bag, keep the merged mesh). The old bags were squashed balls that only
touched in points: daylight showed between them, worst beside the loophole.
- `tools/make_textures.py` `burlap()` → `burlap_albedo.png` / `burlap_normal.png` (256 px, plain
  weave, light grey – the material colour tints it, so plain and snowy bags share it).
- `_bag_mesh()` in `build_scenes.gd`: a pillow (rounded-square outline, flat top/bottom, 160
  triangles, smooth normals) that sags and is 6–18 % bigger than its place, so neighbours press
  into each other. `_bags_mesh()` and the bag positions are unchanged (still one mesh, 2 surfaces).
- Materials `sandbag.tres` / `sandbag_snow.tres`: burlap, triplanar (no UVs in the mesh).
- **Added beyond the three steps:** node `SandbagCore` in each `FirePostN` – three dark boxes inside
  the wall (7–13 cm smaller than the collision boxes, material `sandbag_core.tres`). Bags alone
  cannot close every crack at every angle without bulging into the loophole; with the filling a
  crack shows dark earth instead of daylight.
- Unchanged: collision, loophole (0.8 × 0.42 m), navmesh (no re-bake needed).
- Cost: bags 24 320 triangles in the 4 walls (was ~9 700), +4 draw calls (one filling per wall).
Details: `graphics-and-web.md` ("Sandbags"). Tests: `test_v4.gd`, `shots_v4.gd`.

## D9 – hit zones (review item D9) (2026-11-15)
The player's bullets do different damage in a soldier's head, body and legs.
- No new collision shapes: `Enemy.hit_zone_at(hit_position)` works the zone out from where on the
  one capsule the bullet landed. Standing (1.8 m): head = top 0.3 m, legs = below 0.85 m.
  Kneeling (1.2 m): head = top 0.3 m, legs = below 0.4 m. Lying flat: measured ALONG the body
  (head forward) – head = front 0.3 m, legs = rear 0.8 m.
- Multipliers in `EnemyData` ("Combat"): `head_damage_multiplier` 4, `leg_damage_multiplier` 0.6.
  **Owner decisions:** head ×4 (so one Suomi head shot kills up close), legs ×0.6 (a Mosin leg hit
  only wounds: 60 of 100), ring around the X for a head shot; a head-shot sound may come later.
- Only bullets (`WeaponController.resolve_shot`, also the Maxim) use zones. Molotov fire, shells
  and bombs call `take_damage()` directly and are unchanged; so are Soviet bullets on the player.
- `hit_confirmed(killed, zone)` – the host sends the zone (`Enemy.HitZone`: BODY, HEAD, LEGS – add
  new values at the END) with the hit confirmation; `HitMarker.show_hit(killed, head)` draws the ring.
  The F3 debug text names the zone.
Details: `weapons.md` ("Hit zones"). Test: `test_d9.gd`.

## P4 – web loading without the long freeze (2026-11-16)
Owner's report: the web version "takes much time" at the first battle, the browser says "no
response", and when it is ready the photo and briefing are still on screen with "click to start".
- Measured (live v0.9.0, real GPU): one 10.3 s freeze with no frame, at the "reading files" step.
- Fix: `LoadingScreen` loads the battle's files one by one in the web build (no threads) with a
  frame in between; details in `graphics-and-web.md` ("Loading the battle in the web build").
- **Owner decision:** at the click prompt the photo and briefing go away (fade 0.6 s).
- Test: `test_b1.gd` (fade, dependency order, desktop keeps threaded loading).
- Open: the first frame's shader compiling is not split yet (see the note).

## S1 – sky seams in Chrome (2026-11-16)
Owner's report: in Chrome (Windows, AMD Radeon 780M) the night sky of v0.9.0 showed straight lines /
blocks, also while paused; Firefox was fine, and Chrome with `chrome://flags/#use-angle` = D3D11
was fine too – so it is Chrome's default graphics path on that computer.
- Not reproduced outside the game (a WebGL test page with the old noise looked fine in Chrome).
- Fix tried: the sky's `hash()` now uses whole-number (uint) math instead of `fract()` of big
  decimals; noise coordinates marked `highp`. Stars use the same hash. Cloud pattern is a new
  random layout, same look and cost.
- **Owner decision:** if the seams are still there after this, remove the cloud drift (V10a).
- Owner tested it in Chrome on Default (Run in Browser): the blocks are gone. Released as v0.9.1.


## GR1 – Soviet hand grenades (2026-11-17)
Owner's wish: enemies throw grenades at the Finns when they are close to the trench. Plan: project
doc `claude/plan-enemy-grenades.md` (GR1 + GR2 throw-back).
**Owner decisions:** same number on every difficulty, one soldier carries at most 2; from battle 1;
friendly fire yes; warning = only a grenade icon (no text); they may throw into the bunker;
GR2 (pick up and throw back, F) right after GR1; the end screen shows grenades thrown back (GR2).
- Model: owner's download `assets_source/Grenade F_1.zip` (Sketchfab, CC-BY 4.0, in CREDITS.md) →
  `import_weapons.py --f1` (rebuilt: 1,873 triangles instead of 4,108 – meshoptimizer with a higher
  error broke the body –, 256 px colour + normal, no pin, metres).
- Details: `battle.md` ("Hand grenades (GR1)"). Tests: `test_grenades.gd`, `shots_grenades.gd`.
- Sounds: `grenade_boom…` / `grenade_land…` recordings wanted (owner downloads); until then the
  raid_boom recording pitched up, landing silent.

## GR2 – throw a grenade back (2026-11-17)
F next to a live grenade (1.5 m): snatch it up and throw it back the way you look (~20 m) in
0.4 s; the fuse keeps running (too late = it goes off in your hand); kills count for you; end
screen "Grenades thrown back" (kept in the saved run). HUD: [F] key beside that grenade's icon.
Details: `battle.md` ("Throwing a grenade back (GR2)"). Tests: `test_grenades.gd` (GR2 part).

## GR3 – grenades round a corner in the trench (2026-11-17)
Owner noticed soldiers in the trench never throw (the GR1 rule). **Owner decision:** in the trench
only at a Finn he can't see but knows is there, at least 8 m away, no comrade within 4 m of the
landing spot, never landing near himself; same limits (2 live, 4 s). Details: `battle.md` (GR3).

## NET1 – co-op: host and join over ENet (review item A1, step 1) (2026-11-18)
Review item A1 "prove co-op early", steps 1–3 as NET1–NET3 (the name A1 is already the air raid).
**Owner decisions (2026-11-18):** names NET1–NET3; a co-op battle never touches the single-player
saved run (like Test mode); respawn as in single player (same time, at the rear, for everyone).
- Host Co-op / Join Co-op open a lobby (`CoopLobby`, made in code by the main menu). ENet, port
  7777, 2–4 soldiers. Desktop only: in the browser both buttons stay greyed out (ENet needs real
  sockets; the web needs WebRTC = A1 steps 4–5, later).
- Start → every computer loads the battle (difficulty + Test-mode battle from the host).
  **Load gate:** the host's battle stays paused with nobody in it until every computer reports its
  battle scene (`NetworkManager.report_loaded`); then the host spawns all players and unpauses.
  Nobody can join a running battle; one who drops out disappears; host leaves → the others go back
  to the menu with "The host left the game."
- Launch options for two windows on one PC (Debug → Customize Run Instances): `--coop-host`
  (starts as soon as a second soldier joins), `--coop-join[=address]` (retries until the host is
  there), `--coop-wave=N` (Test mode battle N, with --coop-host).
- Details: `architecture.md` ("Co-op connection (NET1)"). Test: `test_coop.gd` (two copies).
- Fix after the owner's first test: player 2's "Battle 1 begins in 5 s" stood still – the countdown
  ran only on the host. Now `WaveSpawner.next_wave_seconds` (whole seconds) is synced by WaveSync and
  `get_time_to_next_wave()` reads it on the other computers.
- Next: NET2 – play a battle as player 2, list what breaks (`notes/coop-issues.md`), fix the worst;
  NET3 – smooth remote soldiers / players / tanks between network updates (picture only).

## NET2 – co-op: play as player 2, fix what breaks (review item A1, step 2) (2026-11-18)
The list (what works, what breaks, status): `coop-issues.md`, found with the new scenario
`tools/soak_coop.gd` (player 2 does everything a player can; 72 checks, both copies' errors read).
**Owner decisions (2026-11-18):** retry in co-op yes; a warning line on the host's Main menu ok;
order NET2 → NET2b (a Finnish soldier body for the other players instead of the grey capsule) → NET3.
- The next battle waits until every player has closed his own day screen (`WaveSpawner.set_reader_hold`,
  `_peer_holds`, synced `waiting_for_readers` → HUD "waiting for the others to read the briefing").
- Host's end screen: "Retry battle n" / "New game" for everyone (`NetworkManager.begin_battle(test, start)`,
  `MatchDirector.coop_start_battle`); retry in three steps (others stop their battle → host leaves →
  everyone loads) so no message arrives for a battle that is gone. Others: "Waiting for the host…".
- Host's pause / end screen: "Main menu ends the battle for everyone." Respawn never on another
  living player's spot. Refused join: "…or the battle has already started." Launch option `--mute`.

## NET2b – a Finnish soldier body for the other players (2026-11-18)
The other players were a grey capsule that never turned. Now every player except your own is
drawn as a Finnish soldier (`PlayerBody`, Player child `Body`, made in code; your own stays hidden).
**Owner decisions (2026-11-18):** M/39 fur hat; snow smock in dirty off-white / undyed white (not
optical white), loose (an outer layer), to mid-thigh, gathered at the waist with a drawcord, grey
uniform collar and cuffs just showing, subtle grime on elbows / stomach / lower hem / knees, no
modern pockets, zips, Velcro, elastic cuffs, padded elbows or camouflage patterns; hood down but
visibly bunched round the back of the neck and shoulders; full white snow trousers; dark-medium
brown leather boots, toe moderately raised, mostly hidden by the trousers; keep it low-poly.
Order after this: EX1 (Windows build to play with a friend on the same network), then NET3.
- `FinnMesh` (scripts/player/finn_mesh.gd): code-built like SoldierMesh, same 12-bone skeleton,
  two versions (Mosin M/28-30, Suomi KP/-31), ~1050 triangles, one draw call. Grime = vertex colour
  (`SoldierMesh.use_color_fn`), drawn with soldier.gdshader (smock alpha 1 = gets the grain and a
  per-player tint from `SMOCK_TINTS`).
- `PlayerBody` poses it every frame from state that is synced anyway (no new network traffic):
  walk/run from the position change, view yaw (the Player turns) and pitch (chest 40 %, head and gun
  the rest), crouch (kneel / bent-low walk), sprint (port arms), aim (shouldered), reload, weapon slot,
  Maxim (hands on `MountedGun.get_hand_grips()`), Molotov phase (bottle in the hand, overhand throw),
  grenade grab (GR2), climbing, bandaging, dead (tips over like the Soviets; up again at respawn).
  Hands busy → the gun is slung on his back. Arms: `SoldierMesh.reach` (the IK moved there from
  SoldierVisual; the Soviet meshes are byte-for-byte unchanged – test_net2b checks it).
- The other player's muzzle flash + smoke come from his gun's muzzle (`WeaponController.
  _play_remote_fire_effects`), and his gun kicks. Collision / hits unchanged (the capsule shape).
- The capsule picture (`BodyMesh`) is gone from player.tscn and build_scenes.gd
  (`resources/materials/player_body.tres` is no longer used).
- Tests: `test_net2b.gd` (43 checks), `soak_coop.gd` (now 73 checks) also checks player 2 sees the host as a Finn;
  screenshots `shots_net2b.gd` (lineup, portrait in sun / against the sun, back, side, busy, fire,
  dead, Maxim).

## NET3 – smooth movement on the other computers (review item A1, step 3) (2026-11-19)
Soviets, tanks and the other players jumped from one network update to the next on a guest's
computer. Now they glide (picture only; the host still decides everything). How it is built:
`architecture.md` ("Smoothing on the other computers (NET3)").
**Owner decisions (2026-11-18/19):** keep 60 updates a second; lag compensation (a guest's
shots at running Soviets) left for the online milestones; NET3 before EX1 (Windows build).
- `NetSmoother` (`Smoother` child in soviet_rifleman / officer / mg_gunner / tank / player.tscn and
  build_scenes.gd): host stamps position + facing, guest draws ~35 ms (LAN) – 150 ms in the past
  and glides; ≤ 0.15 s carrying on; > 1.5 m = jump at once; own player never delayed.
- PlayerBody: view yaw / pitch smoothed; Tank: turret / gun smoothed on guests.
- Lag simulator `--net-lag=100 --net-jitter=20 --net-loss=2` (guest). F3 overlay "Net:" line.
- Measured (cloud, two copies, 144 fps client): frame-to-frame "jerk" 0.0018 m smoothed vs
  0.015 m raw (no lag), 0.0018 vs 0.019 m with the lag simulator; delay 36 / 57 ms; 61 / 56
  updates a second; drawn 0.10 / 0.37 m behind the host's walking Soviets (median); no jumps.
- Tests: `test_net3.gd` (42 checks), `test_net3_coop.gd [--lag]` (two copies, 10 checks);
  test_net2b now expects 16 synced player values (the time stamp).

## EX1 – Windows desktop build for co-op on the same network (2026-11-19)
The owner wants to play co-op with a friend on the same home network; co-op is desktop only.
**Owner decisions (2026-11-18):** a Windows build is worth making even during development (a
build is a snapshot, re-made in a minute); share it only privately with the friend, not as a
public release; first NET2b and NET3, then EX1.
- `export_presets.cfg`: preset 1 "Windows Desktop" – x86_64, `.exe` + separate `.pck`
  (`embed_pck` off), S3TC/BPTC textures, no code signing, `application/modify_resources` off
  (needs rcedit + Wine on Linux, and only sets the icon / file details), same exclude filter as Web.
  Path `export/windows/WinterWarSumma.exe`. The .pck is the same 18 MB as the web build's.
- `tools/windows_readme.txt` = the README.txt for the friend (start, SmartScreen, firewall,
  Host / Join, same version on both).
- How to make a build: RELEASES.md ("Windows build"). Not in git: `releases/WinterWarSumma-windows.zip`.
- Checked in the cloud: exported with the 4.7.2 templates; the exported .pck runs (Linux Godot
  with `--main-pack`: main menu, no script errors), and two copies of it host + join and both load
  battle 3 ("every computer has loaded – 2 soldiers"). The .exe itself can only be tried on Windows.
- Ideas for later: a game icon for the .exe (needs rcedit), a "your address is …" line in the
  Host Co-op lobby so the host doesn't have to look up his IPv4 address.

## TR1 – ground cut into tiles (review item P3) (2026-11-20)
Review item P3 ("the ground is one mesh of 180,000 triangles, drawn whole even when most is behind
you"). Named TR1 because the repo's "P3" is the 3D resolution cap.
**Owner decision (2026-11-20):** no simpler far-away ground (LOD) – a far soldier must never look
sunk into the snow or floating, on any computer. So every tile keeps every 1 m point at its exact
height; the saving comes only from Godot skipping tiles outside the camera's view.
- `TerrainGenerator.tiles_per_side` (default 4 → 16 tiles of 75 m) under the generated node
  `GroundTiles` (`Tile_x_z`), replacing `GroundMesh`. Heights, normals and vertex colours are
  still worked out once for the whole grid; neighbours share their edge points exactly.
- Collision (`GroundCollision`), navmesh, horizon, `get_height()` unchanged – no navmesh re-bake.
  Picture only, nothing synced: no effect on co-op traffic.
- Tile count chosen by measuring (`tools/bench_tr1.gd`, High, 1280 × 720, no enemies). Benchmark
  flight route average / max:
  | tiles | draw calls avg / max | triangles avg / max |
  |---|---|---|
  | 1 (old) | 130 / 213 | 283k / 406k |
  | 3×3 | 135 / 216 | 217k / 306k |
  | **4×4** | **138 / 219** | **204k / 304k** |
  | 5×5 | 142 / 223 | 196k / 290k |
  | 6×6 | 147 / 226 | 193k / 281k |
  | 8×8 | 158 / 238 | 186k / 276k |
  4×4 gives most of the saving for +6–9 draw calls (each visible tile costs a few draw calls, and
  the in-game peak is already near 300). Firing position looking south 227k → 171k, trench looking
  north 366k → 242k; the overview (whole map in view) stays ~417k.
- Screenshots (tiles 1 vs 4) differ only by the same run-to-run noise as two runs of the same build.
- Test `tools/test_tr1.gd`: all 90,601 points drawn, 180,000 triangles, every point at exactly the
  collision height, shared edge points identical, no LOD, no shadow casting, and 2,000 rays down
  show the drawn triangles are the collision surface between the points too (same diagonal as Jolt's
  height field; worst 0.0000 m).
- **Owner tested and approved (2026-11-20), 4×4 kept.** Benchmark on his PC (Windows, Radeon 780M,
  High, 1904 × 1022): 474.9 FPS (2.11 ms), 1% low 360, worst 12.8 ms, draw calls 203 avg / 302 max,
  235k triangles (was 306–310k on 16 Nov), physics 1.84 ms. At 1280 × 720: 635.2 FPS, 192 / 306 draw
  calls, 225k triangles. The max draw calls are now a little over the README's 300 – accepted; win
  them back elsewhere (forest, props) before adding much new art.


## A7 – all tests with one command, and on every push (review item A7) (2026-11-20)
Owner asked whether to do it while the game is still developed: yes – that is when it pays.
**Owner decisions (2026-11-20):** the slow co-op soak (`soak_coop.gd`, ~3 min) stays out of the
automatic run (only by hand, "all"); no web export / web smoke test on GitHub for now.
- `tools/run_all.gd` + the list `tools/tests.cfg` (41 tests + `soak_coop` as manual). Each test in its
  own Godot; judged from its output, because most tests quit with code 0 even when a check fails.
  Details and the failure rules: `notes/tools.md` "Running all tests".
- `.github/workflows/tests.yml`: every push / pull request (not docs/, notes/, *.md only), Ubuntu,
  Godot 4.7.2 cached, import, xvfb, run_all; logs kept as a download when it fails. Changes nothing
  in the repo, GitHub Pages or the releases.
- Fixed a flaky check: `test_benchmark` counted the soldiers only at the end ("15 soldiers spawned").
- Cloud run 20 Nov 2026: 41 OK in 13.1 min (only ~3 min of it CPU – the tests wait on game time).
