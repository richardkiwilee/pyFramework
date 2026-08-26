# 地狱黑杰克 实施计划

> 规则与架构见 [00-design.md](00-design.md)。本文件是执行清单：分阶段、每阶段的文件与验证方式。

## 执行结果（2026-08-27，全部完成 ✅）

- 55 个单元/集成测试全绿（headless 退出码 0）：核心规则 31 + 牌背/牌面 12 + AI 10 + 本地整局 + ENet 回环整局。
- 窗口截图 + PIL 像素断言 13/13 通过（牌桌/牌背可见/放大镜/对照表/点击要牌出手牌）。
- 两个场景 headless 冒烟通过。临时驱动与 `_shots/` 已按约定删除。
- 实测新增环境坑已记入 memory（类型化数组构造、`match` 关键字、load 坏对象、TextureRect 尺寸等）。

## 阶段 0：项目骨架

- `project.godot`：主场景 `res://scenes/main_menu.tscn`、autoload `UITheme`、警告视为错误（`debug/gdscript/warnings/` 全开为 error，与 fullver-1 一致）。
- 移植 `fullver-1/scripts/autoload/ui_theme.gd` → `scripts/autoload/ui_theme.gd`（去掉 fullver-1 特有 faction/rarity 颜色，保留调色板/面板/按钮/label/center 工具）。
- 自写测试 runner `tests/test_runner.gd` + `tests/test_runner.tscn`（Node 根 + 脚本，扫描所在目录 `*.gd`，运行小写名含 `test` 的无参方法，失败 `push_error` 计数，结束 `quit(失败数)`）。
- **验证**：`--headless --import` + 跑空测试目录，退出码 0。

## 阶段 1：核心逻辑（纯 RefCounted，先测后写）

- `scripts/core/cards.gd`：`Suit`/`Rank` 枚举、`CardData`（suit/rank/面值/是否为 10 点牌）、`Hand`（加牌、软硬 A 最佳点数、is_bust、is_natural_blackjack、最大单张）。
- `scripts/core/deck.gd`：`Deck`（52 张构造、`shuffle(rng)` 种子可复现、`draw()`、弃牌堆、抽空自动洗回）。
- `scripts/core/round.gd`：`RoundEngine`——状态机（`WAITING/TURN/COMPARE/OVER`）、`hit/stand`、手牌上限 5、胜负判定（含爆牌/自然 BJ/同点比单张/push）、底池结算回调。
- `scripts/core/match.gd`：`MatchState`——筹码 100/底注 10/全押/先手随机轮换/筹码归零结束。
- `tests/unit/test_cards.gd`、`test_deck.gd`、`test_round.gd`。
- **验证**：headless 跑 runner，全绿。

## 阶段 2：牌背程序化绘制（本作精髓）

- `scripts/core/back_drawer.gd`：`class_name BackDrawer`
  - `draw_back(cv, suit, rank, rect)` 按编码规范绘制（上沿铆钉数=点数、中央徽章色调+符号=花色、四角花纹对称）；
  - `make_back_texture(suit, rank) -> ImageTexture`（缓存 52 张）；
  - `decode(suit, rank) -> 参数` 与绘制恒等（供测试与对照表）。
  - 花色符号：矢量绘制（心/桃/菱/梅，polygon+circle 组合）。
- `tests/unit/test_backs.gd`：52 种参数→解码恒等；渲染 52 张 `Image` 两两像素比较全不同。
- **验证**：headless 全绿 + 截图肉眼检查一张牌背。

## 阶段 3：UI 场景

- `scripts/ui/card_view.gd`：牌面绘制（角标点数+花色符号、中央大符号、红黑配色）+ 牌背（用 BackDrawer 纹理）；面朝上/面朝下两态。
- `scripts/ui/magnifier.gd`：悬停牌堆 → ×3 放大绘制顶牌牌背；新手模式附带解码文字。
- `scripts/ui/reference_sheet.gd`：F1 切换 52 张牌背对照覆盖层（地狱模式禁用）。
- `scripts/ui/table.gd`：牌桌组装——对手/玩家手牌扇面（参考 ai-discover 的 fanned arc）、牌堆、弃牌堆、底池、筹码、回合指示、要牌/停牌按钮（非己方回合禁用+失焦拦截层）、结算横幅、对局信息；输入走 `_unhandled_input` + 真实 `push_input` 可测路径。
- `scripts/ui/main_menu.gd` + 两个 `.tscn`。
- **验证**：`--quit-after` 冒烟；窗口截图 + PIL 断言（见阶段 6）。

## 阶段 4：AI

- `scripts/ai/ai_player.gd`：`class_name AIPlayer`，纯函数 `decide(state, difficulty) -> "hit"|"stand"`。
  - 简单：≤16 抽牌，不读背。
  - 困难：读顶牌（已知下一张）+ 记弃牌 + 对玩家明手评估（能安全追分才抽、领先即停）。
- `tests/unit/test_ai.gd`：构造场景断言决策。
- **验证**：headless 全绿。

## 阶段 5：联机（ENet）

- `scripts/net/net_game.gd`：`class_name NetGame`（Node）
  - 主机：`create_server(port, 1)`；客户端：`create_client(ip, port)`；
  - 主机权威跑 MatchState/RoundEngine；客户端发 `rpc_action("hit"/"stand")`；
  - 主机广播 `rpc_state(snapshot)` 全量快照（含顶牌 suit/rank 供渲染牌背）；断线判负。
  - 同进程回环可测（双 MultiplayerAPI 上下文，供测试复用）。
- `tests/unit/test_net.gd`：回环完整一局脚本化对战（主机代打双方动作 → 断言快照与结算一致）。
- 牌桌接线：菜单选择模式 → 进入 table；联机时输入走 NetGame。
- **验证**：headless 回环测试全绿；手动双实例冒烟（可选）。

## 阶段 6：截图 + PIL 验证

- 临时 TestDriver autoload（按 fullver-1 工作流）：种子牌堆进 table → 悬停牌堆 → F1 对照表 → 结算横幅，逐帧截图到 `_shots/`。
- `C:\Python314\python.exe` + PIL 断言：
  1. 牌堆顶牌背区域非背景色；
  2. 两张不同顶牌（种子不同）→ 牌堆区域像素不同（**牌背可区分**）；
  3. 放大镜区域出现且含放大内容；
  4. F1 对照表面板出现；
  5. 结算横幅出现。
- **收尾**：删除临时驱动与 `_shots/`；跑最终 headless 测试确认退出码 0。

## 关键风险与对策

| 风险 | 对策 |
|---|---|
| ENet 回环测试时序抖动 | 全部 `await` 连接信号 + 超时保护；断言以最终快照为准 |
| 警告视为错误导致解析失败 | 显式类型标注（`var x: int = ...`），沿用仓库既定编码习惯 |
| 花色符号绘制走样 | 截图肉眼检查 + PIL 只断言"不同牌背不同像素"（不咬死具体形状） |
| 中文渲染 | 复用 UITheme 的 SystemFont 微软雅黑链，不用 emoji |

## 验证总入口（每个阶段都跑）

```bash
GODOT="D:/Godot/Godot_v4.6.2-stable_win64_console.exe"
$GODOT --headless --path D:/pyFramework/black-joker --import
$GODOT --headless --path D:/pyFramework/black-joker res://tests/test_runner.tscn   # 退出码 0 = 通过
```
