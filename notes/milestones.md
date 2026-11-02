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
- [x] Controls screen + tank 3 m closer + Molotov hint (owner): a **Controls** button in the
  main menu and the pause menu opens `ui/controls_panel.tscn` (`ControlsPanel`, rows filled from
  the Input Map – change a key there and the list follows; F-key test keys only in the editor;
  Back / Esc close it). Tanks park 3 m closer (routes end at z = 49, gun depression −14°). The
  first tank battle shows a Molotov hint after its banner. Details: `tank-and-molotov.md`.

- [x] Bug fixes from the code review (2026-11-01, owner asked for 1 and 2): artillery hold line
  no longer survives into the next match (`battle.md`); bailed-out tank crews count as soldiers
  of the battle (`tank-and-molotov.md`). Review leftovers (not approved): bandage usable at
  99 HP, Space closes the day screen AND jumps, rifle fire timing / corpse timers use real time, "last enemy" hunt for a hidden
  MG team, respawn next to Soviets in the trench, soldiers walk through Molotov fires,
  FOV / invert-Y options.

- [x] Ctrl+W guard in the browser (2026-11-02, owner chose the warning + true blocking in
  fullscreen + an info notice): "Leave site?" while a battle runs, Keyboard Lock in fullscreen
  (Chrome/Edge), "hold Esc to leave fullscreen" notice. Crouch keeps Ctrl AND C (owner didn't
  pick the key change). Reaches players only with the next release. See `graphics-and-web.md`.

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
