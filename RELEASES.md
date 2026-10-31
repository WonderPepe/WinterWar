# Releases – the playable browser version

Players play a **released version** on itch.io. Development continues in this repository; the
public version only changes when a new release is uploaded.

## How a release works
1. Finish and test a milestone (all tests pass, it plays well).
2. Raise the version in `tools/setup_project.gd` (`application/config/version`, e.g. 0.1.0 → 0.2.0),
   run it, and add a line to the list below.
3. Export the web build: `godot --headless --path . --export-release "Web" export/web/index.html`
   (or in the editor: Project → Export → Web → Export Project).
4. Zip the **contents** of `export/web/` (index.html must be at the top of the zip, not inside a
   folder) as `releases/WinterWarSumma-v<version>-web.zip`. The `releases/` folder is not in git.
5. Commit, then tag the commit with the version (`v0.2.0`) so this exact version can always be
   rebuilt: in GitHub Desktop, History → right-click the commit → Create Tag.
6. Upload the zip on the itch.io page (Edit game → Uploads), tick "This file will be played in the
   browser", and delete or hide the previous web upload. Players get the new version immediately.

## itch.io page settings (first time)
- Kind of project: **HTML**. Upload the zip, tick "This file will be played in the browser".
- Embed options: viewport **1280 × 720**, tick **Fullscreen button**, "Click to launch in
  fullscreen" optional. "SharedArrayBuffer support" is **not** needed (the game is exported
  without threads).
- Visibility: **Draft** while testing (only you can open it), later **Restricted** (people with the
  link / a password) or **Public**.
- Use a pseudonym account; the game itself contains no personal information.
- Credits: the page description must name the 3D model authors (see `CREDITS.md`, CC-BY 4.0).

## Versions
| Version | Content |
|---|---|
| 0.1.0 | First public test: Mosin, Suomi, Maxim with overheating; Soviet waves; hold the trench until dusk (Easy / Normal / Hard); ammo crates, bandages; snow-camo arms. |
