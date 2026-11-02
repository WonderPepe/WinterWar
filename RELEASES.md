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
| 0.2.4 | DP-27 machine-gun teams follow their riflemen 5–10 m behind, open fire from 80–130 m off the trench and move up in bounds; when all the riflemen are dead they storm the trench too (no more hunting for the last enemy). Loading screen: only the tip and "Click to start the battle" at the end. |
| 0.2.3 | Browser: closing the tab during a battle (Ctrl+W – easy to hit with W + Ctrl) first asks "Leave site?"; in fullscreen (Chrome/Edge) Ctrl+W is blocked and Esc must be held to leave fullscreen (a notice says so). Fixes: soldiers no longer stop far from the trench after a match was left during an artillery barrage; the crew of a burning tank now count as enemies of the battle. |
| 0.2.2 | Controls screen (main menu and pause menu) listing every key; tanks stop 3 m closer to the trench; in the first tank battle a hint shows where the Molotov cocktails are and how to throw them. |
| 0.2.1 | Fix: the Credits list scrolls, so Back (or Esc) closes it again. |
| 0.2.0 | Ten battles with front reports and SA-kuva photos between them; officers, DP-27 machine-gun teams, suppression and artillery barrages; T-26 tanks from battle 4 (two in battles 9–10) and Molotov cocktails to stop them; Suomi drum change, aiming fixes. |
| 0.1.2 | Browser: "Click to start the battle" at the end of loading instead of the pause menu. |
| 0.1.1 | Loading screen with a progress bar and tips between the main menu and the battle. |
| 0.1.0 | First public test: Mosin, Suomi, Maxim with overheating; Soviet waves; hold the trench until dusk (Easy / Normal / Hard); ammo crates, bandages; snow-camo arms. |
