# Isaac Bot PP

《以撒的结合：忏悔》的单机 AI 自动驾驶 mod（Lua），在原版 [netlesha/isaac-bot](https://github.com/netlesha/isaac-bot) (MIT) 基础上大量增强。

English: [README.md](README.md)

---

## 🎮 它能做什么

机器人**完全自主**打完一局：
- ✅ 探索楼层并规划路线
- ✅ 清理房间、躲避弹幕
- ✅ 智能判断道具价值（该捡什么、该跳过什么）
- ✅ 使用钥匙/炸弹/金币的策略决策
- ✅ 打 Boss、挑战房间、献祭房
- ✅ 处理压力板、特殊机关
- ✅ 自动重试（死亡后重开）

---

## 🏆 成就记录

使用 **v0.6.11** 版本成功通关妈心（Mom's Heart），获得成就：

| 成就 | 描述 | 时间 | 截图 |
|---|---|---|---|
| **Solar System** | Unlocked Challenge #6 | 2026-01-13 | [查看](achievements/solar_system.png) |
| **A Noose** | Unlocked a new item | 2026-01-13 | [查看](achievements/a_noose.png) |

> **v0.6.11 是第一个完整通关妈心的稳定版本**，已打 tag 保存。

更多成就记录详见 [achievements/](achievements/) 目录。

---

## 📦 安装

### 前置要求
- The Binding of Isaac: Repentance（Steam 版本）
- Steam Workshop 订阅（或手动安装）

### 方法 1：Steam Workshop（推荐）
1. 在 Steam 创意工坊搜索 "Isaac Bot PP"
2. 点击订阅
3. 启动游戏，在 Mod 菜单启用

### 方法 2：手动安装
1. 下载最新版本 Release
2. 解压到游戏 Mod 目录：
   ```
   %USERPROFILE%\Documents\My Games\Binding of Isaac Repentance\mods\isaac-bot-pp
   ```
3. 启动游戏，在 Mod 菜单启用

---

## 🎯 使用

### 启动机器人
游戏内按 **`** (数字1左边的键) 打开控制台，输入：

```lua
luamod isaac_bot
```

看到日志 `loaded v0.6.x` 即表示成功加载。

### 控制命令

| 命令 | 功能 |
|---|---|
| `set bot_auto_restart 1` | 死亡后自动重开（默认关闭）|
| `set bot_auto_restart 0` | 关闭自动重开 |
| `set bot_speed 2` | 调整速度（0.5-4.0）|

### 查看状态
游戏内按 **Tab** 键查看当前状态：
- 当前目标（房间、道具、敌人）
- 决策模式（探索/战斗/拾取）
- 资源状态（钥匙/炸弹/金币）

---

## 🔧 底层实现

### 架构概览

```
isaac-bot-pp/
├── main.lua          # 入口，注册回调
├── isaacbot/
│   ├── core.lua      # 核心配置、常量、全局状态
│   ├── brain.lua     # 决策引擎（目标规划、路径寻找）
│   ├── combat.lua    # 战斗逻辑（躲避、射击、Boss 策略）
│   ├── floor.lua     # 楼层管理（房间图、路径规划）
│   ├── items.lua     # 道具评估（价值判断、拾取决策）
│   ├── grid.lua      # 网格系统（障碍物、可行走区域）
│   ├── danger.lua    # 危险评估（弹幕、敌人威胁）
│   ├── bridge.lua    # 游戏接口（读取/控制游戏状态）
│   ├── panel.lua     # HUD 面板（调试信息显示）
│   ├── telemetry.lua # 遥测数据（性能分析）
│   └── presets.lua   # 角色预设（不同角色的策略）
```

### 关键模块

#### 1. **决策引擎** (`brain.lua`)
- **目标选择**：根据优先级（Boss > 重要房间 > 道具 > 探索）选择下一个目标
- **路径规划**：A* 算法找到最优路径，考虑钥匙/炸弹成本
- **策略决策**：
  - 钥匙策略：`KEY_RICH = 7`（>7 把钥匙时开所有锁，≤7 时只开重要房间）
  - 炸弹策略：保留炸弹用于秘密房间和特殊情况
  - 献祭房策略：满血时尝试献祭

#### 2. **战斗系统** (`combat.lua`)
- **躲避算法**：预测弹幕轨迹，找到安全区域
- **射击策略**：优先攻击威胁最大的敌人
- **Boss 专用策略**：
  - **The Haunt**：优先击杀小鬼，避免被包围
  - 更多 Boss 策略持续添加中...

#### 3. **道具评估** (`items.lua`)
- **道具价值**：基于增益（攻击/射速/血量）计算分数
- **诅咒道具**：权衡收益与风险
- **金色/锁箱**：任何钥匙都可以开（不需要金钥匙）

#### 4. **楼层管理** (`floor.lua`)
- **房间图构建**：自动探索并记录房间位置
- **路径优化**：优先探索高价值房间（宝箱房、商店、秘密房间）
- **重要房间判定**：`importantRoom` 函数识别优先级房间

---

## 🐛 调试与开发

### 在 Agent 中调试

#### 1. 查看当前版本和状态
```lua
-- 游戏内控制台
luamod isaac_bot
-- 看日志：loaded v0.6.x
```

#### 2. 启用调试日志
修改 `isaacbot/core.lua`：
```lua
B.DEBUG_MODE = true  -- 开启详细日志
B.SHOW_PANEL = true  -- 显示调试面板
```

#### 3. 查看日志文件
日志位置：
```
%USERPROFILE%\Documents\My Games\Binding of Isaac Repentance\log.txt
```

关键日志标记：
- `[BOT]`：机器人决策日志
- `[COMBAT]`：战斗事件
- `[FLOOR]`：楼层探索
- `[BRAIN]`：目标规划

#### 4. 实时修改策略
```lua
-- 修改钥匙阈值（isaacbot/core.lua）
B.KEY_RICH = 5  -- 从 7 改成 5，更激进开锁

-- 修改炸弹策略（isaacbot/brain.lua）
local bomb_threshold = 3  -- 保留至少 3 个炸弹
```

#### 5. 测试特定场景
```lua
-- 游戏内控制台
goto s.boss.1010  -- 传送到 Boss 房间
goto s.treasure  -- 传送到宝箱房间
giveitem c15     -- 给予特定道具测试
```

#### 6. 性能分析
```lua
-- 查看遥测数据（isaacbot/telemetry.lua）
-- 数据记录在 panel.lua 的 HUD 中显示
```

### 常见问题排查

| 问题 | 可能原因 | 排查方法 |
|---|---|---|
| **机器人 Idle** | 目标丢失或路径被阻塞 | 查看 `log.txt` 的 `idle` 事件和 `why` 字段 |
| **一直撞门** | 门暂时被拉黑（10秒后重试）| 检查是否有钥匙、是否是重要房间 |
| **不踩压力板** | 板子被判定不可达或暂时拉黑（15秒后重试）| 查看 `plate_blocked` 日志 |
| **不捡道具** | 道具价值低于阈值 | 修改 `items.lua` 的评分函数 |
| **战斗卡住** | Boss 策略未覆盖 | 在 `combat.lua` 添加 Boss 专用逻辑 |

### 添加新功能

#### 示例：添加新 Boss 策略
1. 在 `isaacbot/combat.lua` 找到 `bossPlan` 函数
2. 添加新 Boss ID 判断：
   ```lua
   if boss_type == EntityType.ENTITY_PIN then
       -- Pin boss 的专用策略
       return {
           priority_target = "body",  -- 优先攻击本体
           safe_distance = 200,       -- 保持距离
           dodge_priority = "high"    -- 高优先级躲避
       }
   end
   ```

#### 示例：调整道具评分
1. 修改 `isaacbot/items.lua` 的 `scoreItem` 函数
2. 增加/减少特定属性的权重：
   ```lua
   local score = 0
   if item.damage > 0 then score = score + item.damage * 10 end  -- 攻击权重 x10
   if item.speed < 0 then score = score - 50 end  -- 速度惩罚 -50
   ```

---

## 📊 版本历史

### v0.6.30-dev (开发中)
- 🔧 **门拉黑改为临时**：打不开的门 10 秒后重试（之前是永久）
- 🔧 **压力板拉黑改为临时**：够不到的板 15 秒后重试
- ✅ 修复"按钮房"死锁问题

### v0.6.11 (2026-01-13) 🏆
**首个通关妈心的稳定版本**
- ✅ 钥匙策略优化（`KEY_RICH = 7`）
- ✅ 火焰机制改进（跳过紫色火焰）
- ✅ 持续房间超时退出（20秒无敌人可见时离开）

### v0.6.10-v0.6.29
详细变更记录见 [CHANGELOG.md](CHANGELOG.md)

---

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

### 开发指南
1. Fork 本仓库
2. 创建功能分支：`git checkout -b feature/your-feature`
3. 提交修改：`git commit -m 'Add some feature'`
4. 推送分支：`git push origin feature/your-feature`
5. 提交 Pull Request

详见 [CONTRIBUTING.md](CONTRIBUTING.md)

---

## 📝 许可证

MIT License - 详见 [LICENSE](LICENSE)

基于 [netlesha/isaac-bot](https://github.com/netlesha/isaac-bot) (MIT)

---

## 🙏 致谢

- 原作者 [netlesha](https://github.com/netlesha) 的初始框架
- The Binding of Isaac 社区的 Mod API 文档
- 所有测试者和贡献者

---

## 📮 联系

- GitHub Issues：[提交问题](../../issues)
- Steam Workshop：（待添加链接）

---

**⭐ 如果这个项目帮到了你，请给个 Star！**
