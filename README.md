# Isaac Bot PP

An autonomous AI bot mod (Lua) for *The Binding of Isaac: Repentance*, heavily enhanced from the original [netlesha/isaac-bot](https://github.com/netlesha/isaac-bot) (MIT).

中文文档：[README.zh.md](README.zh.md)

---

## 🎮 What It Does

The bot **fully autonomously** completes a run:
- ✅ Explores floors and plans routes
- ✅ Clears rooms and dodges projectiles
- ✅ Intelligently evaluates items (what to pick, what to skip)
- ✅ Strategic decisions for keys/bombs/coins
- ✅ Fights bosses, challenge rooms, sacrifice rooms
- ✅ Handles pressure plates and special mechanics
- ✅ Auto-retry (restart after death)

---

## 🏆 Achievement Records

Successfully defeated Mom's Heart using **v0.6.11**, unlocking:

| Achievement | Description | Date | Screenshot |
|---|---|---|---|
| **Solar System** | Unlocked Challenge #6 | 2026-01-13 | [View](achievements/solar_system.png) |
| **A Noose** | Unlocked a new item | 2026-01-13 | [View](achievements/a_noose.png) |

> **v0.6.11 is the first stable version to fully clear Mom's Heart**, tagged for preservation.

More achievement records in [achievements/](achievements/) directory.

---

## 📦 Installation

### Prerequisites
- The Binding of Isaac: Repentance (Steam version)
- Steam Workshop subscription (or manual install)

### Method 1: Steam Workshop (Recommended)
1. Search "Isaac Bot PP" in Steam Workshop
2. Click Subscribe
3. Launch game, enable in Mod menu

### Method 2: Manual Installation
1. Download latest Release
2. Extract to game Mod directory:
   ```
   %USERPROFILE%\Documents\My Games\Binding of Isaac Repentance\mods\isaac-bot-pp
   ```
3. Launch game, enable in Mod menu

---

## 🎯 Usage

### Starting the Bot
In-game, press **`** (key left of 1) to open console, type:

```lua
luamod isaac_bot
```

Look for log `loaded v0.6.x` to confirm successful load.

### Control Commands

| Command | Function |
|---|---|
| `set bot_auto_restart 1` | Auto-restart after death (default off)|
| `set bot_auto_restart 0` | Disable auto-restart |
| `set bot_speed 2` | Adjust speed (0.5-4.0)|

### View Status
Press **Tab** in-game to view current status:
- Current target (room, item, enemy)
- Decision mode (explore/combat/pickup)
- Resource status (keys/bombs/coins)

---

## 🔧 Implementation Details

### Architecture Overview

```
isaac-bot-pp/
├── main.lua          # Entry point, register callbacks
├── isaacbot/
│   ├── core.lua      # Core config, constants, global state
│   ├── brain.lua     # Decision engine (goal planning, pathfinding)
│   ├── combat.lua    # Combat logic (dodging, shooting, boss strategies)
│   ├── floor.lua     # Floor management (room map, path planning)
│   ├── items.lua     # Item evaluation (value scoring, pickup decisions)
│   ├── grid.lua      # Grid system (obstacles, walkable areas)
│   ├── danger.lua    # Danger assessment (projectiles, enemy threats)
│   ├── bridge.lua    # Game interface (read/control game state)
│   ├── panel.lua     # HUD panel (debug info display)
│   ├── telemetry.lua # Telemetry data (performance analysis)
│   └── presets.lua   # Character presets (per-character strategies)
```

### Key Modules

#### 1. **Decision Engine** (`brain.lua`)
- **Goal Selection**: Prioritizes targets (Boss > Important Rooms > Items > Explore)
- **Pathfinding**: A* algorithm for optimal paths, considering key/bomb costs
- **Strategic Decisions**:
  - Key strategy: `KEY_RICH = 7` (open all locks when >7 keys, only important rooms when ≤7)
  - Bomb strategy: Reserve bombs for secret rooms and special situations
  - Sacrifice room strategy: Attempt sacrifices at full health

#### 2. **Combat System** (`combat.lua`)
- **Dodge Algorithm**: Predicts projectile trajectories, finds safe zones
- **Shooting Strategy**: Prioritizes highest-threat enemies
- **Boss-Specific Strategies**:
  - **The Haunt**: Prioritize killing minions, avoid being surrounded
  - More boss strategies being added...

#### 3. **Item Evaluation** (`items.lua`)
- **Item Value**: Calculates score based on bonuses (damage/tear rate/health)
- **Cursed Items**: Weighs benefits vs risks
- **Golden/Locked Chests**: Can open with any key (golden key not required)

#### 4. **Floor Management** (`floor.lua`)
- **Room Map Construction**: Auto-explores and records room positions
- **Path Optimization**: Prioritizes high-value rooms (treasure, shop, secret rooms)
- **Important Room Detection**: `importantRoom` function identifies priority rooms

---

## 🐛 Debugging & Development

### Debugging in Agent

#### 1. Check Current Version and Status
```lua
-- In-game console
luamod isaac_bot
-- Look for: loaded v0.6.x
```

#### 2. Enable Debug Logging
Edit `isaacbot/core.lua`:
```lua
B.DEBUG_MODE = true  -- Enable detailed logging
B.SHOW_PANEL = true  -- Show debug panel
```

#### 3. View Log File
Log location:
```
%USERPROFILE%\Documents\My Games\Binding of Isaac Repentance\log.txt
```

Key log markers:
- `[BOT]`: Bot decision logs
- `[COMBAT]`: Combat events
- `[FLOOR]`: Floor exploration
- `[BRAIN]`: Goal planning

#### 4. Real-time Strategy Tweaks
```lua
-- Modify key threshold (isaacbot/core.lua)
B.KEY_RICH = 5  -- Change from 7 to 5, more aggressive key usage

-- Modify bomb strategy (isaacbot/brain.lua)
local bomb_threshold = 3  -- Reserve at least 3 bombs
```

#### 5. Test Specific Scenarios
```lua
-- In-game console
goto s.boss.1010  -- Teleport to Boss room
goto s.treasure  -- Teleport to Treasure room
giveitem c15     -- Give specific item for testing
```

#### 6. Performance Analysis
```lua
-- View telemetry data (isaacbot/telemetry.lua)
-- Data displayed in panel.lua HUD
```

### Common Issue Troubleshooting

| Issue | Possible Cause | Troubleshooting |
|---|---|---|
| **Bot Idle** | Target lost or path blocked | Check `log.txt` for `idle` event and `why` field |
| **Keeps hitting door** | Door temporarily blacklisted (retries after 10s)| Check if have keys, if important room |
| **Won't step on plate** | Plate deemed unreachable or temp blacklisted (retries after 15s)| Check `plate_blocked` log |
| **Won't pick item** | Item value below threshold | Modify scoring function in `items.lua` |
| **Combat stuck** | Boss strategy not covered | Add boss-specific logic in `combat.lua` |

### Adding New Features

#### Example: Add New Boss Strategy
1. Find `bossPlan` function in `isaacbot/combat.lua`
2. Add new Boss ID check:
   ```lua
   if boss_type == EntityType.ENTITY_PIN then
       -- Pin boss specific strategy
       return {
           priority_target = "body",  -- Prioritize attacking body
           safe_distance = 200,       -- Keep distance
           dodge_priority = "high"    -- High priority dodging
       }
   end
   ```

#### Example: Adjust Item Scoring
1. Edit `scoreItem` function in `isaacbot/items.lua`
2. Increase/decrease specific attribute weights:
   ```lua
   local score = 0
   if item.damage > 0 then score = score + item.damage * 10 end  -- Damage weight x10
   if item.speed < 0 then score = score - 50 end  -- Speed penalty -50
   ```

---

## 📊 Version History

### v0.6.30-dev (In Development)
- 🔧 **Door blacklist now temporary**: Locked doors retry after 10s (was permanent)
- 🔧 **Pressure plate blacklist now temporary**: Unreachable plates retry after 15s
- ✅ Fixed "button room" deadlock issue

### v0.6.11 (2026-01-13) 🏆
**First stable version to clear Mom's Heart**
- ✅ Key strategy optimized (`KEY_RICH = 7`)
- ✅ Fire mechanics improved (skip purple fires)
- ✅ Hold room timeout (leave after 20s with no visible enemies)

### v0.6.10-v0.6.29
Detailed changelog in [CHANGELOG.md](CHANGELOG.md)

---

## 🤝 Contributing

Issues and Pull Requests welcome!

### Development Guide
1. Fork this repo
2. Create feature branch: `git checkout -b feature/your-feature`
3. Commit changes: `git commit -m 'Add some feature'`
4. Push branch: `git push origin feature/your-feature`
5. Submit Pull Request

See [CONTRIBUTING.md](CONTRIBUTING.md) for details

---

## 📝 License

MIT License - see [LICENSE](LICENSE)

Based on [netlesha/isaac-bot](https://github.com/netlesha/isaac-bot) (MIT)

---

## 🙏 Credits

- Original author [netlesha](https://github.com/netlesha) for initial framework
- The Binding of Isaac community for Mod API documentation
- All testers and contributors

---

## 📮 Contact

- GitHub Issues: [Submit Issue](../../issues)
- Steam Workshop: (link TBD)

---

**⭐ If this project helped you, give it a Star!**
