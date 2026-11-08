# CLAUDE.md – Winter War: Summa

Read this first. Each milestone gets its own chat; this file + `notes/` are the memory
between chats. Kept short on purpose: details live in `notes/` – read the note for the area
you work on. Update this file and the right note at the end of every milestone.

## The project
- FPS, Winter War 1939–40, Battle of Summa. Player is a Finnish soldier holding a trench against
  Soviet attacks. Long-term: real Summa terrain (Copernicus
  GLO-30 DEM – Finnish NLS data doesn't cover today's Russia), WebRTC co-op for 2–4 players.
- Godot **4.7.2**, **GDScript only**, **Compatibility renderer** (must export to web/HTML5), Jolt.
- Status: M1–M5, P1–P2, W1–W2, G1–G2, T1–T4 done (T4 = heavy hand-cranked turret), L1 (new trench line + 4 sandbag firing positions), L2 (bunker faces the enemy, trench behind, back door), + Controls screen / Molotov hint, B1 (10 battles with real dates, weather and briefings shown before each battle); public
  v0.2.x on GitHub Pages.
  Next: owner's choice (wreck cover / field cover is idea 0). See `notes/milestones.md`.

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
  → stage it → `git clone` in the cloud. Godot 4.7.2 Linux + Web export templates from
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
- Tests: `godot --headless --path . --script tools/run.gd -- tools/test_m1.gd` (plain Nodes via
  the launcher, because `--script` files compile before autoloads exist). **Run all tests
  before every commit.** List: `notes/tools.md`.
- New `class_name` or new audio files: run `godot --headless --import` first.
- Web export (`mkdir -p export/web` first in a fresh clone): `godot --headless --path . --export-release "Web" export/web/index.html`, then
  `python3 tools/web_smoke_test.py` and `tools/check_web_pack.gd`.
- Shader errors only show with a real GL window (xvfb + `--rendering-driver opengl3`).

## Rules that are easy to break
- Multiplayer-ready always: single player = host (peer 1); host is authority for AI, hits,
  damage, spawning, game state; use the `players` group, never a "the player" singleton; UI only
  reads state. Details: `notes/architecture.md`.
- Synced enums (Enemy State, Tank State, Molotov phase…): add new values at the END.
- `@export` PackedStringArray defaults must be `= PackedStringArray()`, not `[]` (export bug).
- Every new particle effect must go through `ImpactEffects.web_fallback()` (particle colours
  render black in WebGL / on AMD).
- New `project.godot` settings, autoloads or `class_name`s: tell the owner **Project → Reload
  Current Project**.
- Level geometry changed → re-bake the navmesh (`Navigation` in `levels/test_level.tscn`).
- Keep new art within the README's performance budget; web limits: `notes/graphics-and-web.md`.

## Notes index (`notes/`, ignored by Godot)
- `milestones.md` – milestone history, owner decisions per milestone, development ideas
- `architecture.md` – multiplayer architecture, conventions, groups, physics layers, map coordinates
- `graphics-and-web.md` – web export limits, quality presets, P1 graphics (sky, snow, forest LOD)
- `weapons.md` – Mosin/Suomi view models, Maxim, first-person arms (W1, W2)
- `soldiers-effects-sound.md` – soldier mesh/poses, impact effects, audio buses, background sounds
- `battle.md` – MatchDirector, assault, ammo/bandages, dusk, waves, suppression, officers, MGs, artillery
- `day-screen.md` – battle briefings (B1), photos, day screen
- `tank-and-molotov.md` – T-26 tank (T1), Molotov cocktail (T2), tanks in the waves (T3), turret feel (T4)
- `gotchas.md` – full list of lessons learned
- `tools.md` – helper tools and tests
