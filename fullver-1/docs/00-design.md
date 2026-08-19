# fullver-1 游戏框架设计文档

> 本文档是 fullver-1 的权威设计文档。领域术语定义见 [../CONTEXT.md](../CONTEXT.md)，架构决策记录见 [adr/](adr/)。
> 依据：[../readmd.md](../readmd.md)（项目需求）；参考项目：`../demo-1`（编队战斗）、`../demo-2`（大地图移动）、`../diplomacy`（外交）、`D:\AbilityKit`（战斗系统概念）；运行环境：Godot 4.6.2（`D:\Godot\Godot_v4.6.2-stable_win64_console.exe`）、Python 3.14（`C:\Python314\python.exe`）、内置框架 zfoo/godot-framework（autoload `GodotFramework`，class_name `gdf`）。

---

## 1. 项目目标与范围

将 demo-1（编队战斗）、demo-2（大地图移动）、diplomacy（外交）三个独立实验**合并为一个回合制策略游戏框架**，跑在 zfoo/godot-framework 之上。目标是一个**可玩的垂直切片**：开始新游戏 → 大地图经营与移动 → 军团相遇进入战斗 → 外交互动 → 结束回合循环，全部系统数据驱动、逻辑与表现分离。

**范围外**（框架阶段不做）：联机、热更新接入（zfoo 已提供，暂不接业务）、完整数值平衡、真实美术资源。

## 2. 设计原则

1. **代码、数据、资源三者分离**（readme 硬性要求）：逻辑在 `scripts/`，静态配置在 `data/*.json`，美术在 `assets/`，三者只通过 DataManager / ArtIndex 的具名接口互相访问。
2. **逻辑与表现分离**：领域逻辑全部是纯 `RefCounted` 类（无节点、无绘制），可 headless 测试；场景脚本只做输入、展示、播放。
3. **美术资源索引化 + 占位符回退**（readme 硬性要求）：所有视觉引用走 `ArtIndex`，资源缺失时三级回退（纹理 → emoji → 基础 UI 组件），任何数据缺失都不崩。
4. **深模块**（codebase-design）：每个系统暴露小接口、隐藏大实现，接口即测试面。
5. **AI 可挂载**（readme 硬性要求）：AI 回合思考/行动通过可替换的 GDScript 脚本接入，详见第 9 节。
6. **中文注释 + Python 类比**：维护者精通 Python、无 GDScript 经验，所有脚本用中文完整注释，GDScript 特有机制附 Python 类比说明（demo-1 的注释风格）。
7. **数据校验测试**：JSON 数据与代码的"效果全集/字段名/引用完整性"由测试兜底（吸收 demo-1 "效果静默丢失"教训）。

## 3. 总体架构

```
┌─────────────────────────────────────────────────────────┐
│ 表现层  scenes/ + scripts/ui/                            │
│   MainMenuScreen  WorldMapScreen(+Overlay)               │
│   CityScreen  UnitEditorScreen  BattleScreen             │
│   （只做输入/绘制/动画/播放，通过信号订阅系统）             │
├─────────────────────────────────────────────────────────┤
│ 系统层  scripts/{world,battle,diplomacy,economy,ai}/     │
│   WorldMapModel  BattleEngine  DiplomacySystem           │
│   EconomySystem  TurnManager  AIController               │
│   （纯 RefCounted，无 Node 依赖，可 headless 测试）        │
├─────────────────────────────────────────────────────────┤
│ 领域层  scripts/core/                                    │
│   GameState Faction City Army Team Unit Relation Treaty  │
│   （运行态数据，全部可 to_dict/from_dict 序列化）           │
├─────────────────────────────────────────────────────────┤
│ 基础层  autoload 单例                                    │
│   DataManager UITheme I18n ArtIndex GameManager          │
│   + zfoo 框架（gdf / SceneHelper / Alert / gdtest …）     │
└─────────────────────────────────────────────────────────┘
```

- 依赖方向严格自上而下：表现层 → 系统层 → 领域层 → 基础层。**领域层不知道表现层存在**（demo-1 把 UI 引用塞进单位字典的坑，这里明确禁止）。
- 系统层通过信号向上广播事件，表现层订阅；表现层通过命令方法向下调用。
- 跨场景存活的数据只放领域层对象（由 GameManager 持有），autoload 不做业务数据。

## 4. 目录结构

