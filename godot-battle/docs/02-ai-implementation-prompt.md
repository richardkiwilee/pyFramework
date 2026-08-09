# Godot 实现提示词

> 以下提示词供 AI（如 Claude、GPT 等）使用，用于实现两个 Godot 场景。请将完整提示词发送给目标 AI。

---

## 项目背景

你需要在 Godot 4.x 引擎中，基于《圣兽之王》（Unicorn Overlord）的战斗系统，实现两个游戏场景。项目已初始化在 `godot-battle` 目录下。

参考文档：[游戏设计文档](./01-game-design.md)

---

## 场景一：队伍编辑场景（TeamEditor）

### 场景功能描述

实现一个队伍编辑界面，允许玩家对对战双方的队伍进行配置。

### 具体要求

#### 1. 界面布局

```
┌─────────────────────────────────────────────────┐
│                队伍编辑 - 战前准备                │
├──────────────────┬──────────┬───────────────────┤
│   我方队伍 (蓝方)  │          │  敌方队伍 (红方)   │
│                   │          │                   │
│  [上场单位列表]    │  VS      │  [上场单位列表]     │
│  ┌─────────────┐ │          │ ┌─────────────┐   │
│  │ 1. 骑士 Lv10 │ │          │ │ 1. 战士 Lv10 │   │
│  │ HP:150 ATK:30│ │          │ │ HP:140 ATK:35│   │
│  │ [装备] [下阵] │ │          │ │ [装备] [下阵] │   │
│  │ 2. 法师 Lv10 │ │          │ │ 2. 弓手 Lv10 │   │
│  │ HP:100 MATK:4│ │          │ │ HP:110 ATK:28│   │
│  │ [装备] [下阵] │ │          │ │ [装备] [下阵] │   │
│  └─────────────┘ │          │ └─────────────┘   │
│                   │          │                   │
│  [候补单位列表]    │          │  [候补单位列表]     │
│  ┌─────────────┐ │          │ ┌─────────────┐   │
│  │ 3. 牧师 Lv8  │ │          │ │ 3. 盗贼 Lv8  │   │
│  │ [上阵]        │ │          │ │ [上阵]        │   │
│  └─────────────┘ │          │ └─────────────┘   │
│                   │          │                   │
├──────────────────┴──────────┴───────────────────┤
│              [🎮 开始战斗]                        │
└─────────────────────────────────────────────────┘
```

#### 2. 功能需求

| 功能 | 说明 |
|------|------|
| **上阵/下阵** | 点击单位卡片上的按钮，将单位从上场列表移入/移出。每方上场人数限制为 3-5 人 |
| **装备编辑** | 点击「装备」按钮弹出装备选择面板，显示可用装备列表，可装备/卸下武器、副手、饰品 |
| **单位属性预览** | 单位卡片显示：名称、等级、HP、ATK/MATK、DEF/MDEF、速度。装备后属性实时更新 |
| **队伍平衡检查** | 开始战斗前检查双方人数一致（3v3、4v4 或 5v5），不一致时弹出提示 |
| **开始战斗** | 点击「开始战斗」按钮，将双方队伍数据传递给场景二，切换到战斗场景 |
| **返回/重置** | 提供重置按钮，恢复默认编队 |

#### 3. 数据结构

```gdscript
# 单位数据
class UnitData:
    var id: String
    var name: String
    var class_name: String      # 职业名
    var level: int
    var hp_max: int
    var hp_current: int
    var atk: int                # 物理攻击
    var def_: int               # 物理防御
    var matk: int               # 魔法攻击
    var mdef: int               # 魔法防御
    var hit: int                # 命中
    var evasion: int            # 回避
    var crit_rate: int          # 暴击率
    var guard_rate: int         # 格挡率
    var speed: int              # 行动速度
    var ap_max: int             # AP上限
    var pp_max: int             # PP上限
    var active_skills: Array    # 主动技能列表
    var passive_skills: Array   # 被动技能列表
    var tactics: Array          # 策略配置（优先级列表）
    var equipment: Dictionary   # 装备 {weapon: null, offhand: null, accessory1: null, accessory2: null}

# 装备数据
class EquipmentData:
    var id: String
    var name: String
    var slot: String            # weapon | offhand | accessory
    var stats: Dictionary       # 属性加成
    var granted_skill: String   # 附带的技能ID
    var immunities: Array       # 免疫的状态

# 技能数据
class SkillData:
    var id: String
    var name: String
    var skill_type: String      # active | passive
    var cost: int               # AP或PP消耗
    var power: int              # 威力倍率
    var damage_type: String     # physical | magical | true
    var target_type: String     # single_enemy | row_enemy | all_enemy | self | single_ally | row_ally | all_ally
    var effects: Array          # 附加效果
```

