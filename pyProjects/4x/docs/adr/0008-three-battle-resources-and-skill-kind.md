# 三战斗资源与技能 kind 三分类

战斗资源由两项(HP/Mana)扩为三项:**HP**(跨场累积)、**AP**(主动技能资源,每场开打回满)、**PP**(被动技能资源,新增,每场开打回满)、**Mana**(高级资源,跨场累积不回满、仅按月相在战间恢复、进场只 clamp 到当前有效上限)。技能按 `kind` 三分类:`active`(主动,耗 AP,排在策略表主动区、轮到本单位时从上到下检测)、`passive`(被动,耗 PP,在触发时点检测)、`perk`(免费常驻,走修正管道,不占策略表 8 槽)。技能来源二分:**习得**(写死在单位定义)与**装备赋予**(经装备 `skill_grant` 效果装上时加入、卸下时移除)。

**Considered Options**:曾只有 HP/AP/Mana 两资源 + 主动/被动两分类。把被动也耗 AP 会与主动抢同一种资源、无法表达"被动是独立预算"的意图;把被动走 perk 修正管道则无法表达"按触发时点有条件释放、消耗点数、每攻击最多 1 单位响应"这种离散事件语义——perk 是无条件的连续数值修正,passive 是有条件的离散点数释放。故被动单列、配独立资源 PP。Mana 起初设计为"进场回满",改为跨场 clamp + 月相恢复,以承载"高级技能需跨场攒资源"的成长线;AP 明确不决定技能属性(物理/魔法),物理/魔法由技能效果参数本身决定(如"冰封"是魔法系普通技能、耗 AP)。

**Consequences**:AP/PP 每场回满 → 战斗开始即置为有效上限,无跨场延续;Mana 不回满 → 战斗进场只 clamp 不补满,跨场守恒。`kind=perk` 的技能数据与事件源 Perk 是两条独立来源,但都走修正管道(`collect_passive_modifiers`),二者不互斥也不混用槽位。装备赋予技能需 `Unit` 临时字段(`granted_skills`),装/卸时如 `_recompute_unit_tags` 逐地重算。`skill_kind()` 缺省返回 `SKILL_PERK`,以向后兼容无 `kind` 字段的旧技能数据。

批次2(引擎层)已接通执行:`run_battle` 进场把 `cur_ap`/`cur_pp` 置为有效上限、`cur_mana` 仅 clamp 不回满;行动段按策略表主动区行序检测主动技能,首个 `_can_fire_active`(AP+Mana 足、无目标型必要条件满足)的主动技能执行 `execute_active_effect`(`ap_damage` 走 `resolve_strike` 统一管道、`apply_status` 施加状态)并扣 AP/Mana,都不满足则普通攻击;被动时点 `dispatch_trigger` 判满足即扣 PP(响应前)。**RNG 注入**:`run_battle(..., rng: random.Random | None, skill_defs)` 接收注入随机数,脱离全局 `random.seed`,便于测试定种子;`game._do_battle` 传 `rng=random.Random()` 与 `skill_defs=self.defs.get("skills", {})`。
