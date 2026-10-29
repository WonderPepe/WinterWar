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
| Release mouse | Esc (click the game to capture it again) |
| Debug: god mode / enemy state labels | F1 / F2 |

## Folders
- `autoload/` – scripts that are always loaded (NetworkManager)
- `scenes/` – game.tscn (a match), player.tscn
- `levels/` – test_level.tscn (terrain, forest, trench, bunker)
- `scripts/` – all game code, grouped by topic
- `resources/` – materials, weapon data (`resources/weapons/*.tres`) and enemy data
  (`resources/enemies/*.tres`) – tune weapons and enemies here
- `ui/`, `assets/` – menus/HUD and art (later)

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
- [ ] M4: HUD, death/respawn, main menu
- [ ] M5: web export test and performance check
