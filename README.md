# Isaac Bot PP

Single-player autopilot mod for *The Binding of Isaac: Repentance*, written in Lua. A heavily
extended fork of [netlesha/isaac-bot](https://github.com/netlesha/isaac-bot) (MIT).

Chinese documentation: [README.zh.md](README.zh.md).

## Features

- **Navigation**: whole-floor room graph plus Dijkstra grid pathing; treasure, shop, secret,
  devil/angel, challenge and arcade rooms ranked by interest.
- **Combat**: weapon-aware firing spots (tears / charge / melee / steer) and a short-horizon
  dodge simulation for projectiles, lasers, bombs and stomps.
- **Enemy knowledge**
  - Knights: front shield, back-of-the-head weak spot (engine direction calibration + bomb fallback).
  - Hosts and other "shell / stand up" enemies: stop firing, cross the room, wait for the opening.
  - Globins: finish the goo before it regenerates.
  - Boss tactics: summoners clear adds first; close-range punishers are fought from farther away.
- **Enemy experience (learning)**: every hit taken from an enemy type is counted and persisted in
  the mod save. Types that keep hurting the bot are killed first and approached from farther away;
  deaths are attributed to the last attacker. Logs: `learn_hit`, `learn_death`.
- **Loot**
  - Cards: only useful ones are carried (Death / Chariot / High Priestess / Empress / Magician /
    Strength / Sun / Hierophant / Lovers / World / Moon / Star / Judgement / Wheel), used in combat
    (boss first) or for healing; a better card on the floor makes the bot drop the held one and swap.
  - Pills are never picked or used (unknown effect, conservative).
  - Shop: quality ≥ 1 if affordable, hearts and batteries with a coin buffer, keys/bombs only when low.
  - Chests: golden always, key chests only with 3+ keys, red chests with enough health.
- **Room clean-up**: put out fireplaces, break poop, bomb tinted / super tinted / gold rocks;
  give up on blue/white fires and on targets blocked by bricks or pits.
- **Spikes**: read the retract state, step only on retracted spikes, step off a spike that rises
  under the bot, and force a crossing after 3 s without progress.
- **Secret rooms**: locate undiscovered secret rooms from level data, bomb the shared wall, enter.
- **Boss preparation**: use a healing card before entering a boss room when low on health.
- **F8 menu**: English UI, run switch, goal, character, behaviour toggles, preset system,
  priority / exclusion lists and the item catalogue.

## Install

1. Copy this repository into
   `...\The Binding of Isaac Rebirth\mods\isaac_bot\`.
2. Enable mods in game, then run in the console:
   ```
   luamod isaac_bot
   ```
3. The bottom-left line should read `PP | ...   F8 Menu`.

## Controls

| Key | Action |
|---|---|
| F8 | open / close the settings menu |
| F9 | enable / disable the bot (Off = no control at all) |
| F7 | next preset |

## License

MIT. The original project's copyright notice is kept in [LICENSE](LICENSE); see
[CREDITS.md](CREDITS.md) for upstream projects.

## Disclaimer

Single-player only. Using mods disables achievements; that is a game limitation, not this project's.
