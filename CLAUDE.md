# CLAUDE.md – Winter War: Summa

Read this first. Each milestone gets its own chat; this file + `notes/` are the memory
between chats. Kept short on purpose: details live in `notes/` – read the note for the area
you work on. Update this file and the right note at the end of every milestone.

## The project
- FPS, Winter War 1939–40, Battle of Summa. Player is a Finnish soldier holding a trench against
  Soviet attacks. Long-term: real Summa terrain (Copernicus
  GLO-30 DEM – Finnish NLS data doesn't cover today's Russia), WebRTC co-op for 2–4 players.
- Godot **4.7.2**, **GDScript only**, **Compatibility renderer** (must export to web/HTML5), Jolt.
- Status: M1–M5, P1–P2, W1–W2, G1–G2, T1–T4 done (T4 = heavy hand-cranked turret), L1 (new trench line + 4 sandbag firing positions), L2 (bunker faces the enemy, trench behind, back door), + Controls screen / Molotov hint, B1 (10 battles with real dates, weather and briefings shown before each battle), B2 (loading screen with a marching soldier), B3 (weather and time of day per battle), A1 (air raid of three SB-2 bombers in battles 4 and 8); battles rebalanced (R1: air raid also in battle 10, tanks in 3/5/7) and a tank-route fix; public
  v0.5.0 on GitHub Pages. L3: two zigzag communication trenches to the rear (x = ±40) with the
  rear (re)spawn points, and battle 6 "retake the trench" (Soviets hold the west half first).
  W3: Suomi cocking handle pulled back + snaps forward when the gun needs cocking (first time
  out each life, empty-drum reload; never when firing), empty cases fly out to the right.
  V1: enemy muzzle flashes a little bigger/brighter + a brief tiny glow, scaled by the battle's darkness.
  D1: a lost battle can be retried and a run continued from the main menu (`RunSave`,
  `user://run.cfg`, saved at each battle held; statistics cover the whole run).
  P3 (review item P1): the 3D picture is capped at 1080 / 900 / 720 lines (High / Medium / Low)
  on big or high-density screens; Settings "3D resolution: Auto / Full".
  V2 (review item V2): soft snow over the box edges of the earthworks – lips on the trench
  edges, drifts at the wall foot, rounded heaps, bunker snow cap + side banks (picture only, no
  collision; `tools/earthwork_snow.gd`, node `EarthworkSnow`).
  V4 (review item V4): sandbags are sagging burlap pillows (texture + normal map, smooth normals)
  that press into each other, with a dark filling inside the wall (`SandbagCore`) – no daylight
  between the bags; collision and loophole unchanged.
  C1: climbing out of the trench – Space at a wall too high to jump onto (0.9–1.7 m) hauls the
  soldier over the edge in 1 s, hands busy (`ClimbHandler`, Player child `Climb`, synced
  `Player.is_climbing`); owner: not with a lit bottle, also from a crouch, no help text.
  T5: tanks and wrecks stop ENEMY bullets, shells, sight and the 45 mm blast too (physics layer
  5 "armour", `Tank.SIGHT_MASK` / `BULLET_MASK`) – a wreck is cover for the player.
  D9 (review item D9): hit zones for the player's bullets – head ×4, legs ×0.6, worked out from
  where on the soldier's one capsule the bullet lands (`Enemy.hit_zone_at`, numbers in
  `EnemyData`); a head shot adds a ring to the hit marker (`hit_confirmed(killed, zone)`).
  V10b (review item V10, steps 3–4): the fallen stay on the field – a body is handed to the
  `BodyKeeper` (node `Bodies`) 3 s after the fall, as a plain picture; caps 36 / 24 / 12 per
  quality, the newest 12 stay for the next day with a little snow on them – and tanks leave
  tracks (`TankTracks`, one MultiMesh of pooled strips, cleared at the day change).
  V10a (review item V10, steps 1–2): the spruces sway (vertex shader, TIME) and the clouds drift
  (`cloud_offset`, moved 8×/s by DuskLight – never TIME in the sky shader); strength from each
  battle's `WeatherData.wind`.
  T6: running tracks and turning wheels – `TrackAnimator` (tank child node, picture only, every
  computer by itself) reads the hull's real movement, left/right track = forward ∓ turn × half
  gauge; link picture slides (`tank_track.gdshader`, + snow/dirt), wheels turn around axles
  baked into the model's UV2 (`tank_wheels.gdshader`, `import_weapons.py --t26-wheels`).
  P4: web build loads the battle's files one by one with frames in between (no more 10 s
  "Page unresponsive" freeze while reading); photo + briefing fade away at the click prompt.
  S1: sky noise uses a whole-number hash – fix for straight seams / blocks on the sky in Chrome
  (Windows/AMD default path) – owner confirmed it works. Public v0.9.1 (P4 + S1).
  AR1: first-person arms in winter clothing – baggy folded ivory snow-smock sleeves, grey wool
  cuff, thick grey-ivory trigger-finger mittens, baked dirt/wear, own matte shader (one draw call);
  steps AR2–AR6 planned in project doc `claude/plan-arms-winter-clothing.md`.
  AR2: smooth elbow, twist spread, a moving trigger finger (outside the guard / on the guard /
  on the trigger / round the knob), Maxim thumbs press while firing.
  AR3: Mosin bolt hand palm-down over the knob (turns a third, curved path), Suomi left hand
  cups the drum's front-lower edge.
  GR1: Soviet hand grenades – riflemen/officers carry 1–2 F-1s, throw them (6–28 m) at a Finn seen /
  heard a moment ago, also at the bunker's firing hole / back door; host works out the whole bouncing
  flight and sends it to everyone; blast needs a clear line (trench wall / bunker / wreck protect);
  friendly fire; max 2 live, 4 s apart; HUD grenade icon only (`GrenadeManager`, `GrenadeWarning`).
  GR2: F next to a live grenade (1.5 m) snatches it up and throws it back (~20 m, fuse keeps running,
  kills count for you; `GrenadeGrabHandler`, child `GrenadeGrab` made in code); [F] key on its icon;
  end screen + saved run count "Grenades thrown back".
  GR3: in the trench a soldier throws only round a corner (a Finn he can't see but knows of, ≥ 8 m).
  NET1 (review item A1, step 1): co-op over ENet – Host / Join Co-op lobby (desktop only, port
  7777, 2–4), load gate (host waits paused until every computer has loaded), launch options
  `--coop-host` / `--coop-join` / `--coop-wave=N` for two windows on one PC; co-op never touches the
  saved run.
  NET2 (A1 step 2): `tools/soak_coop.gd` scenario + `notes/coop-issues.md`; the next battle waits
  until every player closed his day screen; host's end screen "Retry battle n" / "New game" for all;
  host's Main menu warns it ends the battle for everyone; free respawn spot; `--mute`.
  NET2b: the other players are Finnish soldiers, not grey capsules (`PlayerBody`, Player child `Body`
  made in code, own body hidden; mesh `FinnMesh` – M/39 fur hat, dirty off-white snow smock + trousers,
  Mosin / Suomi – on the Soviets' skeleton; posed only from state already synced; shared arm IK
  `SoldierMesh.reach`).
  NET3: Soviets, tanks and other players glide on a guest's computer (`NetSmoother`, child
  `Smoother`; StateSync sends `Smoother:net_position/net_quat` + `net_stamp` LAST; ~35 ms delay on a
  LAN, own player never delayed; lag simulator `--net-lag/--net-jitter/--net-loss`).
  EX1: Windows desktop export preset (`.exe` + `.pck`, unsigned) for co-op with a friend on the same
  network – private builds, not releases (RELEASES.md "Windows build", `tools/windows_readme.txt`).
  TR1 (review item P3): the drawn ground is 4 × 4 tiles (`GroundTiles`) so tiles behind you are
  skipped – ~28 % fewer triangles on the benchmark flight; never LOD on the ground (owner: far
  soldiers must not look sunk in / floating); collision + navmesh unchanged.
  A7 (review item A7): `tools/run_all.gd` runs every test in `tools/tests.cfg` in its own Godot,
  judges the output (FAIL lines, script errors, missing end line, time limit), exit code 1 on a
  failure; GitHub Actions runs it on every push (not the manual co-op soak, no web export) –
  first GitHub run green (20 Nov 2026).
  TC1: Soviets in the trench at the limit (6 on every difficulty) start a 30 s countdown – kill them
  below it and the clock resets, run out and the line is broken; no hard cap (`breach_time_left`).
  Next: owner's choice – online co-op ON0–ON5 (plan in Claude Docs, project doc
  `claude/plan-online-coop.md`), AR4 (reloads: Mosin stripper clip, grey cuff reveal), the v0.6.0
  review's list (project doc `claude/review-2026-11-12.md`: U3, U4, D6, P2, V5, …) or wreck cover /
  field cover (idea 0). See `notes/milestones.md`.

