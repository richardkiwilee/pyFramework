# 被动触发时点与策略表条件枚举

**被动触发时点**为枚举固定集(可扩展):`battle_start` / `battle_end` / `self_attack_start` / `self_attack_end` / `ally_attacked_start` / `ally_attacked_end` / `on_block` / `on_eva` / `after_phys` / `after_magic`。每个时点对被动技能的发动顺序按该时点下所有单位的速度值从高到低排序(速度可在战斗中被临时改变,故每次按当前速度现排)。**按时点各自计:每个时点独立最多 1 个单位响应**(一次攻击可在 `self_attack_start`/`on_block`/`after_phys` 等不同时点各触发一个被动),由 `ctx.trigger_fired_this_attack` 集合防同一时点重复触发。按速度逐单位检测,某单位有被动满足条件且 PP 足够即响应并结束该时点剩余单位检测;**判定满足时即扣 PP(响应前)**,PP 不足则该被动视为不满足(不扣 PP,继续下行)。

**触发时点放 effect dict**(非 skill 级):一个被动技能的多条 effect 可各设各的 `trigger_point`,在不同时点分别触发。`_trigger_point_of_passive` 取该技能首个带 `trigger_point` 的 passive effect 的时点作策略表被动行的时点标签。

**策略表条件**为枚举类型集(可扩展),分两型:**必要条件**(全部满足才能释放并筛选目标,如 `self_hp_le(50)`、`ally_avg_hp_le(75)`、`row_count_ge(row,n)`、`enemy_has_frozen`、`target_pref` 的 low_hp/front/random)与**优先条件**(满足则偏好在目标中选此类,不影响是否释放,如 `pref_enemy_frozen`、`pref_enemy_debuffed`)。`target_pref` 的 low_hp/front/random 各有对应的优先条件版本(必要版用于筛选目标是否合法,优先版用于在合法目标中排序偏好)。条件编码为结构化 dict(如 `{"type":"self_hp_le","threshold":50}`),不写字符串 DSL。单位策略表共至多 8 条,分上下两区(主动区 + 被动区),两区合计 ≤8、自由分配;主动行按行序从上到下在轮到本单位时检测,被动行在触发时点检测。

**Considered Options**:曾考虑把"优先条件"合并进必要条件(统一为一个条件对象带"是否硬性"开关)。但必要与优先的语义不同——必要是"是否释放 / 打谁的硬筛",优先是"在合法目标中偏好的软排";二者作用阶段不同(必要先过滤、优先后排序),混为一个对象会让"一条规则同时表达'必须冻结'和'偏好冻结'"退化为语义重复。故分两型、显式区分。被动响应"最多 1 单位"曾考虑允许多单位串联响应(如 A 掩护后 B 再追击),但"逐单位检测 + 命中即停"语义清晰、避免一次攻击触发链式被动导致结算爆炸;若未来需串联,以"响应后再触发新时点"的方式增量扩展而非本期内建。

"最多 1 单位响应"的粒度曾考虑"一次攻击合计最多 1 个被动"(跨时点合计)。但不同时点语义独立(如 `self_attack_start` 是攻击者出手前、`on_block` 是目标格挡成功时、`after_phys` 是受物理伤后),跨时点合并计数会让"格挡时触发霜守"与"受击后触发追击"互相挤占,语义混乱。故改为按时点各自计,由 `trigger_fired_this_attack` 集合按 `TriggerPoint` 去重。

**Consequences**:批次2(引擎层)已在 `pydemo/game/triggers.py` 落地 `TriggerPoint`(10 值)/`ConditionType`(必要+优先两型)/`STATUS_META`,条件求值函数 `eval_necessary`/`priority_key`;`pydemo/game/formation.py` 落地 8 槽两区 `UnitStrategy`/`StrategyRow`/`validate_strategy`/`default_strategy`/带槽位选目标 `choose_target_with_slots`(必要先过滤、池空回退可达性池不软锁、优先后稳定排序、无条件时退回旧 `target_pref` fallback);`pydemo/game/battle.py` 落地 `dispatch_trigger`(按时点各自计、速度降序、判满足即扣 PP)与 10 时点接入(`battle_start`/`battle_end` 一次性、`self_attack_*`/`ally_attacked_*` 在行动段 strike 前后、`on_block`/`on_eva`/`after_phys`/`after_magic` 在 `resolve_strike` 内)。向后兼容:无 `rows` 时 `choose_target_with_slots` 退回旧 `target_pref`,未接 `skill_defs` 的旧调用方仍工作。

**格挡/闪避掷骰**:为让 `on_block`/`on_eva` 时点能真正触发(凑齐 10 时点),批次2 在 `resolve_strike` 内落地命中/格挡/闪避/暴击掷骰(单一管道,普通攻击与 `ap_damage` 共用):命中后判 `rng.random() < eva/100` → 闪避(dmg 0 + 发 `on_eva`);否则判 `rng.random() < block/100` → 格挡(dmg ×`BLOCK_DMG_FACTOR` + 发 `on_block`);暴击 `rng.random() < crit/100` → dmg ×1.5。模块开关 `BLOCK_EVA_ENABLED`(默认 True)与常量 `BLOCK_DMG_FACTOR=0.5`:若 smoke_test 胜负翻转可一键关掷骰或调系数,不改代码。命中下限 dmg 1(非闪避)。
