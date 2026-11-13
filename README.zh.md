# Isaac Bot PP

《以撒的结合：忏悔》的单机 AI 自动驾驶 mod（Lua），在原版 `netlesha/isaac-bot` 的基础上做了大量增强。

> Single-player autopilot mod for *The Binding of Isaac: Repentance*. A heavily extended fork of
> [netlesha/isaac-bot](https://github.com/netlesha/isaac-bot) (MIT).

## 功能

- **寻路与探索**：整层房间图 + Dijkstra 网格寻路；宝箱/商店/隐藏房/恶魔房/天使房/挑战房/游戏厅按兴趣分排序。
- **战斗**：按武器类型（眼泪/蓄力/近战/制导）自动找射击位；弹幕/激光/炸弹/踩踏的短时预演闪避。
- **敌人特性**：
  - Knight 背击（正面无敌盾，只打后脑勺，带引擎方向校准 + 炸弹兜底）；
  - Host 等"缩壳/起身"敌人：停止开火、大范围换角走动，等它露头；
  - Globin 泥巴补刀（不补会复活）；
  - Boss 战术：召唤型先清小怪，近身惩罚型拉远站位。
- **拾取与资源**：
  - 只捡**有用**的卡牌（死神/战车/女祭司/皇后/魔术师/力量/太阳/教皇/恋人/世界/月亮/星星/审判/命运之轮），战斗卡优先在 Boss 房使用；
  - 药丸**不捡不用**（效果未知，保守）；
  - 卡牌可换更好的（丢弃→拾取，优先级排序）；
  - 商店按品质/价格/血量买血、电池、钥匙、炸弹；
  - 金宝箱必开；钥匙箱在钥匙 ≥3 时才开；红宝箱按血量开。
- **清房巡检**：灭掉火堆、打掉屎、炸彩色石/超级彩色石/金石头；打不灭的蓝/白火自动放弃。
- **地刺**：识别升降状态，只在缩下去时迈步；站在刺上会横移离开；3 秒没进展则强制趟过去防卡关。
- **隐藏房**：按房间邻接规则找到未发现的隐藏房，炸开共享墙进入。
- **Boss 前准备**：进 Boss 房前血少会用回血卡。
- **F8 菜单**：英文界面，运行开关/目标/角色/6 个行为开关/预设系统/优先级与排除列表/道具目录。

## 安装

1. 把本仓库内容放到：
   ```
   ...\The Binding of Isaac Rebirth\mods\isaac_bot\
   ```
2. 游戏里启用 mods（主菜单 → Mods），进游戏后控制台执行：
   ```
   luamod isaac_bot
   ```
3. 看到左下角 `PP | ...   F8 Menu` 即加载成功。

## 按键

| 键 | 作用 |
|---|---|
| F8 | 打开/关闭设置菜单 |
| F9 | 开/关机器人（Off 时完全不操作角色） |
| F7 | 切换预设 |

## 目录结构

```
main.lua            入口：回调、输入接管、运行/重开
metadata.xml        mod 元信息
isaacbot/
  core.lua          设置、存档、公共工具
  grid.lua          房间网格、Dijkstra、地刺/岩石/火堆/屎
  danger.lua        威胁模拟与闪避
  combat.lua        目标选择、射击位、武器档位、背击、Boss 战术
  items.lua         拾取价值、商店、卡牌优先级
  floor.lua         楼层房间图与路由
  brain.lua         总决策循环（战斗/拾取/清房/隐藏房/门/出口）
  panel.lua         F8 菜单
  presets.lua       预设
  bridge.lua        调试桥（可选）
  telemetry.lua     事件日志
  replay.lua        回放记录（可选）
resources/gfx/isaacbot/   菜单用的小方块精灵
```

## 许可与致谢

MIT。原项目 `netlesha/isaac-bot`（MIT）保留其版权声明，见 `LICENSE` 与 `CREDITS.md`。
本仓库的修改部分版权归 PP。

## 免责声明

仅用于**单机**模式。联机（Repentance Online）下使用 mod 可能影响他人体验，请勿在联机房间使用。
使用本 mod 会禁用成就，这是游戏本身的限制，与本项目无关。