```
fullver-1/
├── CONTEXT.md                  # 领域词汇表
├── docs/
│   ├── 00-design.md            # 本文档
│   └── adr/                    # 架构决策记录
├── project.godot               # autoload / 输入 / 显示配置
├── zfoo/                       # godot-framework（既有，不动）
├── data/                       # ★ 全部静态数据（JSON）
│   ├── world/map.json          # 城市 + 路线（据点图）
│   ├── factions.json           # 势力 + AI 策略挂载
│   ├── characters.json         # 单位角色
│   ├── classes.json            # 职业
│   ├── skills.json             # 技能 + 触发规则
│   ├── items.json              # 装备/道具
│   ├── resources.json          # 资源定义（图标/颜色/用途）
│   ├── diplomacy.json          # 外交参数（阈值/朝贡/初始关系）
│   ├── art_index.json          # 美术索引（id → 资源路径/emoji/颜色）
│   └── i18n/{zh,en}.json       # 多语言文本
├── assets/                     # 美术资源（当前为空 → 走占位符回退）
├── scenes/                     # 场景壳（节点少，UI 代码构建）
│   ├── main_menu.tscn
│   ├── world_map.tscn
│   ├── city_manage.tscn
│   ├── unit_editor.tscn
│   └── battle.tscn
├── scripts/
│   ├── autoload/               # 5 个 autoload 单例
│   │   ├── game_manager.gd     # 游戏流程/存档/场景编排
│   │   ├── data_manager.gd     # 数据加载/索引/校验
│   │   ├── ui_theme.gd         # 字体/色板/样式工厂
│   │   ├── i18n.gd             # 多语言
│   │   └── art_index.gd        # 美术索引 + 占位符回退
│   ├── core/                   # 领域层（RefCounted）
│   │   ├── game_state.gd
│   │   ├── faction.gd  city.gd  army.gd  team.gd  unit.gd
│   │   ├── relation.gd  treaty.gd
│   │   └── turn_manager.gd
│   ├── world/                  # 大地图系统
│   │   ├── world_map_model.gd  # 据点图 + 移动点数
│   │   └── pathfinder.gd       # Dijkstra 寻路
│   ├── battle/                 # 战斗系统
│   │   ├── battle_engine.gd    # 先算后播引擎
│   │   ├── battle_unit.gd      # 战斗单位
│   │   └── trigger_runner.gd   # 事件→条件→动作
│   ├── diplomacy/
│   │   └── diplomacy_system.gd
│   ├── economy/
│   │   └── economy_system.gd
│   ├── ai/                     # AI 挂载机制
│   │   ├── base_ai_strategy.gd # ★ 用户扩展的基类
│   │   ├── ai_context.gd       # 只读局面视图
│   │   ├── ai_controller.gd    # 加载/调度策略脚本
│   │   └── strategies/basic_ai.gd  # 内置简单策略示例
│   └── ui/                     # 表现层
│       ├── main_menu_screen.gd
│       ├── world_map_screen.gd
│       ├── world_overlay.gd    # 遮罩1：资源栏/按钮/结束回合
│       ├── city_screen.gd
│       ├── unit_editor_screen.gd
│       ├── battle_screen.gd
│       └── widgets/            # 复用控件（提示条/消息面板/占位图标…）
├── tests/                      # gdtest 测试
│   ├── test_all.tscn           # IntegrationTest 总驱动
│   ├── test_data.tscn          # 数据加载与校验
│   ├── test_core.tscn          # 领域层
│   ├── test_battle.tscn
│   ├── test_diplomacy.tscn
│   └── unit/                   # 测试脚本（方法名 test 开头/结尾）
└── saves/                      # 运行期生成于 user://（不进仓库）
```

## 5. Autoload 基础层接口

### 5.1 DataManager（数据）
```gdscript
func load_all_data() -> void                    # 幂等；启动时调用
func get_faction(id: String) -> Dictionary      # 全部 getter 都是 .get(key, default)
func get_character(id: String) -> Dictionary
func get_class(id: String) -> Dictionary
func get_skill(id: String) -> Dictionary
func get_item(id: String) -> Dictionary
func get_resource_def(id: String) -> Dictionary
func get_map_data() -> Dictionary               # {cities:[], routes:[]}
func get_diplomacy_config() -> Dictionary       # 阈值/朝贡/初始关系
func validate_all_data() -> Array[String]       # 数据校验，返回错误列表（空=通过）
```
校验项：`id` 唯一性、`skill.effects` 的 effect_type 全部存在于代码注册表（防 demo-1 静默丢失）、JSON key 存在性、引用完整性（单位→职业/技能存在）。

