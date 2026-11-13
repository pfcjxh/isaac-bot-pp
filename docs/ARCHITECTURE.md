# Architecture

## Update pipeline

```
MC_POST_UPDATE (main.lua)
  └─ B.brain.update()
       ├─ clear input, tick++, skip if paused / dead / room entering
       ├─ danger.collect(entities)          -- threat lists for this frame
       ├─ grid.build(player, entities)      -- every 15 frames, or 4 on spike rooms
       ├─ grid.flood(playerCell, extra)     -- Dijkstra costs from the player
       ├─ choose a goal (see priority below)
       ├─ danger.choose(dx, dy, weight)     -- simulate 8 directions over 16 updates
       └─ B.move / B.shoot / B.tap          -- desired input for MC_INPUT_ACTION
```

Goal priority inside a room (first non-nil wins):

1. `runBomb` – finish a bomb plan (rock / fire / poop / retreat)
2. `plateGoal` – step on an unpressed pressure plate
3. `cardSwapGoal` – drop a worse card for a better one on the floor
4. `lootGoal` – walk to the best pickup by value / distance
5. `sweepGoal` – after the room is clear: put out fires, break poop, bomb loot rocks
6. `secretGoal` – bomb a shared wall of an undiscovered secret room
7. `routeFloor` – door toward the next room, boss room, devil deal or floor exit

Before that, `cardGoal` may use a held card, and a spike escape overrides everything when the
player is standing on a raised spike.

## Modules

| File | Lines | Responsibility |
|---|---|---|
| `main.lua` | ~243 | Callbacks, input ownership, restart/bench, save loading |
| `isaacbot/core.lua` | ~313 | Settings table, persistence, helpers (`B.try`, `B.move`, events) |
| `isaacbot/grid.lua` | ~447 | Grid rebuild, Dijkstra, rocks/fires/spikes/chests, steering |
| `isaacbot/danger.lua` | ~327 | Threat model and dodge simulation |
| `isaacbot/combat.lua` | ~693 | Targets, firing spots, weapon profiles, knight flank, boss playbook, learning |
| `isaacbot/items.lua` | ~366 | Pickup values, shop prices, card priority, active swap |
| `isaacbot/floor.lua` | ~412 | Room graph, interest scores, doors, exits |
| `isaacbot/brain.lua` | ~1319 | Decision loop and all goals |
| `isaacbot/panel.lua` | ~1346 | F8 menu, item catalogue, presets UI |
| `isaacbot/presets.lua` | ~235 | Built-in presets and preset operations |
| `isaacbot/telemetry.lua` | ~98 | `EV` log lines |
| `isaacbot/replay.lua` | ~122 | Optional input recording |
| `isaacbot/bridge.lua` | ~142 | Optional debug bridge commands |

## State

- `B.S` — settings persisted with `mod:SaveData` (goal, character, toggles, lists, presets,
  stats, learned enemy data).
- `B.st` — runtime state: tick, mode/detail (shown in the status line), blacklists, room age,
  last hit, restart timer.
- `B.input` / `B.taps` — desired inputs for this frame; `MC_INPUT_ACTION` answers with them.
- `B.grid` — per-room grid: cost map, rocks, fires, poop, spikes, chest cells, flood results.
- `B.floor` — room list with map cells, adjacency, interest.
- `B.combat` — current target, weapon profile, charge learner, flank state, boss plan, learning.

## Input model

The bot never touches the keyboard directly. It writes `B.input[ButtonAction]` and the game's
`MC_INPUT_ACTION` callback answers for player movement, shooting, bomb, active item, card and
drop. `OWNED_MAX` in `main.lua` defines the highest action the bot may own. While the F8 menu
is open, `panel.blocks` swallows the game's own keys.

## Callbacks used

- `MC_INPUT_ACTION` — input ownership
- `MC_POST_UPDATE` — main loop
- `MC_POST_RENDER` — panel drawing, restart timer
- `MC_POST_NEW_ROOM` / `MC_POST_NEW_LEVEL` / `MC_POST_GAME_STARTED` / `MC_POST_GAME_END`
- `MC_ENTITY_TAKE_DMG` — telemetry, spike state correction, enemy learning

## Persistence

Settings, presets, stats and learned enemy data live in the mod save (`mod:SaveData`).
Deleting that save resets all of it.
