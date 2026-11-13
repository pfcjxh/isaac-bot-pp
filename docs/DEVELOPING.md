# Developing

## Rules

- Never call the engine without a guard. Use `B.try(function() ... end)` for anything that can be
  missing across game versions.
- Resolve enums by name and tolerate `nil`:
  ```lua
  local t = B.try(function() return EntityType.ENTITY_KNIGHT end)
  if t then SET[t] = true end
  ```
- One module = one responsibility; modules attach to the shared table `B`.
- Every new behaviour should emit `B.event("name", {...})` so it can be verified from `log.txt`.
- Keep the F8 menu strings ASCII (the game's CJK font has no real glyphs in current builds).

## Add a pickup rule

`items.lua` → `I.value(e, p, ctx)`:

```lua
elseif v == PV.PICKUP_MY_THING then
    if someCondition then return nil end
    value = 3
```

Prices are validated before the branches; return `nil` to ignore.

## Add a card

1. Add the card to `I.CARD_KEEP` / `I.CARD_RANK` (priority order) in `items.lua`.
2. Add its kind in `brain.lua` `CARD_KIND` (`combat`, `heal`, `map`, `secret`, `treasure`,
   `spawn`).
3. The use conditions live in `cardGoal` (HP, boss, foe count, unvisited rooms).

## Add an enemy rule

`combat.lua` has small sets:

- `C.ARMORED` – shield in front (Knight)
- `C.REVIVE` – collapses and regenerates (Globin)
- `C.BOSS_PLAN` – per-boss flags

For a new rule, add the set near those, fill it by enum name, and use it in `pickTarget`,
`attackSpot` or `needFlank`.

## Add a room type

`floor.lua`: remove it from `SKIP`, give it an `INTEREST` score, and add a gate in
`chooseGoalRoom` if it costs something (health, coins, keys).

## Verify

- Syntax: parse the file with a Lua 5.3 parser (luaparse works).
- In game: `luamod isaac_bot`, then read `log.txt` for the new event.
- The status line shows the current `mode detail`; the F8 menu shows the settings.