### 5.2 I18n（多语言）
```gdscript
func t(key: String, args: Array = []) -> String    # 占位符 {} 风格，与 Log 一致
func set_language(lang: String) -> void            # "zh"/"en"，写入 Setting 并 save()
func language() -> String
```
- 方法名为 `t()` 而非 `tr()`：Godot 原生 `Object.tr()` 被覆盖会触发警告视为错误（实测坑）。
- 文案文件 `data/i18n/zh.json`（默认）/`en.json`；UI 文案全部走 key：`I18n.t("ui.world.end_turn")`。
- 字体按语言切换（I18n 通知 UITheme）。

### 5.3 ArtIndex（美术索引）
```gdscript
func get_icon(id: String) -> Texture2D        # 三级回退，永不返回 null
func get_emoji(id: String) -> String          # emoji 回退表
func get_color(id: String) -> Color           # 势力/职业颜色表
```
回退链：`assets/` 下有对应文件 → `art_index.json` 配的 emoji → 通用占位符（默认色块+字符）。索引表本身是数据（`data/art_index.json`），新增美术=加资源文件+改索引表，零代码。

### 5.4 UITheme（样式）
继承 demo-1 方案：SystemFont 字体链（中文 `["Microsoft YaHei","SimHei","Noto Sans CJK SC","sans-serif"]`；emoji 独立 `["Segoe UI Emoji","Segoe UI Symbol"]`——SystemFont 不做逐字回退，混排必须拆 Label）；StyleBoxFlat 工厂（`panel_style()/button_style()/gold_button_style()/...` 每次返回新实例）；色板常量。注意用 `ThemeDB.get_default_theme().duplicate()`（`get_project_theme()` 运行时为 null，civ-6 教训）。

### 5.5 GameManager（游戏流程）
```gdscript
signal turn_started(turn: int)
signal turn_ended(turn: int)
signal game_event(kind: String, data: Dictionary)   # 全局消息（外交/战斗/经济事件都走这里）

func new_game(save_slot: int) -> void
func save_game(slot: int) -> void                    # GameState.to_dict() → JSON → user://saves/slot_N.json
func load_game(slot: int) -> bool
func list_saves() -> Array
func end_turn() -> void                              # 流程见 §7
func change_scene(scene_path: String) -> void        # 内部用 SceneHelper.async_change_scene_to_file
func get_game_state() -> GameState
func get_player_faction() -> Faction
```
注意：GameManager 不做领域计算，只做编排与持久化。

## 6. 领域层（scripts/core/）

全部 `class_name` + `extends RefCounted`，字段显式类型（本环境 INFERRED_DECLARATION 警告视为错误），每个类提供 `to_dict()` / `from_dict()`（存档用），禁止持有任何 Node/UI 引用。

| 类 | 关键字段/方法 | 说明 |
|---|---|---|
| `GameState` | turn, factions: Array[Faction], cities: Array[City], armies: Array[Army], relations: Array[Relation], event_log | 完整运行态，唯一序列化根 |
| `Faction` | id, is_player, ai_strategy(脚本路径), resources: Dictionary, at_war 集合 | 玩家与 AI 同构（diplomacy 项目"无玩家对象"坑的修正） |
| `City` | id, owner_faction_id, position: Vector2, level, garrison_army_id | 据点图节点 |
| `Army` | id, owner_faction_id, team: Team, current_city_id, move_points/max_move_points | 战略层移动单位 |
| `Team` | units: Array[Unit]（≤9）、captain | 3×3 编队；**slot→战斗位置映射显式化**（见 §8，修正 demo-1 棋盘位与战斗位脱节） |
| `Unit` | id, character_id, class_id, level, stats: Dictionary, skills, equipment, exp | 角色实例 |
| `Relation` | faction_a, faction_b, attitude: float(-100~100), at_war: bool, treaties: Array[Treaty] | 双边记录（diplomacy 项目单侧视角的修正） |
| `Treaty` | type, remaining_rounds, params | 有持续时间；回合推进时递减、到期失效 |

## 7. 回合流程（TurnManager）

