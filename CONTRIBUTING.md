# Contributing

Thanks for helping.

## Issues

- Bugs: include the mod version (`loaded v...` in `log.txt`), the game version, and the last
  ~30 `[IsaacBot] EV` lines around the problem.
- Balance/behaviour: describe the room, the enemy, and what the bot did instead.

## Pull requests

- Keep the module boundaries (see `docs/ARCHITECTURE.md`).
- Guard every engine call with `B.try`; resolve enums by name and tolerate `nil`.
- Add a `B.event` for any new behaviour.
- Keep menu strings ASCII.
- Test: parse all `*.lua` with a Lua 5.3 parser, then run a game and check the log.
- License: contributions are accepted under MIT; keep the existing copyright notices.

## Commit messages

`area: short description` (e.g. `combat: keep distance from Hush`).