## Working with the owner
- **Privacy:** never put the owner's real name, e-mail or personal details in any project file,
  comment, commit or build. Commits may be authored as `Claude <noreply@anthropic.com>` or as
  the owner's pseudonym `WonderPepe` (repo-local git config) – never with his real name or e-mail.
- Total beginner (coding + Godot): explain important concepts briefly, in plain words.
- Before code for a milestone: show a short plan + node tree and **wait for approval**.
- One milestone at a time, then stop with exact test steps in Godot, then a git commit with a
  clear message. He pushes with GitHub Desktop. Releases only when asked (see RELEASES.md).
- Check `git status` before writing files – never overwrite his own edits.
- If something can't be done well in the web export, say so and suggest an alternative.
- Never reword the owner's own texts (front reports, day-screen texts). Respect recorded owner
  decisions in the notes (e.g. Easy only has fewer riflemen; officers/MGs never change).

## Session setup (Cowork: cloud workspace + owner's computer)
- Get the repo into the cloud: on his computer `git bundle create "Claude outputs/repo.bundle" --all`
  → stage it → `git clone` in the cloud (the bundle is ~60 MB and staging can time out: if his
  `git rev-parse HEAD origin/main` are equal and `git status` is clean, clone the public GitHub
  repo instead). Godot 4.7.2 Linux + Web export templates from
  github.com/godotengine/godot/releases (into `~/.local/share/godot/export_templates/4.7.2.stable/`);
  xvfb for screenshots/GL; Python Playwright for `tools/web_smoke_test.py`.
