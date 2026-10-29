# Winter War: Summa (prototype)

First-person shooter prototype set in the Winter War 1939–40, Battle of Summa.
Godot 4.7, GDScript, Compatibility renderer (so it can be exported to the web).

## Controls
| Action | Key |
|---|---|
| Move | W A S D |
| Look | Mouse |
| Sprint | Shift (uses stamina) |
| Crouch | C (or Ctrl – but avoid Ctrl in the browser, Ctrl+W closes the tab) |
| Jump | Space |
| Fire / aim down sights | Left mouse / right mouse |
| Reload | R |
| Mosin-Nagant / Suomi | 1 / 2 |
| Pause menu | Esc |
| Debug: god mode / enemy state labels / debug text | F1 / F2 / F3 |

## Running
- **F5** starts from the main menu. To jump straight into a match while testing, open
  `scenes/game.tscn` and press **F6** (Run Current Scene).

## Web version (browser)
1. **Once:** in Godot choose **Editor → Manage Export Templates → Download and Install** (~1 GB).
2. **Quick test:** click the 🌐 button at the top right of the editor (**Remote Debug → Run in Browser**).
   Godot starts a small local web server and opens the game in your browser.
3. **Export files:** **Project → Export… → Web → Export Project** → saves to `export/web/`.
   Opening `index.html` by double-clicking does **not** work (browsers block it from disk) –
   use step 2 or upload it.
4. **Share on itch.io (free):** create a new project, *Kind of project* = **HTML**. Zip the
   *contents* of `export/web/` (so `index.html` is at the top of the zip), upload it and tick
   **"This file will be played in the browser"**. Viewport 1280 × 720, enable the fullscreen
   button. "SharedArrayBuffer support" is not needed. Keep it as **Draft** (or *Restricted*)
   while testing – only you (and people you give the link/password to) can play it.

## Settings and benchmark
- **Settings** (main menu or Esc menu): graphics quality Low / Medium / High, mouse sensitivity,
  volume, fullscreen. Saved automatically. Browsers start on Medium, desktop on High.
- **Benchmark** (main menu): a fixed 60-second run with a 16-soldier attack. The result screen
  shows FPS, slowest frames, draw calls, triangles, script/physics time and memory.
  **Copy results** puts the text on the clipboard.

## Performance budget (measured in M5, High quality)
| | Now | Budget for future graphics |
|---|---|---|
| Draw calls per frame | ~180 average, ~250 max | ≤ 300 |
| Triangles per frame (incl. shadows) | ~250 000 | ≤ 400 000 |
| CPU: scripts / physics (16 enemies) | ~1–2 ms / ~2.5–4 ms (desktop) | ≤ 8 ms total in the browser |
| Download | ~40 MB (≈10 MB compressed) | ≤ 60 MB |
| Textures | none yet | ≤ 2048 px, VRAM-compressed |

## Editing the trench and bunker
They are built from CSG shapes in `levels/source/trench_csg.tscn` and baked into plain meshes
(`levels/baked/`) because CSG is slow to load in a browser. After editing the CSG scene, the
meshes and the navigation mesh must be re-baked (`tools/bake_csg.gd`, then `tools/bake_nav.gd`
– or ask Claude to do it).

## Folders
- `autoload/` – scripts that are always loaded (NetworkManager)
- `scenes/` – game.tscn (a match), player.tscn
- `levels/` – test_level.tscn (terrain, forest, trench, bunker)
- `scripts/` – all game code, grouped by topic
- `resources/` – materials, weapon data (`resources/weapons/*.tres`) and enemy data
  (`resources/enemies/*.tres`) – tune weapons and enemies here
- `ui/` – main menu, HUD, pause menu, theme (`ui/winter_theme.tres`)
- `assets/` – sounds (placeholders), art later

## Multiplayer-ready design
- Single player = host with no clients (OfflineMultiplayerPeer, our peer id is 1).
- Player nodes are named after their peer id. `PlayerInput` reads the keyboard/mouse;
  `Player` only reads `PlayerInput`, and only the host moves players.
- `MultiplayerSpawner` creates players; `MultiplayerSynchronizer` nodes sync input and state.
- Shooting: the owner's WeaponController decides when the trigger fires and plays effects,
  then calls `server_fire` on the host, which checks ammo/fire rate, raycasts and applies
  damage through `take_damage()`.

## Enemy navigation
Enemies walk on a pre-baked navigation mesh (`levels/test_level_navmesh.res`).
If you change the level (terrain, trench, trees), open `levels/test_level.tscn`,
select the **Navigation** node and click **Bake NavigationMesh** in the toolbar.

## Milestones
- [x] M1: project setup, input map, test level, player movement
- [x] M2: weapons and shooting
- [x] M3: enemy AI and wave spawner
- [x] M4: HUD, death/respawn, main menu
- [x] M5: web export test and performance check
