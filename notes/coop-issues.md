# Co-op: what works, what breaks (NET2, 18 Nov 2026)

Found with `tools/soak_coop.gd` (two headless copies, player 2 does everything; 72 checks since
NET2) and a
code read. Keep this list up to date as co-op work goes on.

## Works for player 2 (checked by soak_coop.gd)
- Own camera, own first-person gun, own body hidden; HUD follows his own soldier.
- Walking, Mosin shot, reload, switch to the Suomi + burst (first burst of a life cocks first, W3).
- Maxim: on / fire / off, belt count on his screen.
- Molotov: take from the box, bottle in the hand, light (right mouse), throw, bottles left.
- Grenade lands next to him: [F] mark, grab, throw back, his "thrown back" count.
- Climbing out of the trench; hurt (health bar, red flash), bandage; death screen, respawn after
  5 s at the rear, gun back.
- Battle held: day screen opens and closes for him too (within 0.2 s when nobody presses keys);
  countdown to the next battle (fixed in NET1).
- Defeat: end screen, no "Play again" in co-op. Kills, deaths, bandages, ammo are all synced.
- No script errors in either copy. Soviets, tanks, bombs, shells and grenades already pick from
  every player (the `players` group).

## Breaks / missing (status after NET2)
1. **Open – NET2b.** **The other player is a grey capsule** (`BodyMesh`): no soldier, no gun, and it never turns
   (Player `rotation` is not synced – mode 0; his view direction `look_yaw` is).
2. **Fixed (NET2).** **Day screen + Space:** the host's Space closes the host's screen and starts the countdown
   (5 s) while player 2 may still be reading; his screen is then closed by the next battle. Player
   2's Space changes nothing for the battle. Now every computer tells the host when its own day
   screen opens / closes (`WaveSpawner.set_reader_hold`); the countdown waits for all, the HUD says
   "Battle n – waiting for the others to read the briefing" (`waiting_for_readers`, synced).
3. **Fixed (NET2).** **Respawn spot:** two players who die close together can come back on the same rear spot.
4. **Fixed (NET2).** **Join refused** once the battle runs: now "Could not reach the host – or the
   battle has already started."
5. **Fixed (NET2).** **Two windows on one PC** play every sound twice: launch option `--mute`.
6. **Fixed (NET2, owner: yes).** **No retry in co-op:** now the host's end screen has "Retry battle n"
   (defeat) / "New game" (victory) for everyone; the others see "Waiting for the host…".
   Statistics start again with the retried battle (the saved run stays single player only).
7. **Fixed (NET2, owner: ok).** The host's "Main menu" (pause / end screen) ended the battle for
   everyone without a word: now a line "Main menu ends the battle for everyone."

## Not checked yet (needs the owner's two-window test)
- How movement feels for player 2 (host decides his position; one round trip of delay).
- Sound of the other player's shots / footsteps, effects seen from the other window.
