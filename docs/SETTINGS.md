# Settings

Everything below is stored in the mod save and edited from the **F8** menu.

## Goal

| Value | Run ends at |
|---|---|
| `auto` | as far as possible (stage 11 / Chest) |
| `mom` | Mom (stage 6) |
| `heart` | Mom's Heart / It Lives (stage 8) |
| `isaac` | Cathedral (stage 10, WOTL) |
| `satan` | Sheol (stage 10, WOTL) |
| `bluebaby` | Chest (stage 11) |
| `lamb` | Dark Room (stage 11) |

Polaroid / Negative are valued by the goal (Satan and Lamb need the Negative).

## Character

- `same` — keep the current character
- `cycle` — every character in turn (including tainted)
- `random` — any character
- a number — that player type

## Behaviour toggles

| Toggle | Effect |
|---|---|
| Auto-restart | start a new run after death |
| New run on win | restart after a real ending |
| Fast explore | treasure + shop, then boss (skip optional rooms) |
| Devil deals | enter the devil room and pay hearts when worth it |
| Active items | press a charged active in fights |
| Bombs | spend bombs on rocks, doors, bosses and clean-up |

## Presets

Built-in presets cannot be overwritten or deleted; "Save as" creates your own. The preset marked
with `*` is applied when the game (or `luamod`) loads. Presets store every setting above plus the
priority and exclusion lists.

## Priority / exclusion

- **Priority** — collectibles the bot always wants, in order; they outrank quality.
- **Exclusion** — collectibles it never takes.
The catalogue has search, quality filters and drag/drop ordering; click an item to toggle it
between priority and exclusion.

## Stats and learning

`stats` keeps runs/wins/deaths and the per-enemy-type `learn` table (hits taken, deaths). It is
saved with the mod and reset by deleting the mod save.
