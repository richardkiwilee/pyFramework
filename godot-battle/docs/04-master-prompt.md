# AI 实现提示词：《圣兽之王》风格战斗系统

> **使用方法**：将本文档内容完整发送给支持 Godot 4.x + GDScript 的 AI 编码助手。
> **参考文档**：`docs/01-game-design.md`（战斗系统设计）、`docs/03-assets-guide.md`（素材指南）

---

## 任务概述

在 `godot-battle` 项目（已初始化的 Godot 4.x 项目）中，实现两个场景：

1. **场景一：队伍编辑场景** — 配置对战双方的队伍、装备、策略
2. **场景二：战斗场景** — 基于《圣兽之王》自动战斗规则的回合制对战

---

## 第一部分：技术架构要求

### 项目基础
- Godot 4.3+，GDScript
- 项目路径：`res://`
- 设计基准分辨率：1920×1080

### 必须创建的 Autoload 单例

**1. BattleData（`res://scripts/data/battle_data.gd`）**
- 场景间传递的队伍数据
- 两个队伍数组：`team_blue: Array[Dictionary]` 和 `team_red: Array[Dictionary]`
- 每个字典包含完整的单位数据、装备、技能、策略配置

**2. BattleManager（`res://scripts/battle/battle_manager.gd`）**
- 管理战斗回合流程
- 信号：`battle_started`, `turn_started(unit)`, `turn_ended(unit)`, `skill_used(caster, skill, target, result)`, `battle_ended(winner)`
- 战斗日志数组

**3. SkillDatabase（`res://scripts/data/skill_database.gd`）**
- 所有技能的预定义数据
- `get_skill(id: String) -> Dictionary`

**4. UnitDatabase（`res://scripts/data/unit_database.gd`）**
- 所有单位模板的预定义数据
- `get_unit_template(id: String) -> Dictionary`
- `get_all_templates() -> Array[Dictionary]`

**5. EquipmentDatabase（`res://scripts/data/equipment_database.gd`）**
- 所有装备的预定义数据
- `get_equipment(id: String) -> Dictionary`

---

## 第二部分：场景一详细规格 — 队伍编辑场景

### 场景文件
`res://scenes/team_editor.tscn`

### 界面结构（Control节点树）

```
TeamEditor (Control)
├── TitleLabel (Label) — "队伍编辑 - 战前准备"
├── HBoxContainer
│   ├── TeamPanel (Panel) — 我方队伍
│   │   ├── TeamTitle (Label) — "我方队伍 (蓝方)"
│   │   ├── ActiveUnitsList (VBoxContainer) — 已上场单位
│   │   └── ReserveUnitsList (VBoxContainer) — 候补单位
│   ├── VSDivider (VBoxContainer)
│   │   └── VSLabel (Label) — "VS"
│   └── TeamPanel (Panel) — 敌方队伍
│       ├── TeamTitle (Label) — "敌方队伍 (红方)"
│       ├── ActiveUnitsList (VBoxContainer) — 已上场单位
│       └── ReserveUnitsList (VBoxContainer) — 候补单位
├── HBoxContainer
│   ├── ResetButton (Button) — "重置编队"
│   └── StartBattleButton (Button) — "🎮 开始战斗"
└── EquipmentPopup (PopupPanel) — 装备选择弹窗（默认隐藏）
    ├── EquipmentList (VBoxContainer)
    ├── EquipButton (Button)
    └── UnequipButton (Button)
```

### 单位卡片组件（UnitCard）

创建独立的 `UnitCard` 场景（`res://scenes/components/unit_card.tscn`），包含：

```
UnitCard (Panel)
├── HBoxContainer
│   ├── SpritePlaceholder (ColorRect 或 TextureRect) — 角色图像占位
│   └── VBoxContainer
│       ├── NameLabel (Label) — "骑士 Lv.10"
│       ├── HBoxContainer
│       │   ├── HPBar (ProgressBar)
│       │   └── HPLabel (Label) — "HP:150"
│       ├── StatsGrid (GridContainer)
│       │   ├── ATKLabel, DEFLabel, MATKLabel, MDEFLabel, SPDLabel
│       │   └── APPLabel, PPLabel
│       └── ButtonsHBox
│           ├── EditEquipButton (Button) — "装备"
│           └── DeployButton (Button) — "下阵" / "上阵"
```

