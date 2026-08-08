# 装备按 def_id 库存计数

Status: accepted, supersedes ADR-0007.

装备存储从"逐件实例(`ArtifactInstance` + `Game._artifact_index` id→实例映射 + 200 件上限 + 5 回合卸下冷却)"改为"按装备定义 `def_id` 以库存计数存储"。`Faction.inventory` 是 `dict[def_id → 库存数]`;`Unit.artifacts` 存 `def_id` 列表(最多 4 槽 0..3)。已装备数量从所有己方单位的 `artifacts` 反查(`库存数 - 该 def_id 在己方单位 artifacts 中出现次数 = 实际在库可装数`)。装备=库存 −1、卸下=库存 +1、卖出=按 def_id 卖 1 件库存(固定 +10 金币)。**移除 200 件上限与 5 回合不可用冷却**,代之以**位置限制**:装/卸仅当目标单位所在部队位于己方据点内才允许(待命单位无部队、视为安全,可编辑);野外部队无法穿戴/卸下。单位死亡/解散时其装备全部回库(死亡无位置惩罚)。

**Considered Options**:ADR-0007 的实例模型把每件作为独立对象以承载件级状态(装备/在库可用/在库冷却)。原型推进中发现件级状态里只有"在库不可用冷却"依赖实例,而该冷却的真实动机是"野外卸下有代价";改为位置限制后冷却失去存在理由,件级状态全部坍缩为"装在某单位上 / 在库"两种——二者都可由 def_id 计数 + 单位 artifacts 反查干净表达,实例层成为纯开销(`_artifact_index` 映射 + 200 件遍历 + 卸下冷却 tick)。故废弃实例模型。代价:无法表达"同名两件、一件在库冷却一件被装备"——但冷却已移除,该状态不再存在。

**Consequences**:`game.py` 删除 `make_artifact_instance`/`_artifact_index`/`_unequip_instance`/`_tick_inventory`(冷却);`grant_tags_from_artifacts` 与 `collect_unit_mods` 不再经实例映射,直接按 `Unit.artifacts` 中的 `def_id` 查 `artifact_defs`;`_recompute_unit_tags` 同理重算。仓库界面(`inventory.py`)从"按件列表(最多 200 行)"改为"按 def_id 行(每行:定义名 + 库存数 + 已装备数 + 归属列表)"。`scenario.py` 装备发放从"每定义造 3 件实例"改为"`inventory[def_id] += 3`"。AI 仍不使用装备(本期不动)。
