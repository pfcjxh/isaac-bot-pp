# Isaac Bot PP

Single-player autopilot mod for *The Binding of Isaac: Repentance* (Lua). A heavily extended
fork of [netlesha/isaac-bot](https://github.com/netlesha/isaac-bot) (MIT).

中文说明：[README.zh.md](README.zh.md)

## What it does

The bot plays a normal run on its own: it explores the floor, clears rooms, dodges projectiles,
picks what is worth picking, opens rooms it can open, fights bosses, and logs everything it
decides so the behaviour can be tuned from the log afterwards.

It does **not** use a neural network. Everything is heuristic: a room graph, a Dijkstra grid,
a short-horizon dodge simulation, per-weapon firing profiles and a small amount of learned
enemy threat data (see [Learning](#learning)).

## Highlights

| Area | Behaviour |
|---|---|
| Navigation | Whole-floor room graph (treasure / shop / secret / devil / angel / challenge / arcade ranked by interest) + Dijkstra pathing on the room grid |
| Combat | Weapon-aware firing spots (tears, charge, melee, steer) and short-horizon dodge for projectiles, lasers, bombs and hands |
| Knights | Front shield: attacks from behind, engine direction calibration, bomb fallback |
| Hosts | Stop firing, cross the room and wait until the shell opens |
| Globins | Finish the goo before it regenerates |
| Bosses | Summoners: adds first; close-range punishers: keep distance; burst bosses: spend bombs/actives earlier |
| Cards | Carries only known-good cards, uses them in fights (boss first) or for healing, swaps for a better one |
| Pills | Never picked, never used (unknown effect, conservative) |
| Shop | Quality-gated items, hearts/batteries with a coin buffer, keys/bombs only when low |
| Chests | Golden chest always, key chests with 3+ keys, red chests with enough health |
| Clean-up | Fireplaces, poop, tinted / super tinted / gold rocks; gives up on blue/white fires and blocked targets |
| Spikes | Reads retract state, steps only on retracted spikes, steps off a rising one, force-crosses after 3 s without progress |
| Secret rooms | Finds undiscovered ones from level data, bombs the shared wall, walks in |
| Boss prep | Uses a healing card before entering a boss room when low |
| Learning | Counts hits taken per enemy type across runs; dangerous types are killed first and fought from farther away |

## How it works

```
MC_POST_UPDATE
   └─ brain.update
        ├─ read room / player / entities
        ├─ grid.build        (walkable map, rocks, fires, spikes, chests)
        ├─ grid.flood        (Dijkstra costs from the player)
        ├─ danger.collect    (projectiles, lasers, bombs, creep, hands)
        └─ choose one goal: fight / plate / loot / card / sweep / secret / door / exit
             └─ danger.choose (simulate 8 directions, pick the safest)
                  └─ B.move / B.shoot / B.tap  → MC_INPUT_ACTION
```

More detail: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## F8 menu

- Run switch (same as F9), goal, character, six behaviour toggles.
- Preset system: built-in presets (Standard / Mom Speedrun / Azazel to Lamb) plus your own.
- Priority and exclusion lists for collectibles, with the item catalogue and search.
- All settings persist in the mod save.

Menu text is English on purpose: the game's CJK pixel font in the current builds has advance
widths but no real glyphs, so non-ASCII text renders as boxes.

## Install

1. Copy this repository to
   `...\The Binding of Isaac Rebirth\mods\isaac_bot\`.
2. Enable mods (main menu → Mods) and run in the console:
   ```
   luamod isaac_bot
   ```
3. The bottom-left line shows `PP | <state> <detail>   F8 Menu` when loaded.

## Controls

| Key | Action |
|---|---|
| F8 | settings menu |
| F9 | bot on / off (Off = no input at all) |
| F7 | next preset |

## Learning

Every hit taken is attributed to the attacking enemy type (`type.variant`) and persisted in the
mod save. A type that hits the bot often is prioritised and approached from farther away; deaths
are attributed to the last attacker. Events: `learn_hit`, `learn_death`.

This is a threat model, not a move database. Boss-specific move patterns are added per boss on
request (see [docs/BOSSES.md](docs/BOSSES.md)).

## Logs and events

The mod writes `[IsaacBot] EV {...}` lines to `log.txt`. Full reference:
[docs/EVENTS.md](docs/EVENTS.md).

## Development

- Module map and data flow: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Extending (bosses, cards, enemies, rooms): [docs/DEVELOPING.md](docs/DEVELOPING.md)
- Contributing: [CONTRIBUTING.md](CONTRIBUTING.md)
- Sync the live mod folder into this repo: `tools/sync-from-game.sh`

## Roadmap

- More boss move patterns (Mom, Isaac, Hush, Delirium, The Beast...).
- Sacrifice room policy.
- Secret-room wall detection without level data (visual).
- Better active-item value model.

## License

MIT. The original project's copyright notice is kept in [LICENSE](LICENSE); upstream projects are
listed in [CREDITS.md](CREDITS.md).

## Disclaimer

Single-player only. Mods disable achievements in game; that is a game limitation, not this project's.
