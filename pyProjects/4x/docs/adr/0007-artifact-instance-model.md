# 装备实例模型（Artifact Instance）

Status: superseded by ADR-0009.

装备从"按装备定义 id 装备"改为"按实例装备":每个阵营持有一个仓库（Inventory）列表,上限 200 件,每件是一个独立的 `ArtifactInstance`(有 `def_id` / `state` / `cooldown` / `equipped_by`)。`Unit.artifacts` 存实例 id（非 def_id）。实例状态:已装备（equipped_by 非 None,左侧列表名字前加 E）、在库可用（可装备/可卖出）、在库不可用（从不在据点的单位上卸下后冷却 5 回合）。

旧设计把 `Unit.artifacts` 当作 def_id 列表、装备即"把某定义挂在某槽",不维护库存与多件同名装备的独立状态。引入仓库界面与卖出/卸下/冷却语义后,这层抽象不够:同名装备可有多件、各件状态不同（一件在被某单位装备、另一件在库冷却中）、卸下后需按单位位置决定冷却——这些都要求"件级"状态。考虑过在 def 上加计数与状态聚合（如 def→{可用数, 冷却数, 装备数}）,其代价是卸下/卖出时要改多个计数、冷却到期要逐件还原、且无法表达"某件具体装在哪个单位上"——冷却规则依赖单位位置,聚合模型无法干净承载。实例模型把每件作为独立对象,卸下/卖出/冷却/死亡回收都退化为对该实例的单点改写,warehouse 界面也天然按件列出。代价:200 件实例对象的内存与遍历开销,以及 `_artifact_index` 这层 id→实例映射——原型规模下可忽略。

连带影响:`grant_tags_from_artifacts` 与 `collect_unit_mods` 经 `Game._artifact_index` 解析实例→def_id 再取 effects;`_recompute_unit_tags` 在装备/卸下后重算单位 tags = 本体 tag ∪ 装备赋予的 tag。单位死亡/解散（首都陷落、部队全灭）经 `_release_artifacts` 把其装备全部回库·可用（死亡无位置惩罚）。回合开始 `_tick_inventory` 推进不可用装备冷却,到 0 转可用,与 `_tick_standby` 同理。卖出固定 +10 金币（artifacts.json 无 cost/value 字段,原型固定值）。
