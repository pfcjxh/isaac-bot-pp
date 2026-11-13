# Isaac Bot PP

《以撒的结合：忏悔》的单机 AI 自动驾驶 mod（Lua）。在原版
[netlesha/isaac-bot](https://github.com/netlesha/isaac-bot)（MIT）基础上做了大量增强。

English: [README.md](README.md)

## 它做什么

机器人自己打完一局：探索楼层、清房间、躲弹幕、判断该捡什么、开能开的房间、打 Boss，并把
每次决策写进日志，方便事后按日志调行为。

**不是神经网络**，全部是启发式：房间图 + 网格 Dijkstra + 短时预演闪避 + 按武器类型的射击位
+ 少量跨局累积的"敌人威胁"经验（见下文"学习"）。

## 能力一览

| 模块 | 行为 |
|---|---|
| 寻路 | 整层房间图（宝箱/商店/隐藏/恶魔/天使/挑战/游戏厅按兴趣分排序）+ 房间网格 Dijkstra |
| 战斗 | 按武器（眼泪/蓄力/近战/制导）找射击位；弹幕/激光/炸弹/手 的短时预演闪避 |
| Knight | 正面无敌盾：绕后打后脑勺，带引擎方向校准，打不到用炸弹兜底 |
| Host | 停止开火、大范围换角走动，等壳打开再打 |
| Globin | 补刀泥巴，防止复活 |
| Boss | 召唤型先清小怪；近身惩罚型拉远；爆发型更早丢炸弹/主动 |
| 卡牌 | 只带"已知有用"的卡；Boss 战优先用、残血回血用；地上有更好的会丢弃旧卡换新 |
| 药丸 | 不捡、不用（效果未知，保守） |
| 商店 | 按品质买、残血买心、电池按需、钥匙/炸弹少时才买 |
| 宝箱 | 金宝箱必开；钥匙箱 ≥3 把钥匙才开；红宝箱血量够才开 |
| 清房 | 火堆、屎、彩色石/超级彩色石/金石头；蓝/白火与被砖/坑挡住的目标放弃 |
| 地刺 | 读升降状态，只踩缩下去的；脚下升起会横移离开；3 秒无进展强制趟刺 |
| 隐藏房 | 从楼层数据找未发现的隐藏房，炸共享墙进入 |
| Boss 前 | 血少时进 Boss 房前先用回血卡 |
| 学习 | 按敌人类型累计"被打中次数"（跨局），危险的先杀、拉远打 |

## 运行流程

```
MC_POST_UPDATE
   └─ brain.update
        ├─ 读房间/玩家/实体
        ├─ grid.build        （可走格、石头、火堆、地刺、宝箱）
        ├─ grid.flood        （从玩家出发的 Dijkstra 代价）
        ├─ danger.collect    （弹幕、激光、炸弹、血迹、手）
        └─ 选一个目标：战斗 / 按钮 / 拾取 / 用卡 / 清房 / 隐藏房 / 门 / 出口
             └─ danger.choose（模拟 8 个方向，选最安全）
                  └─ B.move / B.shoot / B.tap → MC_INPUT_ACTION
```

细节见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## F8 菜单

- 运行开关（等同 F9）、目标、角色、6 个行为开关；
- 预设系统：内置（标准 / 速通到妈妈 / 阿萨谢尔到羔羊）+ 自建；
- 优先级 / 排除列表 + 道具目录 + 搜索；
- 所有设置存在 mod 存档里。

菜单文字是英文：当前版本游戏的 CJK 像素字体只有"宽度"没有真正字形，中文会画成方块。

## 安装

1. 把本仓库内容放到
   `...\The Binding of Isaac Rebirth\mods\isaac_bot\`；
2. 游戏里启用 mods，控制台执行：
   ```
   luamod isaac_bot
   ```
3. 左下角出现 `PP | <状态> <细节>   F8 Menu` 即加载成功。

## 按键

| 键 | 作用 |
|---|---|
| F8 | 设置菜单 |
| F9 | 开/关机器人（Off = 完全不操作） |
| F7 | 切换预设 |

## 学习机制

每次被敌人打中，都记到该敌人类别（`类型.变体`）名下，写进 mod 存档：
- 被某类怪打中次数多 → **优先击杀**、**站位拉远**；
- 死亡时把死因归给"最后一个打你的敌人"；
- 日志事件：`learn_hit`、`learn_death`。

这是**威胁模型**，不是出招数据库。Boss 的逐招处理是"一只一只加"的（见
[docs/BOSSES.md](docs/BOSSES.md)）。

## 日志与事件

mod 把 `[IsaacBot] EV {...}` 写进 `log.txt`，完整事件表见
[docs/EVENTS.md](docs/EVENTS.md)。

## 开发

- 模块与数据流：[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 如何扩展（Boss/卡牌/敌人/房间）：[docs/DEVELOPING.md](docs/DEVELOPING.md)
- 贡献指南：[CONTRIBUTING.md](CONTRIBUTING.md)
- 把游戏目录同步进本仓库：`tools/sync-from-game.sh`

## 路线图

- 更多 Boss 逐招（妈妈、以撒、Hush、Delirium、野兽……）
- 献祭房策略
- 不走楼层数据的"看墙找隐藏房"
- 主动道具价值模型

## 许可

MIT。原作者版权保留在 [LICENSE](LICENSE)，上游项目见 [CREDITS.md](CREDITS.md)。

## 免责声明

仅单机使用。开 mod 会禁用游戏成就，这是游戏本身的限制。