- Run builder/tests/exports in the cloud copy; deliver changed files as a zip → unzip in his
  folder → `git status`. Cloud commits are scratch only.
- `build_scenes.gd` gives scenes new random `unique_id`s: restore files whose ONLY change is
  `unique_id` lines (`git show HEAD:file > file`) – never binary files (`git diff --numstat`
  shows `-`), or the baked meshes / navmesh are lost. It overwrites scenes: once the owner edits
  a scene in the editor, edit the .tscn instead unless he agrees.
- Git in his folder needs delete permission (lock files): ask once per chat before committing.
  `git fsck` "unable to mmap" errors there are a mount quirk, objects are fine.
- freesound.org is not reachable from the cloud – the owner downloads sounds into `assets_source/`.
- Clean up your temporary files in `Claude outputs/` at the end.

## Commands
- All tests (A7): `godot --headless --path . --script tools/run_all.gd` (in the cloud under
  `xvfb-run -a` so `test_mouse` gets a window; `-- --quick`, `-- --only t5,d9`, `-- --all`). List +
  time limits: `tools/tests.cfg` – **a new test gets a line there**. Logs: `tools/test_logs/`.
  **Run all tests before every commit.** GitHub runs the same on every push
  (`.github/workflows/tests.yml`, ✅ / ❌ beside the commit).
- One test: `godot --headless --path . --script tools/run.gd -- tools/test_m1.gd` (plain Nodes via
  the launcher, because `--script` files compile before autoloads exist). Tools: `notes/tools.md`.
- New `class_name` or new audio files: run `godot --headless --import` first.
- Windows export: `godot --headless --path . --export-release "Windows Desktop" export/windows/WinterWarSumma.exe`
  (`mkdir -p export/windows` first; needs the windows templates).
- Web export (`mkdir -p export/web` first in a fresh clone): `godot --headless --path . --export-release "Web" export/web/index.html`, then
  `python3 tools/web_smoke_test.py` and `tools/check_web_pack.gd`.
- Shader errors only show with a real GL window (xvfb + `--rendering-driver opengl3`).

## Rules that are easy to break
- Multiplayer-ready always: single player = host (peer 1); host is authority for AI, hits,
  damage, spawning, game state; use the `players` group, never a "the player" singleton; UI only
  reads state. Details: `notes/architecture.md`.
- Synced enums (Enemy State, Tank State, Molotov phase…): add new values at the END.
- Positions of things the host moves are synced through their `Smoother` (`Smoother:net_position`),
  never `.:position`; `Smoother:net_stamp` stays the LAST synced property (NET3).
- `@export` PackedStringArray defaults must be `= PackedStringArray()`, not `[]` (export bug).
- Every new particle effect must go through `ImpactEffects.web_fallback()` (particle colours
  render black in WebGL / on AMD).
- New `project.godot` settings, autoloads or `class_name`s: tell the owner **Project → Reload
  Current Project**.
- Level geometry changed → re-bake the navmesh (`Navigation` in `levels/test_level.tscn`).
- Keep new art within the README's performance budget; web limits: `notes/graphics-and-web.md`.

## Notes index (`notes/`, ignored by Godot)
- `milestones.md` – milestone history, owner decisions per milestone, development ideas
- `coop-issues.md` – co-op: what works, what breaks, status (NET2)
- `architecture.md` – multiplayer architecture, co-op connection + load gate (NET1) + retry / day-screen hold (NET2), conventions, groups, physics layers, map coordinates
- `graphics-and-web.md` – web export limits, quality presets, P1 graphics (sky, snow, forest LOD), weather per battle (B3), motion: spruce sway + cloud drift (V10a), ground tiles (TR1)
- `weapons.md` – Mosin/Suomi view models, Maxim, first-person arms (W1, W2, AR1 clothing), Suomi cocking handle + cases (W3), hit zones (D9)
- `soldiers-effects-sound.md` – soldier mesh/poses, impact effects, audio buses, background sounds, bodies that stay (V10b), Finnish soldier body for the other players (NET2b)
- `battle.md` – MatchDirector, assault, ammo/bandages, dusk, waves, suppression, officers, MGs, artillery, air raid (A1), saved run / retry / continue (D1), hand grenades (GR1) + throwing them back (GR2) + round a corner in the trench (GR3), trench countdown (TC1)
- `day-screen.md` – battle briefings (B1), photos, day screen
- `tank-and-molotov.md` – T-26 tank (T1), Molotov cocktail (T2), tanks in the waves (T3), turret feel (T4), armour stops enemy fire (T5), climbing out of the trench (C1), tank tracks (V10b), running tracks + turning wheels (T6)
- `gotchas.md` – full list of lessons learned
- `tools.md` – helper tools and tests