```
end_turn()
 ├─ 玩家势力回合结束（提交移动/内政结果）
 ├─ 依次执行每个 AI 势力回合：
 │    AIController.run_faction_turn(faction, ai_context)
 │      → on_turn_start → on_army_phase → on_diplomacy_phase → on_turn_end
 ├─ EconomySystem.settle_turn()      # 城市产出 → 军费 → 资源结算
 ├─ DiplomacySystem.tick_treaties()  # 条约倒计时
 ├─ turn += 1
 └─ emit turn_started(turn)           # 新回合，玩家可操作
```
战斗是"打断点"：AI 军团移动进攻玩家时，先暂停战略层、切战斗场景，战斗结束后回到 turn 流程继续（GameManager 记录 pending 状态）。

## 8. 大地图系统（scripts/world/）

**WorldMapModel**（纯逻辑）：
```gdscript
func get_cities() -> Array[Dictionary]              # 只读
func get_routes() -> Array[Dictionary]              # [city_a, city_b, distance]
func find_path(from_city_id: String, to_city_id: String) -> Array[String]  # Dijkstra，无路返回 []
func can_army_move(army: Army) -> bool              # move_points 剩余
func move_army(army: Army, target_city_id: String) -> bool
func armies_at(city_id: String) -> Array[Army]
func adjacent_cities(city_id: String) -> Array[String]
```
- 数据来自 `data/world/map.json`；构建邻接表缓存 + O(1) id 索引（demo-2 三张缓存表思路）。
- 移动规则：一次行动只能沿一条路线移动到相邻城市（消耗 1 移动点）；目标城市有敌对军团时触发战斗（见 §9）。
- 渲染（WorldMapScreen）用 demo-2 方案：逻辑坐标系 `MAP_W×MAP_H` + `_to_screen()` 缩放平移投影；虚线贝塞尔路线与移动动画**共用同一控制点公式**（`mid + perp * bend`）；静止时不重绘（demo-2 每帧 queue_redraw 的坑）。

## 9. 战斗系统（scripts/battle/）

### 9.1 引擎（ADR-0001：先算后播）
```gdscript
signal battle_started()
signal battle_ended(result: String)          # victory/defeat/draw
signal round_started(round_num: int)
signal battle_action(action: Dictionary)     # 播放事件（含 skipped）

func start_battle(attacker_army: Army, defender_army: Army) -> void
func next_action() -> Dictionary             # 播放队列下一个；空 {} = 本拍无
func is_over() -> bool
```
- `start_battle` 把编队单位实例化为 `BattleUnit`（**类而非字典**，修正 demo-1 裸字典+UI 引用的耦合）；**编队 3×3 格子显式映射战斗站位**：前排格子（slot 6/7/8）→ 战斗前排（position 0-2），后排（slot 0-2）→ position 3-5（修正 demo-1 "摆位不影响战斗"缺陷）。
- 回合内：按速度排序 → **同步预计算**全部行动（伤害即时生效，死亡插入队列尾部重排）→ `next_action()` 逐条弹出播放；播放层用 Timer 轮询（demo-1 模式，0.9s 间隔）。
- 结算链（简化 AbilityKit 伤害管线）：暴击（随机值注入，可复现）→ 加成 → 护甲减伤（`damage*100/(100+armor)`）→ 取整 → 护盾。
- 结束：一方全灭/回合上限/双方待机 → `battle_ended` → 胜方 Army 占领城市。

### 9.2 触发/被动时点系统（完整移植 demo-1 + 校验，用户决策）

**用户已确认：完整移植 demo-1 的全部 222 技能、55 条件、状态效果与被动时点体系**（`EFFECT_TRIGGERS` 全时点：`battle_start / round_start / before_action / on_hit / on_kill / after_hit / battle_end` 及 Buff tick），同时按本项目要求改进：

- **效果注册表**（`scripts/battle/effect_registry.gd`）：demo-1 的 `EFFECT_TRIGGERS` 常量迁出为独立模块，暴露**效果名全集**；
- **数据校验**（防 demo-1 `heal_on_kill` 静默丢失）：`DataManager.validate_all_data()` 在启动与测试双处执行，skills.json 中每个 effect_type 必须在注册表里有实现，缺一个立即报错；
- demo-1 未实现的效果（如 `heal_on_kill`）**补齐实现**，注册表与数据全集对齐；
- 被动消耗 PP、`_dispatch_passives` 时点分派、死亡队列重排、目标选取（single/row/column/all/multi/self/ally/ally_row）全保留。