#### 4. 预设数据要求

至少提供 8 种不同的单位预设和 10 种装备预设，确保双方可以组成有意义的对战队伍。

---

## 场景二：战斗场景（BattleScene）

### 场景功能描述

实现一个自动回合制战斗场景，根据单位配置的策略自动进行战斗。

### 具体要求

#### 1. 界面布局

```
┌─────────────────────────────────────────────────┐
│  我方 (蓝方)                 敌方 (红方)         │
│                                                   │
│  ┌───┐ ┌───┐ ┌───┐    ┌───┐ ┌───┐ ┌───┐      │
│  │ 后│ │ 后│ │ 后│    │ 前│ │ 前│ │ 前│      │
│  │ 排│ │ 排│ │ 排│    │ 排│ │ 排│ │ 排│      │
│  │ 1 │ │ 2 │ │ 3 │    │ 1 │ │ 2 │ │ 3 │      │
│  └───┘ └───┘ └───┘    └───┘ └───┘ └───┘      │
│  ┌───┐ ┌───┐ ┌───┐    ┌───┐ ┌───┐ ┌───┐      │
│  │ 前│ │ 前│ │ 前│    │ 后│ │ 后│ │ 后│      │
│  │ 排│ │ 排│ │ 排│    │ 排│ │ 排│ │ 排│      │
│  │ 1 │ │ 2 │ │ 3 │    │ 1 │ │ 2 │ │ 3 │      │
│  └───┘ └───┘ └───┘    └───┘ └───┘ └───┘      │
│                                                   │
├─────────────────────────────────────────────────┤
│  战斗日志                          速度条         │
│  ┌──────────────────────────┐ ┌──────────────┐  │
│  │ > 骑士 使用 重斩 对 战士  │ │ 法师  ████░░ │  │
│  │   造成 45 点伤害！        │ │ 弓手  ██████ │  │
│  │ > 战士 触发 格挡！        │ │ 骑士  ██░░░░ │  │
│  │ > 法师 使用 火球术 对     │ │ 战士  ██████ │  │
│  │   骑士 造成 60 点伤害！   │ │              │  │
│  └──────────────────────────┘ └──────────────┘  │
├─────────────────────────────────────────────────┤
│  AP: ◆◆◇  PP: ◆◇◇    [⏸️暂停] [⏩加速] [↩️返回] │
└─────────────────────────────────────────────────┘
```

#### 2. 战斗系统功能

| 功能 | 说明 |
|------|------|
| **回合自动推进** | 按行动速度排序，从高到低依次执行每个单位回合 |
| **策略条件评估** | 每个单位回合遍历其策略列表（优先级1→N），条件满足则释放对应技能 |
| **AP/PP消耗** | 主动技能消耗AP，被动技能在触发条件满足时消耗PP |
| **伤害计算** | 按设计文档公式计算：命中→暴击→格挡→最终伤害 |
| **状态效果** | 支持中毒（每回合30%HP）、灼烧、冰冻（跳过回合）、眩晕 |
| **Buff/Debuff** | 支持攻击/防御/速度增益减益，可叠加 |
| **战斗日志** | 实时滚动显示每次行动的结果 |
| **速度条显示** | 可视化显示各单位的行动顺序 |
| **战斗结束判定** | 一方全灭或双方AP耗尽，比较HP损失判定胜负 |
| **暂停/加速** | 暂停自动战斗或加速播放 |
| **结果界面** | 战斗结束后弹出胜负结果，显示战斗统计 |

#### 3. 战斗核心逻辑（伪代码）

