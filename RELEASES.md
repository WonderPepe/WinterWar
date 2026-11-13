# Releases – the playable browser version

**Play:** https://wonderpepe.github.io/WinterWar/

The game people play is the released build in the `docs/` folder, served by GitHub Pages
(Settings → Pages → Deploy from a branch → `main`, folder `/docs`). Development goes on in the
rest of the repository; the public game only changes when `docs/` is replaced with a new release.

## How a release works
1. Finish and test a milestone (all tests pass, it plays well).
2. Raise the version in `tools/setup_project.gd` (`application/config/version`, e.g. 0.1.0 → 0.2.0),
   run it, and add a line to the list below.
3. Export the web build: `godot --headless --path . --export-release "Web" export/web/index.html`
   (or in the editor: Project → Export → Web → Export Project).
4. Replace the files in `docs/` with the new `export/web/` files (keep `docs/.nojekyll` and
   `docs/.gdignore`). Also keep a zip in `releases/WinterWarSumma-v<version>-web.zip`
   (not in git – it can be uploaded to itch.io too).
5. Commit ("Release v0.2.0"), tag the commit (`v0.2.0`, in GitHub Desktop: History → right-click
   the commit → Create Tag) and **Push origin**. About a minute later the link plays the new version.

Notes:
- `docs/.nojekyll` tells GitHub Pages to serve the files as they are.
- `docs/.gdignore` keeps the Godot editor from importing the exported files.
- The game is exported without threads, so no special web-server headers are needed.
- The 3D models are CC-BY 4.0: their authors are credited in the game (Credits) and in `CREDITS.md`.

## Versions
| Version | Content |
|---|---|
| 0.7.0 | A lost battle can be retried: "Retry battle" on the end screen starts the same battle again, and "Continue" in the main menu goes on with a saved run from the last battle held (statistics cover the whole run and count the retries). Enemy muzzle flashes are a little bigger and brighter with a brief glow at dusk and at night, so you can see where the fire comes from. Big and high-density screens (1440p, 4K, phones) run smoother: the 3D picture is drawn at most 1080 / 900 / 720 lines high (High / Medium / Low) and scaled up, menus and HUD stay sharp; Settings "3D resolution: Auto / Full". |
| 0.6.0 | Two zigzag communication trenches lead from the line back into the forest; after dying you respawn at their far end. Battle 6 "retake the trench": the Soviets hold the west half of the line, you start at the rear and must clear it before their counterattack, in the dark of the morning. Suomi KP/-31: the cocking handle is pulled back and snaps forward when the gun needs cocking (first time you take it out, and after an empty drum) with a real cocking sound; empty cases fly out to the right when firing. |
| 0.5.0 | The ten battles are rebalanced: more riflemen in every battle, tanks in battles 3, 5 and 7, artillery in battles 5–8 and 10, and the air raid also comes in battle 10 (4, 8 and 10). New briefing for battle 2. Fix: a new tank no longer drives into or on top of a destroyed one; it takes a route without a wreck. Machine-gun bullets hitting sandbags and the bunker have their own sound; dead soldiers' rifles lie flat on the ground. |
| 0.4.0 | Ten battles with real dates (30 Nov 1939 – 15 Feb 1940): a briefing with an SA-kuva photo, date, weather and text before every battle (on the loading screen for battle 1, between battles for the rest). New loading screen with a marching soldier, falling snow and loading phrases. Every battle has its own weather and time of day: moonlit twilight, clear, smoke, overcast, dense fog (clearing during battle 8), low cloud, dusk in the last battle. Fog and snow limit how far the enemy can see. |
| 0.3.0 | New trench line with many short legs and corners, four narrow one-soldier firing positions with sandbag loopholes, and the log bunker turned to face the enemy: trench behind it with a back door, the Maxim behind a narrow firing hole (±21°). The bunker room is a safe zone for artillery, except the gunner on the Maxim. |
| 0.2.6 | Artillery barrages are much more dangerous and dramatic: distant guns are heard 6.5 s before the first shell lands, shells bursting close to you have a loud explosion, bigger blasts and screen shake, shrapnel reaches 35 m (6 m = instant death). Only crouching in the trench is safe, and in the bunker only its two back corners. Also: ricochet sounds for bullets hitting metal and stone, new Suomi gunshot. |
| 0.2.5 | The T-26 turret is now heavy and hand-cranked: it turns slowly (4 / 8 / 12°/s), speeds up and brakes over 1.5 s, the crew needs a moment to react to a new target (more if you get behind the tank), and it can't keep up with a player running close to it – so side and rear Molotov attacks are easier. Gear, hand-crank and metal-clunk sounds. |
| 0.2.4 | DP-27 machine-gun teams follow their riflemen 5–10 m behind, open fire from 80–130 m off the trench and move up in bounds; when all the riflemen are dead they storm the trench too (no more hunting for the last enemy). Loading screen: only the tip and "Click to start the battle" at the end. |
| 0.2.3 | Browser: closing the tab during a battle (Ctrl+W – easy to hit with W + Ctrl) first asks "Leave site?"; in fullscreen (Chrome/Edge) Ctrl+W is blocked and Esc must be held to leave fullscreen (a notice says so). Fixes: soldiers no longer stop far from the trench after a match was left during an artillery barrage; the crew of a burning tank now count as enemies of the battle. |
| 0.2.2 | Controls screen (main menu and pause menu) listing every key; tanks stop 3 m closer to the trench; in the first tank battle a hint shows where the Molotov cocktails are and how to throw them. |
| 0.2.1 | Fix: the Credits list scrolls, so Back (or Esc) closes it again. |
| 0.2.0 | Ten battles with front reports and SA-kuva photos between them; officers, DP-27 machine-gun teams, suppression and artillery barrages; T-26 tanks from battle 4 (two in battles 9–10) and Molotov cocktails to stop them; Suomi drum change, aiming fixes. |
| 0.1.2 | Browser: "Click to start the battle" at the end of loading instead of the pause menu. |
| 0.1.1 | Loading screen with a progress bar and tips between the main menu and the battle. |
| 0.1.0 | First public test: Mosin, Suomi, Maxim with overheating; Soviet waves; hold the trench until dusk (Easy / Normal / Hard); ammo crates, bandages; snow-camo arms. |