### 9.3 战斗 UI（BattleScene）
头部队列/战场区/战斗日志/结果覆盖层；只订阅引擎信号 + 轮询 `next_action()`，动画用 Tween；日志面板接收 `game_event`。

## 10. AI 挂载机制（readme 硬性要求，scripts/ai/）

### 10.1 扩展点
```gdscript
# base_ai_strategy.gd —— 用户编写自定义 AI 时继承这个类
class_name BaseAIStrategy
extends RefCounted

func setup(faction: Faction) -> void: pass
func on_turn_start(ctx: AIContext) -> void: pass        # 内政/建设决策
func on_army_phase(ctx: AIContext) -> void: pass        # 移动/进攻决策
func on_diplomacy_phase(ctx: AIContext) -> void: pass   # 宣战/贸易/结盟决策
func on_turn_end(ctx: AIContext) -> void: pass
```
### 10.2 AIContext（只读视图 + 指令集）
```gdscript
class_name AIContext
extends RefCounted
# —— 只读视图 ——
func faction() -> Faction
func map_data() -> Dictionary
func armies() -> Array[Army]                  # 本势力的
func enemy_factions() -> Array[Faction]
func relations() -> Array[Relation]
func game_state() -> GameState
# —— 指令（经系统校验后执行，非法指令返回 false + 原因）——
func issue_move(army: Army, target_city_id: String) -> bool
func issue_declare_war(target: Faction) -> bool
func issue_propose_trade(target: Faction, give: Dictionary, ask: Dictionary) -> bool
func issue_raise_army(city_id: String) -> bool
```
**只读视图防作弊/防越权**：AI 只能通过指令行动，指令内部走与玩家相同的系统校验路径。

### 10.3 挂载方式
1. 用户在 `scripts/ai/strategies/`（或任意路径）写脚本 `extends BaseAIStrategy`（class_name 可选）；
2. 在 `data/factions.json` 给势力配 `"ai_strategy": "res://scripts/ai/strategies/xxx.gd"`（留空 = 内置 BasicAI）；
3. AIController 用 `ResourceLoader.load(path).new()` 实例化并缓存；**每回合调用各回调**。
- 难度设计 = 给不同难度配不同策略脚本；热更新 PCK 可携带新策略脚本（zfoo HotUpdate 能力预留）。
- `strategies/basic_ai.gd` 是内置示例：军团向最近无主城市移动、被攻击时反击、好感低时宣战——同时作为用户写自定义 AI 的范本（注释详尽）。

## 11. 外交系统（scripts/diplomacy/）

DiplomacySystem（纯逻辑，模型层校验——修正 diplomacy 项目"UI 校验、模型裸奔"的坑）：
```gdscript
func get_relation(a: Faction, b: Faction) -> Relation
func declare_war(a: Faction, b: Faction) -> bool          # 模型层校验重复宣战/已同盟
func make_peace(a: Faction, b: Faction) -> bool
func declare_friendship(a: Faction, b: Faction) -> bool   # 阈值校验在模型层
func declare_alliance(a: Faction, b: Faction) -> bool
func propose_trade(a: Faction, b: Faction, give: Dictionary, ask: Dictionary) -> Dictionary  # {accepted, score, reason}
func demand_tribute(a: Faction, b: Faction) -> Dictionary
func tick_treaties() -> void                              # 回合推进，条约到期
func attitude_level(relation: Relation) -> String         # 推导式：交战/敌视/和平/友好/同盟
```
- 参数（阈值 40/60、朝贡量、衰减率、贸易评分规则）全部进 `data/diplomacy.json`——修正 diplomacy 项目"规则数字散落三处"。
- 双边 `Relation` 不对称（A 对 B 与 B 对 A 独立），条约对称且双方各存一份。
- 所有结果通过 `game_event` 广播（宣战/和平/贸易结果……），UI 订阅展示——修正"只有一行提示"的问题。

## 12. 经济系统（scripts/economy/）

```gdscript
func settle_turn(state: GameState) -> Dictionary    # 产出/军费结算，返回变化明细（供事件面板）
func get_production(city: City) -> Dictionary
```
- 城市产出定义在 `data/resources.json`（每种资源：id/图标/颜色/描述）；城市等级乘数；军团维护费按编队规模。
- 资源不足时的规则（军团解散/士气）框架阶段先做最简：不足则不发薪并记事件。

## 13. 场景结构与流程