### 功能逻辑

**上阵/下阵：**
- 每个单位卡片的按钮文字根据位置变化（上场单位显示"下阵"，候补显示"上阵"）
- 每方上场人数限制：最少3人，最多5人
- 超出限制点击"上阵"时弹出提示

**装备编辑：**
- 点击"装备"按钮 → 显示 `EquipmentPopup`
- 弹窗显示当前单位的4个装备槽和可用装备列表
- 点击装备 → 装备到对应槽位，单位属性实时更新
- 点击卸下 → 移除装备，恢复基础属性

**开始战斗：**
- 验证双方人数一致（3v3/4v4/5v5）
- 不一致 → 弹出确认对话框："双方人数不一致（X vs Y），确定开始？"
- 数据存入 `BattleData` Autoload
- `get_tree().change_scene_to_file("res://scenes/battle_scene.tscn")`

### 预设数据（UnitDatabase）

至少提供 **10种** 不同职业的单位预设：

| ID | 名称 | 职业 | 等级 | HP | ATK | DEF | MATK | MDEF | SPD | AP | PP | 主动技能 | 被动技能 |
|----|------|------|------|----|-----|-----|------|------|-----|----|----|---------|---------|
| knight_blue | 亚瑟 | 骑士 | 10 | 150 | 35 | 25 | 10 | 15 | 20 | 3 | 2 | 重斩, 横扫 | 格挡 |
| mage_blue | 梅林 | 法师 | 10 | 100 | 8 | 10 | 42 | 30 | 18 | 3 | 2 | 火球术, 冰箭 | 魔法护盾 |
| archer_blue | 罗宾 | 弓手 | 10 | 120 | 30 | 15 | 10 | 12 | 25 | 3 | 2 | 精准射击, 毒箭 | 远程支援 |
| cleric_blue | 玛利亚 | 牧师 | 10 | 110 | 10 | 12 | 32 | 35 | 16 | 3 | 3 | 治疗, 群体治疗 | 净化 |
| thief_blue | 影 | 盗贼 | 10 | 100 | 28 | 8 | 5 | 8 | 35 | 3 | 3 | 暗杀, 偷取 | 闪避 |
| tank_blue | 铁壁 | 重甲 | 10 | 200 | 22 | 45 | 5 | 20 | 10 | 2 | 3 | 盾击 | 重装掩护 |
| soldier_blue | 兰斯 | 枪兵 | 10 | 140 | 30 | 20 | 8 | 12 | 22 | 3 | 2 | 穿刺, 列阵 | 援护 |
| knight_red | 暗黑骑士 | 暗骑 | 10 | 140 | 38 | 20 | 12 | 15 | 22 | 3 | 2 | 暗黑斩, 吸血 | 反击 |
| mage_red | 火焰魔导 | 法师 | 10 | 95 | 6 | 8 | 45 | 28 | 18 | 3 | 2 | 烈焰风暴, 灼烧 | 火焰护体 |
| archer_red | 暗影弓手 | 弓手 | 10 | 115 | 32 | 14 | 8 | 10 | 26 | 3 | 2 | 暗影箭, 麻醉箭 | 鹰眼 |

*（在代码中实现完整数据，至少包含上述10个单位 + 15个技能 + 10个装备）*

---

## 第三部分：场景二详细规格 — 战斗场景

### 场景文件
`res://scenes/battle_scene.tscn`

### 界面结构

```
BattleScene (Control)
├── BattlefieldContainer (HBoxContainer)
│   ├── BlueFormation (GridContainer 2×3) — 蓝方阵型（左）
│   │   ├── BlueUnit0..5 (CombatantNode 实例)
│   └── RedFormation (GridContainer 2×3) — 红方阵型（右）
│       ├── RedUnit0..5 (CombatantNode 实例)
├── BottomPanel (VBoxContainer)
│   ├── InfoBar (HBoxContainer)
│   │   ├── TurnLabel (Label) — "第 1 回合"
│   │   └── CurrentUnitLabel (Label) — "当前: 骑士"
│   ├── BattleLog (RichTextLabel) — 滚动战斗日志
│   ├── SpeedBar (HBoxContainer) — 行动顺序预览
│   │   ├── SpeedIcon0..N (TextureRect) — 单位头像按速度排列
│   └── ControlBar (HBoxContainer)
│       ├── APLabel (Label) — 当前选中单位的AP
│       ├── PPLabel (Label) — 当前选中单位的PP
│       ├── PauseButton (Button) — "暂停"
│       ├── SpeedButton (Button) — "加速"
│       └── ReturnButton (Button) — "返回"
└── ResultPopup (PopupPanel) — 战斗结果（默认隐藏）
    ├── ResultLabel (Label) — "胜利！" / "败北..."
    ├── StatsLabel (Label) — 战斗统计
    └── ConfirmButton (Button) — "返回编队"
```

