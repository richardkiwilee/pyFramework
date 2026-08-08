# 单位状态系统

引入离散的单位状态(Status),与连续数值的修正管道分离。状态类型为枚举集(如冻结/冰封/减益等,带分类标签与默认层数),`Unit.statuses` 存当前状态及其**剩余层数**(int,非剩余回合)。状态采用**消费模型**(无 tick 计时):按消费方式耗层,层数归 0 即解除;`battle_end` 清场(状态不跨场,与 HP 跨场不同)。状态是技能效果(如"冰封"对敌方施加冻结)与策略表条件(如"优先处于冻结状态的敌方")的输入。

**消费方式三型**(定义在 `triggers.STATUS_META`):`BATTLE_LONG`(整场持续到 `battle_end` 清除,不消耗层数,如减益 DEBUFF)、`ON_SELF_ATTACK`(轮到该单位行动、执行一次攻击后层数 −1,如冻结 FROZEN)、`ON_SELF_HIT`(该单位被攻击命中后层数 −1,受击破冰)。**重施加取 `max(当前, 新层)`,不叠加**(防止反复施加无限堆层)。冻结归 `ON_SELF_ATTACK`:轮到自身行动时跳过出手并扣 1 层(层数归 0 即解除,下回合可行动);被敌方命中时也扣 1 层(受击破冰,`ON_SELF_HIT` 分支,本期冻结示例不采用此分支但管道已留)。

**Considered Options**:曾考虑把状态塞进修正管道(如 `frozen` 当作一个 `pct_attr speed -100%` 的修正项)。但状态是**离散标签 + 解除条件**(冻结=不能行动且到时解除、减益=分类可被"优先处于减益状态的敌方"匹配),不是连续数值增减;混进修正管道后无法表达"是否处于冻结"这种布尔判定,也无法承载堆叠与分类标签。故状态单列为独立系统,与修正管道正交:修正是连续数值增减(走 `compute_attribute`),状态是离散标签 + 消费耗层(走 `Unit.statuses` + `triggers` 模块)。代价:效果解释器需在施加/消费/清场三处处理状态,而非全部经修正管道统一。

曾考虑按 tick 倒计时模型(每回合/每时点状态剩余回合 −1)。但 tick 模型与"冻结在轮到自身行动时解除"的语义耦合差——冻结的解除条件是"该单位行动一次"而非"过 N 回合",且 tick 推进时机散落在循环各处易误序。故改为消费模型:状态解除绑定到明确的事件(自身攻击/自身受击/战斗结束),由 `consume_on_self_attack`/`consume_on_self_hit`/`clear_statuses` 三处显式调用,语义集中、可测。

**Consequences**:批次2(引擎层)已在 `pydemo/game/triggers.py` 落地状态枚举(`StatusType`/`StatusConsume`)、`STATUS_META`、施加/消费/清场函数,并在 `battle.py` 引擎接入:`run_battle` 进场 `clear_statuses`、行动段冻结跳过 + `consume_on_self_attack`、`resolve_strike` 命中分支 `consume_on_self_hit`、`battle_end` 后清场所有单位。条件枚举 `enemy_has_frozen`/`pref_enemy_frozen`/`pref_enemy_debuffed` 读 `Unit.statuses` 做布尔判定/排序(见 ADR-0011)。状态枚举类型集可随技能需要扩展(同触发时点枚举)。