| 场景 | 内容 |
|---|---|
| `main_menu.tscn` | 继续游戏/新游戏/读档/设置（语言、音量）/退出 |
| `world_map.tscn` | 大地图 + **遮罩1**（Overlay：顶部资源栏、城市/编成/外交按钮、结束回合按钮、消息面板） |
| `city_manage.tscn` | 城市管理页（升级/征兵/驻军） |
| `unit_editor.tscn` | 部队/单位编辑页（**简化版，用户决策**：3×3 九宫格 + 点击选单位 + 装备下拉，不做滚轮/弹窗/策略编辑） |
| `battle.tscn` | 战斗播放页 |

流程：主菜单 →（新游戏/读档）→ 大地图；大地图按钮 → 城市管理/编成（返回大地图）；军团相遇 → 战斗 → 结算回大地图。场景切换统一 `SceneHelper.async_change_scene_to_file`（转场淡入淡出），战斗为"中断式"：GameManager 保存返回点与进行中的回合流程。

## 14. 多分辨率与多语言

- **多分辨率**：`project.godot` 设 `display/window/size/viewport_width=1920`、`viewport_height=1080`、`stretch/mode="canvas_items"`、`stretch/aspect="keep"`；所有 UI 用锚点 + `size_flags`（注意 Godot 4 是 `size_flags_stretch_ratio`，不是 `stretch_ratio`）；大地图投影自动缩放（demo-2 公式）。
- **多语言**：I18n（§5.2）；UI 文案（按钮/标题/提示/事件）全 key 化；**游戏数据实体的显示名保留数据内联 `name_zh` 字段**（222 技能全 key 化收益低，如语言为 en 且存在 `name_en` 则用之）；语言选择存 Setting（`Setting.set_string` 后**必须 `save()`**，zfoo 约定）；数字/日期格式化随语言。

## 15. 存档系统

- `user://saves/slot_N.json`，`GameState.to_dict()` → `JSON.stringify` 写入（FileUtils.write_string_to_file）；读档 `from_dict` 重建对象图 + 数据校验（版本字段 `save_version`，不兼容则拒绝并提示）。
- 战斗中途存档：只允许战略层存档（战斗结束才可存档，框架阶段简化）。

## 16. 测试策略（gdtest + 本环境验证工作流）

1. **单元测试**（`tests/unit/*.gd`）：方法名以 `test` 开头/结尾、**无参数**（gdtest 硬性约束）；断言 = 失败时 `Log.error(...)`（会触发 `gdf.events.log_error` → FAIL → `gdf.quit(1)`）。封装 `_assert(cond, msg)` 帮助函数。
2. **集成场景**（`tests/test_*.tscn`）：文件名小写以 test 开头；每个场景放 UnitTest 节点；`tests/test_all.tscn` 放 IntegrationTest 节点做总驱动。
3. **运行方式**：
   ```
   D:\Godot\Godot_v4.6.2-stable_win64_console.exe --headless --import --path D:\pyFramework\fullver-1
   D:\Godot\Godot_v4.6.2-stable_win64_console.exe --headless --path D:\pyFramework\fullver-1 res://tests/test_core.tscn
   ```
   注意：**必须先 `--import` 生成 class_name 全局类缓存**，否则 headless 测试找不到类型。
   - 全量套件入口用 `res://tests/test_core.tscn`：UnitTest 扫描 tests/ 下全部脚本，
     退出码 0 = 全部通过（CI 用这个）。
   - `res://tests/test_all.tscn`（IntegrationTest）在编辑器里点运行方便，
     但 CLI 下退出时框架有 SIGSEGV（zfoo IntegrationTest 场景释放 + gdf.quit 的组合问题，
     2026-08 实测：测试全过后崩溃）——自动化场景不要用它判断退出码。
4. **数据校验测试**：`test_data.tscn` 跑 `DataManager.validate_all_data()`（效果全集对齐、引用完整性、字段一致性）——这是 ADR-0003 的补偿手段。
5. **视觉验证**（需要时）：临时 TestDriver autoload 驱动场景 → 截图 → PIL 像素断言（本环境 Read 无法看图，demo-1/civ-6 验证过的流程）；验完删驱动与 `_shots/`。
6. 单脚本语法检查：`godot --headless --path . --check-only --script res://scripts/xxx.gd`。

## 17. 已知坑与规避清单（调研 + 本环境实测记忆）

