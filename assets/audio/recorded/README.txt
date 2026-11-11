Real sound recordings for the game (used automatically, by file name):

  reload_mosin...   reloading the Mosin-Nagant (stripper clip pushed into the magazine)
  reload_suomi...   changing the Suomi's drum magazine
  reload_maxim...   loading a new cloth belt into the Maxim
  bolt_mosin...     working the Mosin's bolt after each shot (open - back - forward - close)
  cock_suomi...     pulling the Suomi's cocking handle back and letting it snap forward
                    (the loud clack 0.12 s into the file; cut from freesound 676588, CC0)
  hurt...           you get hit - put 3-5 different ones (hurt_1.ogg, hurt_2.ogg, ...),
                    the game picks one at random each time
  officer_whistle...  a Soviet officer's whistle (G2; a generated placeholder is used until then)
  dp27...           one DP-27 machine-gun shot (G2; the Maxim placeholder, pitched up, until then)
  telegraph...      teleprinter / typewriter clatter while a front-report telegram types itself out
                    (stops when the text is finished; silent if there is none)
  tank_gun... / tank_dt... / ricochet...  the T-26's 45 mm gun / DT machine gun (replace the
                    cuts in assets/audio/tank/), bullets glancing off armour (silent until added)
  mg_cover...       machine-gun bullets hitting sandbags / the bunker
  molotov_ignite... lighting the rag (T2)      molotov_throw...  the bottle leaving the hand
  molotov_break...  glass breaking + fuel catching fire
  fire_loop...      burning fuel / a burning tank - set "Loop" on in its import settings
                    (the four Molotov sounds are made by tools/make_molotov_sounds.py)

  raid_engine...    A1 air raid: a bomber flying over (loudest moment after N s: set
                    AirRaid.engine_overhead_at; default is the existing plane recording)
  raid_whistle...   A1: a bomb falling. Should END at the impact (about 2-4 s long)
  raid_boom...      A1: a big bomb exploding, deep, with a long rumble
                    (several files = a random one per bomb; silent if there is none)

.ogg is best (small). Keep each file short and trimmed (no silence at the start).
Good free sources:
  - Freesound.org: search e.g. "mosin reload", "rifle stripper clip", "magazine change",
    "ammo belt", "grunt pain male". Filter by licence "Creative Commons 0" (CC0) if you
    don't want to credit anyone; CC-BY sounds must be listed in CREDITS.md.
  - Sonniss "GameAudioGDC" bundles (free, royalty-free, no credit needed): large
    weapon-foley and voice sets.
  - Kenney.nl "Impact Sounds" / "RPG Audio" (CC0): body hits, cloth, metal clicks.
  - Record yourself: a grunt or short breath for "hurt", and metal clicks (a lock, keys,
    a stapler) layered together for reloads. A phone is enough.
