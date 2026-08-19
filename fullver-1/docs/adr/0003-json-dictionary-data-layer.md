# 数据层用 JSON + Dictionary + DataManager，不用 zfoo JsonUtils 反射对象映射

所有静态游戏数据放 `data/*.json`，由 `DataManager` autoload 启动时加载为 Dictionary 缓存并建反向索引，查询走 `get(key, default)` 防御式访问（demo-1 已验证的模式）。**不用**框架提供的 `JsonUtils.json_to_object` 反射到强类型对象。

**为什么**：①反射映射要求 JSON key 与 GDScript 类字段名一一对应——字段改名会**静默丢数据**，GDScript 反射脆弱，且类型化数组遇到 JSON null 易炸；②Dictionary 与 Python 的 dict 心智模型一致（本项目主要维护者精通 Python），`.get(id, {})` 防御式访问在 demo-1 经过实战验证；③数据校验由专门的数据校验测试承担（启动时全表扫描 + 引用完整性检查），弥补无编译期字段校验的损失。

**代价**：无类型提示与字段拼写保护。缓解手段：所有数据访问集中在 DataManager 的具名 getter（`get_character(id)`），业务代码不直接碰裸字典。
