# 调试与开发指南

本文档详细说明如何在 Agent 环境中调试和开发 Isaac Bot PP。

---

## 📋 目录

1. [环境配置](#环境配置)
2. [日志系统](#日志系统)
3. [调试模式](#调试模式)
4. [常见问题排查](#常见问题排查)
5. [性能分析](#性能分析)
6. [添加新功能](#添加新功能)
7. [测试流程](#测试流程)

---

## 环境配置

### 1. 游戏目录结构

```
%USERPROFILE%\Documents\My Games\Binding of Isaac Repentance\
├── mods/
│   └── isaac-bot-pp/        # Mod 主目录
│       ├── main.lua
│       └── isaacbot/
│           ├── core.lua     # 核心配置
│           ├── brain.lua    # 决策引擎
│           ├── combat.lua   # 战斗系统
│           └── ...
├── log.txt                  # 游戏日志（重要！）
└── options.ini              # 游戏设置
```

### 2. 加载 Mod

游戏内控制台（按 `` 键）：
```lua
luamod isaac_bot
```

**成功标志**：
```
loaded v0.6.30
```

### 3. 配置文件位置

| 文件 | 路径 | 用途 |
|---|---|---|
| `core.lua` | `isaacbot/core.lua` | 全局配置、常量 |
| `log.txt` | `%USERPROFILE%\Documents\...\log.txt` | 运行时日志 |

---

## 日志系统

### 日志级别

| 级别 | 标记 | 用途 |
|---|---|---|
| **INFO** | `[BOT]` | 常规决策日志 |
| **DEBUG** | `[BRAIN]` | 目标规划详情 |
| **TRACE** | `[COMBAT]` | 战斗事件 |
| **ERROR** | `[ERROR]` | 错误信息 |

### 关键日志标记

#### 1. 目标选择
```
[BRAIN] target: room 71 (boss)
[BRAIN] path: [65 -> 67 -> 71], cost: 0 keys, 0 bombs
```

#### 2. 战斗决策
```
[COMBAT] boss: The Haunt (85)
[COMBAT] dodge: 320.5, 240.3 (safe zone found)
```

#### 3. 道具评估
```
[ITEMS] score: 15.2 (Sad Onion)
[ITEMS] pickup: yes (value above threshold)
```

#### 4. Idle 状态
```
[BOT] idle: why=boss, no_target_room
```

### 查看实时日志

**方法 1**：记事本打开
```
notepad "%USERPROFILE%\Documents\My Games\Binding of Isaac Repentance\log.txt"
```

**方法 2**：命令行监控（Windows PowerShell）
```powershell
Get-Content "$env:USERPROFILE\Documents\My Games\Binding of Isaac Repentance\log.txt" -Wait -Tail 50
```

---

## 调试模式

### 启用调试模式

编辑 `isaacbot/core.lua`：

```lua
-- 原始（生产模式）
B.DEBUG_MODE = false
B.SHOW_PANEL = false

-- 调试模式
B.DEBUG_MODE = true   -- 详细日志
B.SHOW_PANEL = true   -- 显示 HUD 面板
```

### HUD 面板信息

按 **Tab** 键查看：

```
┌─────────────────────────────┐
│ Isaac Bot PP v0.6.30        │
├─────────────────────────────┤
│ Mode: Combat                │
│ Target: Boss (71)           │
│ Health: 6/6 ♥               │
│ Keys: 3 🔑  Bombs: 5 💣     │
│ FPS: 60  Frame: 12543       │
│ Path: [65->67->71]          │
└─────────────────────────────┘
```

### 逐帧分析

修改 `core.lua`：
```lua
B.FRAME_STEP = true  -- 启用逐帧模式（空格键继续）
```

---

## 常见问题排查

### 问题 1：机器人 Idle（不动）

**症状**：机器人站着不动，日志显示 `idle`

**排查步骤**：
1. 查看 `log.txt` 最后 20 行：
   ```
   [BOT] idle: why=no_target
   ```

2. 检查 `why` 字段：
   | `why` 值 | 原因 | 解决方法 |
   |---|---|---|
   | `no_target` | 没有可用目标 | 检查房间探索状态 |
   | `boss` | Boss 已死，没有下一层 | 正常（等待进门）|
   | `path_blocked` | 路径被阻塞 | 检查是否有钥匙/炸弹 |

3. 检查房间状态：
   ```lua
   -- 查看当前房间号
   [FLOOR] current room: 65
   [FLOOR] explored: 12/15 rooms
   ```

**常见原因**：
- ❌ 所有门都被永久拉黑（**v0.6.30 已修复**）
- ❌ 压力板不可达（**v0.6.30 已修复为 15 秒后重试**）
- ✅ Boss 已死，等待进入下一层（正常）

---

### 问题 2：一直撞门

**症状**：机器人反复尝试进门，但进不去

**原因**：
1. 门被锁，但没有钥匙
2. 门被暂时拉黑（10 秒后会重试）
3. 房间不是"重要房间"，钥匙 ≤7 时不会开

**排查**：
```
[BRAIN] door: 71 locked, keys=3, important=no
[BRAIN] door blacklisted for 10s (retry at frame 15000)
```

**解决方法**：
- 如果是重要房间（宝箱/商店/Boss），会自动开门
- 如果不是重要房间且钥匙 ≤7，跳过（策略正常）
- 调整钥匙阈值：修改 `core.lua` 的 `B.KEY_RICH = 7`

---

### 问题 3：不踩压力板

**症状**：机器人看到压力板但不去踩

**原因**：
1. 压力板被判定为不可达（有障碍物）
2. 压力板被暂时拉黑（15 秒后重试）

**排查**：
```
[BRAIN] plate_blocked: x=320, y=240, reason=rocks
[BRAIN] plate retry at frame 16000 (15s from now)
```

**解决方法**：
- **v0.6.30** 会先炸掉挡路的石头/TNT，再去踩板
- 如果 15 秒后还不去，查看日志的 `plate_blocked` 原因

---

### 问题 4：战斗卡住（不躲不打）

**症状**：进入房间后不动，或被敌人围攻

**原因**：
1. Boss 没有专用策略
2. 躲避算法失效（安全区域计算错误）
3. 敌人 ID 未识别

**排查**：
```
[COMBAT] boss: unknown (type 999)
[COMBAT] dodge: failed, no safe zone
```

**解决方法**：
1. 添加 Boss 策略（见下方"添加新功能"）
2. 调整躲避参数（`combat.lua` 的 `SAFE_DISTANCE`）

---

## 性能分析

### 启用遥测

编辑 `telemetry.lua`：
```lua
TELEMETRY.ENABLED = true
TELEMETRY.LOG_INTERVAL = 60  -- 每 60 帧记录一次
```

### 查看性能数据

HUD 面板（按 Tab）：
```
FPS: 60
Frame Time: 16.7ms
Brain Time: 2.3ms   <- 决策耗时
Combat Time: 5.1ms  <- 战斗计算耗时
```

### 优化建议

| 耗时 | 阈值 | 优化方法 |
|---|---|---|
| **Brain Time** > 5ms | 慢 | 减少路径搜索深度 |
| **Combat Time** > 10ms | 慢 | 减少敌人扫描频率 |
| **Total** > 16.7ms | 掉帧 | 全面优化 |

---

## 添加新功能

### 示例 1：添加新 Boss 策略

**需求**：为 "Pin" Boss 添加专用策略

**步骤**：

1. 找到 `combat.lua` 的 `bossPlan` 函数：
   ```lua
   function bossPlan(boss_entity)
       local boss_type = boss_entity.Type
       
       -- 现有策略
       if boss_type == EntityType.ENTITY_HAUNT then
           return { priority = "minions", safe_dist = 250 }
       end
       
       -- 【新增】Pin Boss 策略
       if boss_type == EntityType.ENTITY_PIN then
           return {
               priority_target = "body",      -- 优先攻击本体
               safe_distance = 200,           -- 保持距离
               dodge_priority = "high",       -- 高优先级躲避
               attack_timing = "charge_end"   -- 冲锋后攻击
           }
       end
       
       return nil  -- 使用默认策略
   end
   ```

2. 测试：
   ```lua
   -- 游戏内控制台
   goto s.boss.1010  -- 传送到 Pin Boss 房间
   ```

3. 查看日志：
   ```
   [COMBAT] boss: Pin (62)
   [COMBAT] strategy: body, safe_dist=200
   ```

---

### 示例 2：调整道具评分

**需求**：提高"攻击力"道具的权重，降低"速度"道具的权重

**步骤**：

1. 编辑 `items.lua` 的 `scoreItem` 函数：
   ```lua
   function scoreItem(item)
       local score = 0
       
       -- 原始权重
       -- if item.damage > 0 then score = score + item.damage * 5 end
       -- if item.speed > 0 then score = score + item.speed * 3 end
       
       -- 【调整】提高攻击权重，降低速度权重
       if item.damage > 0 then 
           score = score + item.damage * 10  -- 5 -> 10
       end
       if item.speed > 0 then 
           score = score + item.speed * 1    -- 3 -> 1
       end
       if item.speed < 0 then 
           score = score - 50  -- 速度惩罚
       end
       
       return score
   end
   ```

2. 测试：
   ```lua
   giveitem c15  -- Sad Onion（射速道具）
   -- 查看日志
   [ITEMS] score: 3.5 (was 10.5 before adjustment)
   [ITEMS] pickup: no (below threshold)
   ```

---

### 示例 3：添加新房间类型优先级

**需求**：将"图书馆"设为高优先级房间

**步骤**：

1. 编辑 `floor.lua` 的 `importantRoom` 函数：
   ```lua
   function importantRoom(room_type)
       -- 现有重要房间
       if room_type == RoomType.ROOM_TREASURE then return true end
       if room_type == RoomType.ROOM_SHOP then return true end
       if room_type == RoomType.ROOM_BOSS then return true end
       
       -- 【新增】图书馆
       if room_type == RoomType.ROOM_LIBRARY then return true end
       
       return false
   end
   ```

2. 测试：
   ```
   [FLOOR] library (room 73) marked as important
   [BRAIN] target: room 73 (library), priority=high
   ```

---

## 测试流程

### 1. 单元测试（手动）

**测试特定场景**：
```lua
-- 控制台命令
goto s.boss.1010    -- Boss 房间
goto s.treasure     -- 宝箱房间
goto s.shop         -- 商店
giveitem c15        -- 给道具
spawn 10            -- 生成敌人
debug 3             -- 显示网格
```

### 2. 集成测试（完整一局）

**步骤**：
1. 启动游戏
2. 加载 Mod：`luamod isaac_bot`
3. 观察完整一局
4. 记录问题：
   - 卡住的位置（房间号）
   - 日志快照（最后 50 行）
   - 截图

### 3. 回归测试（版本验证）

**检查清单**：
- [ ] 能否正常探索楼层
- [ ] 能否打败常见 Boss（Mom, It Lives）
- [ ] 钥匙策略是否正常（≤7 时不乱开门）
- [ ] 压力板能否正常踩（15 秒内重试）
- [ ] 死亡后是否自动重开（如果开启）

---

## 实战案例：修复"按钮房"死锁

### 问题描述（v0.6.10-v0.6.29）
- 先试门（失败）→ 门**永久拉黑**
- 再试按钮（失败）→ 按钮**永久拉黑**
- → 机器人 Idle

### 修复过程（v0.6.30）

#### 1. 定位问题
```
[BOT] idle: why=no_target
[BRAIN] door 71 blacklisted (permanent)
[BRAIN] plate (320,240) blacklisted (permanent)
```

#### 2. 分析原因
- 拉黑时长设置为 `1e9`（永久）
- 没有重试机制

#### 3. 实施修复
```lua
-- core.lua
B.DOOR_RETRY_DELAY = 10 * 60  -- 10 秒（60 FPS）
B.PLATE_RETRY_DELAY = 15 * 60 -- 15 秒

-- brain.lua
function blacklistDoor(door_id)
    local expire = game:GetFrameCount() + B.DOOR_RETRY_DELAY
    blacklist[door_id] = expire  -- 不再是永久
end
```

#### 4. 验证修复
```
[BRAIN] door 71 blacklisted until frame 15600 (10s)
[BRAIN] plate retry at frame 16500 (15s)
-- 10 秒后
[BRAIN] door 71 retry, status=open
[BOT] target: room 71
```

---

## 附录：常用命令

### 游戏内控制台

| 命令 | 功能 |
|---|---|
| `luamod isaac_bot` | 加载 Mod |
| `goto s.boss.1010` | 传送到 Boss 房间 |
| `goto s.treasure` | 传送到宝箱房间 |
| `goto d.10` | 传送到 Depths 10 层 |
| `giveitem c15` | 给道具（15 = Sad Onion）|
| `spawn 10` | 生成敌人（10 = Fly）|
| `debug 3` | 显示网格（0 = 关闭）|
| `set bot_auto_restart 1` | 开启自动重开 |

### 常用道具 ID
- `c15`: Sad Onion（射速）
- `c1`: The Sad Onion
- `c4`: Cricket's Head（攻击力）
- `c169`: Polyphemus（超高攻击）

---

## 联系与支持

遇到问题？

1. **查看日志**：`log.txt` 最后 50 行
2. **提交 Issue**：[GitHub Issues](../../issues)
3. **提供信息**：
   - 版本号（`loaded v0.6.x`）
   - 日志片段
   - 复现步骤
   - 截图（如果可能）

---

**祝调试顺利！🎮**
