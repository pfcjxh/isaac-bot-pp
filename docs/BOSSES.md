# Boss playbook

The combat loop is generic (find a firing spot, dodge, shoot). On top of it, `combat.lua` keeps a
small per-boss table with three flags:

| Flag | Effect |
|---|---|
| `adds` | Kill the boss' adds first (summoners) |
| `far` | Prefer a firing spot 50 units farther away |
| `burst` | Spend bombs and actives earlier (2 bombs instead of 3) |

## Current entries

| Boss | Flags |
|---|---|
| Mom, Mom's Heart, It Lives | adds |
| Mega Satan, Mother, The Beast, Dogma | adds, far, burst |
| Satan, Monstro II, Bloat, Krampus | far, burst |
| Hush, Delirium, The Lamb | far, burst |
| Isaac, ???, Gurdy, Gurdy Jr | far |
| Ultra Greed, Greed | adds, far |
| Chub, Larry Jr, Monstro, Fistula, Gemini | (default) |

Bosses not in the table use the generic loop. Names are resolved through `EntityType`, so a name
that does not exist in the installed build is skipped instead of breaking.

## Adding a boss

```lua
-- combat.lua, inside the BOSS_PLAN block
boss({"ENTITY_THE_BEAST"}, {adds = true, far = true, burst = true})
```

## Why not per-move state machines for every boss?

A real move database needs, per boss, the animation/state that telegraphs each attack and a
reaction per attack. That is a much larger data project than the heuristic loop. The playbook
above covers what the generic loop cannot guess (adds, spacing, burst timing); specific moves are
added one boss at a time when a run shows a failure. If you want a boss covered, open an issue with
the boss name and the log lines around the fight.