### 战斗单位节点（CombatantNode）

创建 `res://scenes/components/combatant_node.tscn`：

```
CombatantNode (Control)
├── SpriteRect (TextureRect) — 角色图像
├── HPBar (ProgressBar) — 生命值条
├── HPLabel (Label) — "150/150"
├── StatusIcons (HBoxContainer) — 状态图标
│   ├── PoisonIcon, BurnIcon, FreezeIcon, StunIcon...
├── DamageNumber (Label) — 伤害数字（动画后隐藏，使用 Tween）
└── AnimationPlayer — 受击/死亡动画
```

### 战斗核心逻辑（在 BattleManager Autoload 中实现）

**回合流程：**
1. 从 `BattleData` 读取双方队伍数据
2. 初始化所有 CombatantNode
3. 触发所有"战斗开始时"被动技能
4. 进入主循环：
   - 按速度排序所有存活且AP>0的单位
   - 按顺序处理每个单位的回合
   - 遍历该单位的策略列表（Tactics）
   - 评估条件 → 选择目标 → 执行技能
   - 触发相关被动技能
   - 检查战斗结束条件
5. 显示结果弹窗

**条件评估器（ConditionEvaluator，纯代码类）：**

支持的评估函数：
```gdscript
# 目标条件评估
func evaluate(condition: Dictionary, caster: CombatantNode, all_allies: Array, all_enemies: Array, potential_targets: Array) -> Array:
    match condition.type:
        "hp_lowest": return sort_by_hp_asc(potential_targets)
        "hp_highest": return sort_by_hp_desc(potential_targets)
        "hp_below_50": return filter_hp_below(potential_targets, 50)
        "hp_below_25": return filter_hp_below(potential_targets, 25)
        "hp_full": return filter_hp_full(potential_targets)
        "def_lowest": return sort_by_def_asc(potential_targets)
        "infantry": return filter_by_tag(potential_targets, "infantry")
        "cavalry": return filter_by_tag(potential_targets, "cavalry")
        "flying": return filter_by_tag(potential_targets, "flying")
        "armored": return filter_by_tag(potential_targets, "armored")
        "scout": return filter_by_tag(potential_targets, "scout")
        "caster": return filter_by_tag(potential_targets, "caster")
        "healer": return filter_by_tag(potential_targets, "healer")
        "front_row": return filter_front_row(potential_targets)
        "back_row": return filter_back_row(potential_targets)
        "poisoned": return filter_status(potential_targets, "poison")
        "burning": return filter_status(potential_targets, "burn")
        "frozen": return filter_status(potential_targets, "freeze")
        "atk_highest": return sort_by_atk_desc(potential_targets)
        "speed_fastest": return sort_by_speed_desc(potential_targets)
        "evasion_lowest": return sort_by_evasion_asc(potential_targets)
```

**伤害计算器（DamageCalculator，纯代码类）：**
```gdscript
func calculate(caster: CombatantNode, target: CombatantNode, skill: Dictionary) -> Dictionary:
    var result = {"hit": false, "damage": 0, "crit": false, "guard": false, "killed": false}
    
    # 1. 命中判定
    var hit_chance = caster.hit - target.evasion
    if not target.has_tag("soldier") and skill.range == "melee":
        hit_chance -= target.evasion
    if skill.has("sure_hit"):
        hit_chance = 999
    if target.has_status("darkness"):
        return result  # 黑暗状态必定Miss
    
    var actual_hit_rate = hit_rate_table(hit_chance)
    if randf() * 100 > actual_hit_rate:
        return result
    
    result.hit = true
    
    # 2. 基础伤害
    var atk_stat = caster.atk if skill.damage_type == "physical" else caster.matk
    var damage = atk_stat * skill.power / 100.0
    
    # 3. 属性克制
    if is_class_counter(caster, target):
        damage *= 2.0
    
    # 4. 暴击判定
    if randf() * 100 < caster.crit_rate:
        result.crit = true
        damage *= 1.5
    
    # 5. 防御计算
    if skill.damage_type == "physical":
        damage -= target.def_
        # 格挡判定
        if randf() * 100 < target.guard_rate:
            result.guard = true
            damage *= (1.0 - target.guard_reduction)
    elif skill.damage_type == "magical":
        damage -= target.mdef
    
    damage = max(1, int(damage))
    result.damage = damage
    
    # 6. 应用伤害
    target.hp_current -= damage
    if target.hp_current <= 0:
        target.hp_current = 0
        result.killed = true
    
    return result
```