| # | 坑 | 规避 |
|---|---|---|
| 1 | INFERRED_DECLARATION 警告视为错误 | 全部显式类型标注；Dictionary 取值显式转类型 |
| 2 | `draw_*` 只能在 `_draw()` 内（draw 信号回调里调用报错） | 覆盖层各自独立脚本 + `_draw()`；画布对象作参数传入 |
| 3 | 零尺寸 Control 绘制被剔除 | 自定义绘制节点必须设非零 size |
| 4 | emoji 需独立 SystemFont；`draw_string` width≠-1 彩色 emoji 不渲染；中英混排拆 Label | 全部按 demo-1 实测方案 |
| 5 | z_index 无视节点树顺序 | 弹窗/Overlay 设更高 z_index（如 200） |
| 6 | `stretch_ratio` 已改名 `size_flags_stretch_ratio`；运行时错误中止整个函数 | 写对新名；排查先看第一个错误 |
| 7 | 内嵌类不是全局 class_name；类名撞引擎原生类（TileData） | 独立文件 + class_name；命名避开原生类 |
| 8 | `ThemeDB.get_project_theme()` 为 null | `get_default_theme().duplicate()` |
| 9 | 闭包捕获循环变量 | 循环内先复制局部变量（demo-1 注释惯例） |
| 10 | JSON `.get()` 对 null 值返回 null 而非默认值 | 取到后显式判 null |
| 11 | 数据效果全集与代码注册表不一致 → 静默丢失 | 启动校验 + 测试（§16.4） |
| 12 | 每帧无条件 queue_redraw | 脏标记，状态变化才重绘 |
| 13 | 到达判定用距离遍历 | 直接携带目标 id |
| 14 | `Setting.set_*` 不落盘 | 显式 `Setting.save()` |
| 15 | IComponent 无 class_name 报错；注册在 `_init()` | 组件脚本必须 class_name，`_init()` 里 `start()` |
| 16 | 规则数字散落（阈值/朝贡在 UI、模型、文案三处） | 统一进 `data/diplomacy.json`，UI 从配置读 |
| 17 | UI 校验、模型裸奔（模型方法可被误调用） | 模型层做防御校验，UI 校验只用于即时反馈 |
| 18 | 刷新靠手写全量 `_refresh_all()` | 信号订阅 + 定向刷新 |

## 18. 对三个参考项目的继承与修正

| 来源 | 继承 | 修正 |
|---|---|---|
| demo-1 | autoload 三层；DataManager JSON 模式；先算后播战斗引擎；emoji/占位符回退；PickerFactory 弹窗；闭包复制惯例；中文注释风格 | 战斗单位字典→BattleUnit 类；棋盘位→战斗位显式映射；效果全集校验；UI 引用不再挂在数据上；字段名统一（base_stats vs level_50_stats） |
| demo-2 | 逻辑坐标投影；虚线贝塞尔（绘制/动画共用控制点公式）；id 缓存表 | 数据迁 JSON；加寻路与移动点数；到达判定用 id；静止不重绘 |
| diplomacy | RefCounted 模型；UI 校验→模型执行的分层；推导式态度；关系 -100~100 | 玩家也有 Faction 对象；双边 Relation；Treaty 有持续时间；参数全数据化；模型层校验；game_event 消息系统 |

## 19. 实施顺序（对应 plan 阶段细化）

