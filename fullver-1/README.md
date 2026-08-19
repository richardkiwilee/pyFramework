# fullver-1 — 回合制策略游戏框架

将 demo-1（编队战斗）、demo-2（大地图移动）、diplomacy（外交）三个实验合并为一个可玩的垂直切片，跑在 zfoo/godot-framework（`zfoo/`）之上。

- **权威文档**：[docs/00-design.md](docs/00-design.md)（架构设计）、[CONTEXT.md](CONTEXT.md)（领域词汇表）、[docs/adr/](docs/adr/)（架构决策）、[readmd.md](readmd.md)（原始需求）
- **环境**：Godot 4.6.2（`D:\Godot\Godot_v4.6.2-stable_win64_console.exe`）、Python 3.14（`C:\Python314\python.exe`，验证用 PIL）

## 运行

编辑器打开 `project.godot` 运行主菜单；CLI 冒烟：

```bash
GODOT="D:/Godot/Godot_v4.6.2-stable_win64_console.exe"
$GODOT --headless --path D:/pyFramework/fullver-1 --quit-after 40 res://scenes/main_menu.tscn
```

## 测试（44 个用例，退出码 0 = 通过）

```bash
$GODOT --headless --path D:/pyFramework/fullver-1 --import          # 必须先导入（生成 class_name 缓存）
$GODOT --headless --path D:/pyFramework/fullver-1 res://tests/test_core.tscn
```

`test_core.tscn` 里的 UnitTest 会扫描 `tests/` 下全部测试脚本（7 个文件 44 个用例：数据/领域/回合与AI/大地图/外交/经济/战斗）。`tests/test_all.tscn`（IntegrationTest）可在编辑器内运行，但 CLI 下退出时框架有 SIGSEGV（zfoo 已知问题），自动化不要用它判断退出码。

## 架构一览

```
表现层 scenes/ + scripts/ui/    — 主菜单/大地图(+遮罩)/城市/编成/战斗，只做展示与输入
系统层 scripts/{world,battle,diplomacy,economy,ai}/  — 纯逻辑，可 headless 测试
领域层 scripts/core/            — GameState/Faction/City/Army/Team/Unit/Relation/Treaty
基础层 scripts/autoload/        — DataManager/GameManager/UITheme/I18n/ArtIndex + zfoo
数据   data/*.json              — 全部静态配置（demo-1 全量角色/职业/技能/装备/道具）
```

## 三个扩展点（readme 要求）

1. **AI 挂载**：写一个 `extends BaseAIStrategy` 的脚本，在 `data/factions.json` 给势力配 `"ai_strategy": "res://你的脚本"`。内置示例 `scripts/ai/strategies/basic_ai.gd`（注释即教程）。AI 只能通过 `AIContext.command()` 行动，全部经系统校验。
2. **数据驱动**：改 `data/*.json` 即改游戏内容；`DataManager.validate_all_data()` 启动时校验引用完整性与效果注册表覆盖（无静默丢失）。
3. **美术索引**：`data/art_index.json` 配 id → 纹理/emoji/颜色三级回退，`ArtIndex.get_icon(id)` 永不返回 null；美术缺失自动用占位符。

## 战斗系统

demo-1 引擎完整移植 + 改造（见 [ADR-0001](docs/adr/0001-battle-precompute-playback.md)）：先算后播、9v9、编队槽位显式映射战斗站位、被动时点体系（20+1 个效果，补 heal_on_kill）、状态效果（毒/烧/晕/冻）、掩护/闪避/格挡/反击/追击。全部 222 技能数据可用；未实现的稀有效果在启动时显式告警（绝不静默）。