**策略与条件结构（每个单位的数据中包含）：**
```gdscript
# 单位.tactics 数组，按优先级排序
[
    {
        "priority": 1,
        "skill_id": "heavy_slash",
        "condition_1": {"type": "flying", "mode": "only"},    # "仅" — 飞行敌人
        "condition_2": {"type": "hp_lowest", "mode": "priority"} # "优先" — HP最低
    },
    {
        "priority": 2,
        "skill_id": "heavy_slash",
        "condition_1": {"type": "armored", "mode": "only"},
        "condition_2": null
    },
    {
        "priority": 3,
        "skill_id": "heavy_slash",
        "condition_1": {},  # 无条件 → 默认目标（前排→后排→就近）
        "condition_2": null
    }
]
```

### 战斗日志格式

```
[回合 1]
⚔ 骑士 使用「重斩」攻击 战士 → 命中！造成 42 伤害
🛡 战士 触发「格挡」！伤害减半 → 21 伤害
🔥 法师 使用「火球术」攻击 骑士 → 暴击！造成 85 伤害！
💚 牧师 使用「治疗」→ 骑士 恢复 35 HP
---
[回合 2]
...
---
⚡ 战斗结束！蓝方胜利！
  统计: 蓝方存活 3/4, 红方存活 0/4
  总伤害: 蓝方 458 | 红方 312
```

### 动画要求

使用 Tween 实现：
- 伤害数字：从单位位置向上飘出，1秒后淡出
- 受击抖动：单位左右抖动 0.1秒
- 技能特效：在施法者→目标之间播放简单的光效/粒子
- HP条：平滑过渡到新值
- 死亡：单位淡出 0.5秒
- 战斗日志：每条日志从下方滑入

### 控制功能

- **暂停/继续**：暂停回合自动推进（通过 `BattleManager.paused` 标志）
- **加速**：2倍/4倍速（减少 `Timer` 的等待间隔）
- **返回**：确认后返回队伍编辑场景

---

## 第四部分：必需的数据预设

### 技能数据库（至少15个技能）

| 技能ID | 名称 | 类型 | 消耗 | 威力 | 伤害类型 | 目标 | 特殊 |
|--------|------|------|------|------|---------|------|------|
| heavy_slash | 重斩 | active | 1AP | 150 | physical | single_enemy | - |
| wide_slash | 横扫 | active | 1AP | 120 | physical | row_enemy | - |
| poison_slash | 毒刃 | active | 1AP | 100 | physical | single_enemy | 附加中毒 |
| pierce | 穿刺 | active | 1AP | 150 | physical | column_enemy | 贯穿后排 |
| fireball | 火球术 | active | 1AP | 130 | magical | single_enemy | 附加灼烧 |
| icebolt | 冰箭 | active | 1AP | 110 | magical | single_enemy | 附加冰冻 |
| heal | 治疗 | active | 1AP | 120 | magical | single_ally | 恢复HP |
| group_heal | 群体治疗 | active | 2AP | 80 | magical | row_ally | 恢复一排HP |
| precise_shot | 精准射击 | active | 1AP | 120 | physical | single_enemy | 必中 |
| shadow_strike | 暗杀 | active | 1AP | 180 | physical | single_enemy | 对HP<50%目标+50威力 |
| guard | 格挡 | passive | 1PP | - | - | self | 受到物理伤害时触发格挡 |
| heavy_cover | 重装掩护 | passive | 1PP | - | - | single_ally | 代替队友承受伤害 |
| follow_slash | 追击 | passive | 1PP | 75 | physical | single_enemy | 友方被攻击时触发 |
| counter | 反击 | passive | 1PP | 120 | physical | attacker | 受到攻击时反击 |
| evade | 闪避 | passive | 1PP | - | - | self | 闪避一次攻击 |