```gdscript
func start_battle(team_a: Array, team_b: Array):
    # 初始化：所有单位ap=ap_max, pp=pp_max, hp=hp_max
    # 触发所有单位的"战斗开始时"被动技能
    
    while true:
        # 1. 收集所有存活单位
        all_units = get_alive_units(team_a) + get_alive_units(team_b)
        
        # 2. 按速度降序排列
        all_units.sort_by_speed_descending()
        
        # 3. 逐个执行回合
        for unit in all_units:
            if unit.ap <= 0:
                continue  # AP耗尽，跳过
            if unit.is_stunned or unit.is_frozen:
                continue  # 被控制，跳过
            
            # 4. 遍历策略列表
            action_taken = false
            for tactic in unit.tactics:
                if evaluate_conditions(tactic.conditions, unit, all_units):
                    target = select_target(tactic, unit, all_units)
                    if target:
                        execute_skill(tactic.skill, unit, target)
                        action_taken = true
                        break
            
            if not action_taken:
                log("{} 待命".format(unit.name))
        
        # 5. 检查战斗结束条件
        if team_a_all_dead or team_b_all_dead:
            declare_winner()
            break
        
        if all_units_ap_depleted():
            compare_hp_lost()  # HP损失更多的一方失败
            break
        
        # 6. 回合结束处理（中毒伤害、hot/dot触发等）
        process_end_of_round_effects()

func evaluate_conditions(conditions, unit, all_units):
    # 根据"仅"和"优先"规则评估条件
    # 详见设计文档第四章

func calculate_damage(skill, attacker, defender):
    # 命中判定
    hit_chance = attacker.hit - defender.evasion
    if defender.is_melee_target and not defender.is_soldier_class:
        hit_chance -= defender.evasion  # 近战×2回避
    if rand() * 100 > hit_rate_table[hit_chance]:
        return MISS
    
    # 基础伤害
    base_damage = (attacker.atk if skill.damage_type == "physical" else attacker.matk)
    base_damage *= skill.power / 100.0
    
    # 属性克制
    if is_counter_class(attacker, defender):
        base_damage *= 2.0
    
    # 暴击
    is_crit = rand() * 100 < attacker.crit_rate
    if is_crit:
        base_damage *= 1.5
    
    # 防御/格挡
    if skill.damage_type == "physical":
        base_damage -= defender.def_
        if rand() * 100 < defender.guard_rate:
            base_damage *= (1.0 - defender.guard_reduction)
    
    return max(1, int(base_damage))
```

#### 4. 动画与视觉要求

- 单位受击时闪烁/抖动
- 伤害数字弹出（物理伤害白色，魔法伤害紫色，暴击黄色大号）
- 技能释放时简单的粒子/光线效果（可根据技能颜色变化）
- HP条实时更新
- 战斗日志带打字机效果逐条显示
- 单位死亡时淡出

#### 5. 音效需求（使用免费资源）

- 攻击命中音效
- 技能释放音效
- 格挡音效
- 暴击音效
- 胜利/失败音效
- 背景音乐

---

## 全局技术要求

### 1. Godot版本
- **Godot 4.3+**，使用 GDScript

### 2. 项目结构建议
```
godot-battle/
├── scenes/
│   ├── team_editor.tscn
│   └── battle_scene.tscn
├── scripts/
│   ├── team_editor/
│   │   ├── team_editor.gd
│   │   ├── unit_card.gd
│   │   ├── equipment_panel.gd
│   │   └── unit_data.gd
│   ├── battle/
│   │   ├── battle_manager.gd          # Autoload
│   │   ├── battle_scene.gd
│   │   ├── combatant.gd               # 战斗单位节点
│   │   ├── skill_system.gd
│   │   ├── condition_evaluator.gd
│   │   ├── damage_calculator.gd
│   │   ├── status_effects.gd
│   │   ├── battle_log.gd
│   │   └── battle_ui.gd
│   └── data/
│       ├── unit_database.gd
│       ├── skill_database.gd
│       ├── equipment_database.gd
│       └── battle_data.gd             # 场景间数据传递
├── assets/
│   ├── sprites/
│   │   ├── units/                     # 单位精灵
│   │   └── effects/                   # 特效精灵
│   ├── ui/
│   │   ├── buttons/
│   │   ├── panels/
│   │   └── icons/
│   └── audio/
│       ├── sfx/
│       └── bgm/
├── docs/
│   ├── 01-game-design.md
│   ├── 02-ai-implementation-prompt.md
│   └── 03-assets-guide.md
└── project.godot
```

### 3. 代码规范
- 使用静态类型声明 (`var hp: int = 100`)
- 信号用于组件间通信
- 资源文件 (.tres) 存储单位/装备/技能预设数据
- 使用 Autoload 管理全局状态（战斗管理器、数据传递）

### 4. UI 规范
- Control 节点使用锚点布局，适配不同分辨率（设计基准 1920×1080）
- 按钮状态（正常/悬停/按下/禁用）
- 中文文本使用系统字体或内置 fallback 字体
- 颜色方案：蓝方(#4488ff) vs 红方(#ff4444)，UI底色深色(#1a1a2e)

---

## 交付物清单

1. ✅ `scenes/team_editor.tscn` + 相关脚本 — 可运行的队伍编辑场景
2. ✅ `scenes/battle_scene.tscn` + 相关脚本 — 可运行的战斗场景
3. ✅ Autoload 配置 — BattleManager, BattleData
4. ✅ 预设数据 — 至少8个单位、10个装备、15个技能
5. ✅ 场景间数据传递正常工作
6. ✅ 战斗日志正确显示
7. ✅ 伤害计算符合设计文档公式
8. ✅ 基本的视觉特效和音效

---

> **提示词版本**: v1.0 | **目标 AI**: 支持 Godot 4.x GDScript 的任意 AI 编码助手
