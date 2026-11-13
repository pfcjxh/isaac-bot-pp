# Event reference

Every decision is logged as one line to `log.txt`:

```
[IsaacBot] EV {"ev":"<name>","t":<tick>,...}
```

All events carry `ev` and `t` (update tick). The table below lists the remaining fields.

## Run lifecycle

| Event | Fields | Meaning |
|---|---|---|
| `run_start` | char, stage, seed, goal, continued, bench | A run started |
| `floor` | name, stage, eff, curses, red, soul, coins, bombs, keys | New floor |
| `room` | idx, type, shape | Entered a room |
| `hit` | amt, flags, mode, st, sv, sp, px, py, red, soul | Player took damage (st/sv = source type/variant) |
| `death` | — | Player died |
| `win` | how, stage, eff, goal, minutes | Run finished with an ending |
| `restart` | char / seed, bench | Bot restarted the run |
| `game_end` | over, stage, room, pending, won, restart, mode | Game-end callback fired |
| `run_end` | stage, goal | Run ended without an ending and without death |
| `status` / `hb` | char, stage, mode, detail, red, soul, coins, bombs, keys | Periodic status (30 s / 60 s) |

## Combat

| Event | Fields | Meaning |
|---|---|---|
| `active` | id, name | Used the active item |
| `charge` | key, ok, hold, next | Charge-weapon hold time learning |
| `beam` | wait | Brimstone beam timing sample |
| `brim_learn` | who, windup | Learned a laser wind-up |
| `bomb_target` | type, variant, stuck | Bombed a boss / shielded enemy |
| `flank_cal` | rear, front, ok, sign | Knight shield direction calibration |
| `learn_hit` | who, hits | Hit taken from an enemy type |
| `learn_death` | who, deaths | Death attributed to an enemy type |

## Loot and rooms

| Event | Fields | Meaning |
|---|---|---|
| `item` | id, name, q, stage | Gained a collectible |
| `card_use` | id, why, tries | Used a card |
| `card_swap` | from, to | Dropped a card for a better one |
| `boss_prep` | card, hp | Healed with a card before a boss room |
| `bomb_rock` / `bomb_door` / `door_blocked` / `bedroom_skip` | cell / room / slot | Bomb usage |
| `fire_out` / `poop_out` / `fire_blocked` / `fire_stuck` | cell / hp | Room clean-up |
| `sweep_rock` | cell, type | Bombed a loot rock |
| `sweep_poop_bomb` | cell | Bombed stubborn poop |
| `secret_found` / `secret_bomb` / `secret_fail` | room, wall | Secret room handling |

## Movement

| Event | Fields | Meaning |
|---|---|---|
| `stuck` | goal, level, x, y | Goal not improving |
| `unreachable` | room, type, from | No route to the goal room |
| `idle` | room, goal, why, here | Nothing to do for a while |
| `spike_state` | state, timeout | First retracting spike sample |
| `spike_hit` | cell | Spikes rose under the player |
| `spike_force` | tick | No progress on spikes: forced crossing |

## Meta

| Event | Meaning |
|---|---|
| `preset` | A preset was selected |
| `replay` | Replay buffer written |
| `abandon` | Run abandoned |