### 装备数据库（至少10个装备）

| 装备ID | 名称 | 槽位 | 属性加成 | 附带技能 | 免疫 |
|--------|------|------|---------|---------|------|
| steel_sword | 钢剑 | weapon | atk+15 | - | - |
| magic_staff | 魔法杖 | weapon | matk+20 | - | - |
| iron_bow | 铁弓 | weapon | atk+12, hit+10 | - | - |
| great_shield | 大盾 | offhand | def+10, guard_rate+25 | - | - |
| dagger | 匕首 | offhand | atk+8, speed+5 | - | - |
| hp_pendant | 生命吊坠 | accessory | hp+30 | - | - |
| ap_ring | AP指环 | accessory | ap+1 | - | - |
| pp_ring | PP指环 | accessory | pp+1 | - | - |
| flame_sword | 火焰之剑 | weapon | atk+20, crit+5 | fire_slash | burn_immune |
| ice_amulet | 冰霜护符 | accessory | mdef+10 | ice_barrier | freeze_immune |

---

## 第五部分：实现优先级与步骤建议

### 阶段一：数据层（先做）
1. 创建 SkillDatabase、UnitDatabase、EquipmentDatabase 单例
2. 填充所有预设数据
3. 创建 BattleData 单例

### 阶段二：队伍编辑场景
1. 创建基础 UI 布局
2. 实现 UnitCard 组件
3. 实现上阵/下阵逻辑
4. 实现装备编辑弹窗
5. 实现开始战斗 → 场景切换

### 阶段三：战斗场景基础
1. 创建 CombatantNode 组件
2. 创建战斗场景基础布局
3. 实现 BattleManager 单例
4. 实现条件评估器 ConditionEvaluator
5. 实现伤害计算器 DamageCalculator

### 阶段四：战斗流程
1. 实现回合循环
2. 实现策略-条件-目标选择链路
3. 实现被动技能触发系统
4. 实现状态效果系统

### 阶段五：视听效果
1. 实现战斗日志
2. 实现伤害数字动画
3. 实现单位受击/死亡动画
4. 实现技能特效
5. 添加音效

### 阶段六：完善
1. 暂停/加速功能
2. 战斗结果界面
3. 边界情况处理
4. 调试和平衡

---

## 第六部分：重要注意事项

1. **所有素材使用占位符**：由于无法保证外部素材已下载，所有角色图像使用 ColorRect + Label 作为占位符，不同职业用不同颜色和首字符区分。实际素材路径按照 `02-assets-guide.md` 中的规范预留
2. **条件评估的双条件逻辑**：请严格按照设计文档第四章的"仅+优先"规则实现，这是整个系统的核心
3. **事件驱动架构**：使用信号解耦，BattleManager 发出信号，UI 监听更新
4. **战斗速度可调**：使用 `battle_speed: float = 1.0` 控制每个动作之间的等待时间
5. **错误处理**：确保在缺少数据、数组越界等情况下不会崩溃
6. **代码注释**：关键逻辑（特别是条件评估和伤害计算）使用中英文注释

---

## 验收标准

- [ ] 队伍编辑场景可正常添加/移除单位、编辑装备
- [ ] 双方人数3-5人范围内，点击"开始战斗"成功切换到战斗场景
- [ ] 战斗场景中双方单位正确显示，HP/AP/PP数值正确
- [ ] 回合按速度顺序自动推进
- [ ] 策略条件正确评估（至少测试"仅"和"优先"两种模式）
- [ ] 伤害计算公式正确（命中→暴击→格挡）
- [ ] 中毒/灼烧/冰冻/眩晕状态效果正常工作
- [ ] 战斗日志正确记录每次行动
- [ ] 战斗正常结束并显示结果
- [ ] 暂停/加速功能正常
- [ ] 返回编队按钮正常
- [ ] 无运行时错误

---

> **提示词版本**: v1.0 | **创建日期**: 2026-08-10 | **预计实现工作量**: 约1500-2500行 GDScript 代码