P0 基础设施（project.godot/目录/autoload 骨架）→ P1 数据层（data/*.json + DataManager + 校验）→ P2 领域层（core 类 + GameState + 存档）→ P3 回合与 AI 机制（TurnManager/AIContext/AIController/BasicAI）→ P4 大地图（模型+寻路+场景+Overlay）→ P5 外交与经济 → P6 战斗（引擎+触发+场景）→ P7 城市管理/编成场景 → P8 主菜单与场景串联 → P9 测试与验证。

## 20. 实施状态（2026-08-19 完成）

全部 P0-P9 已实施并验证：

- **测试**：44/44 用例通过（数据 6 / 领域 7 / AI 8 / 世界 6 / 外交 6 / 经济 4 / 战斗 7），headless 全量入口 `res://tests/test_core.tscn`（退出码 0）。
- **场景**：5 个场景（主菜单/大地图/战斗/城市/编成）headless 冒烟 0 错误；窗口模式截图 + PIL 像素断言 9/9 通过（验证后已删驱动与截图）。
- **框架实测坑补充**（本环境验证，与 §17 互补）：①zfoo `Log.error` 只 printerr 不触发 `gdf.events.log_error`——测试断言必须用 `push_error`；②`ClassDB.class_exists()` 对 GDScript 全局类返回 false（全局类在 ScriptServer）——直接引用类名；③`Dictionary.get()` 返回无类型 Array，直接 return 给 `Array[String]` 会运行时错误——必须拷贝进类型化数组；④字面量 `[]` 是无类型 Array，同样不能直接 return 给类型化返回；⑤`Object.tr()` 是原生方法，自定义 tr 会触发警告视为错误——I18n 用 `t()`；⑥autoload 顺序即初始化顺序（DataManager 必须先于依赖它的）；⑦zfoo IntegrationTest 在 CLI 退出时 SIGSEGV（测试全过后崩）——CI 用 test_core.tscn；⑧`--check-only` 看不到 autoload 名（运行期才解析）——编译验证以运行测试为准；⑨`String.format` 跳过 Array/Dictionary 值（占位符原样留下）——格式化容器必须 `str()` 包裹；⑩`Control._gui_input` 是受保护方法不能从外部直接调用——点击模拟必须走 `get_viewport().push_input(InputEventMouseButton)` 真实管线（含命中测试与 mouse_filter）。

## 21. v2 修订（2026-08-20，用户反馈驱动）

1. **面板居中修复**：`set_anchors_preset(PRESET_CENTER)` 只把锚点放中心、top-left 仍停在中心点（面板画在右下象限）——统一用 `UITheme.center(ctrl)`（锚点居中 + position=-size/2）。
2. **大地图 v2**：1600×1000、22 城 31 路（原 12 城 15 路）；道路大体遵循四方向（允许小幅弯曲），疏开原阿克一带的拥挤路段。
3. **部队移动 = 沿路径多步行军**：点击任意可达城市 → Dijkstra 最短路径 → 逐段行军直到移动力耗尽或遇敌（遇敌转战斗，移动力耗尽弹提示）；`WorldMapModel.move_army_toward()` + 屏幕逐段贝塞尔动画。
4. **遮罩布局**：顶部资源栏占满窗口顶栏（左：回合+资源，右：功能按钮）；结束回合 = 右下角圆形金色按钮；左下角 = 玩家军团统帅竖长方形条（点击=快速选中，选中后功能待后续）。
5. **点击链路实测验证**（合成 InputEventMouseButton + push_input）：点军团标记→点城 → 军团沿最短路径移动 ✓；统帅条点击 → 选中 ✓。

## 22. v3 修订（2026-08-20，第二轮用户反馈）

1. **顶栏文字横排**：顶栏标签统一关闭自动换行（AUTOWRAP_OFF，防挤压时逐字竖排）；资源图标与数量合并为单标签（emoji 字体含 ASCII 数字，混排安全）；顶栏用 offsets 定位（对非等锚点控件设 size 会触发引擎警告）。
2. **"移动两次后动不了"根因修复**：AI 回合连场进攻时，第二场战斗的 battle_requested 信号在战斗场景内发出、无监听者而丢失 → 回合流程永远卡在等待战斗 → 移动力永不刷新。修复：战斗场景返回时检测 `turn_manager.is_awaiting_battle()` 自重入下一场战斗；世界场景 _ready 时兜底检查挂起的战斗请求。新增回归测试 `test_end_turn_battle_resolution_chain`（AI 攻玩家驻军 → 结算 → 回合推进 → 移动力回满 ✓，端到端驱动实测通过）。
3. **战斗攻防视角**：引擎口径 player_units = 进攻方；玩家防守时（AI 进攻我方驻军）战斗场景的显示侧与胜负文案按 `_player_is_attacker` 翻转（结算传给 GameManager 的结果保持引擎口径）。
4. **编成界面复刻 demo-1**：右列详情 = 4 装备槽卡片（武器/盾牌/饰品1/饰品2，点击槽位 → 下拉选装/卸下）+ 8 行行动策略栏（[技能 | 条件1 | 条件2] 下拉 + 删除行 + 新增按钮）。存储：`Unit.equipment`（weapon/shield/acc1/acc2）与 `Unit.strategy`（[{skill, cond1, cond2}]，旧存档的 skills 数组自动迁移）；战斗引擎按策略行技能顺序出战（`battle_skill_ids()`），条件当前仅存储展示（引擎暂不消费，已声明）。
