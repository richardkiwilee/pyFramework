# PyConsole Framework — 实施计划 (PLAN)

> **状态**：阶段 0–7 已完成并测试通过（149 个 unittest 全绿）。阶段 5 + 7.7 实跑待用户在交互终端验证。
> 本文件既是原始自底向上施工顺序，也是后续迭代的索引——**阶段 6+ 记录已完成的功能演进**（按时间追加），方便回溯每项改动落在了哪里。

执行顺序自底向上：io → core → data → scenes → main → tests → docs → 验证。
每步可独立运行/验证，避免大爆炸式集成。

---

## 阶段 0：骨架与 io 层

**0.1 目录与包**
- 创建 `pyconsole/` 及子包 `io/ core/ scenes/ data/ tests/`，各加 `__init__.py`。
- 创建 `main.py`、`README.md`、`requirements.txt`（空）、`DESIGN.md`、`PLAN.md`。

**0.2 `io/width.py`**
- `char_width(ch) -> int`（2/1/0）。
- `text_width(s) -> int`。
- 单测 `test_width.py` 覆盖：中文=2、ASCII=1、半角片名=2、控制符=0、混合累加。

**0.3 `io/theme.py`**
- 256 色常量：`BG, FG, DIM, ACCENT, ACCENT2, SELECTED_FG, SELECTED_BG, BORDER, HIGHLIGHT, HEADING, OVERLAY_BG` 等。
- 定义颜色对 `Color(fg, bg)` dataclass。

**0.4 `io/buffer.py`**
- `Cell(char='\0', fg=FG, bg=BG)`，`__eq__` 比较三字段（diff 用）。
- `FrameBuffer(w, h)`：`cells: list[list[Cell]]`。
  - `clear(ch=' ', fg=FG, bg=BG)`
  - `set_char(x, y, ch, fg, bg)`
  - `put_text(x, y, text, fg, bg)`：按 `char_width` 写入，双宽补占位，越界截断，返回结束 x。
  - `fill_rect(x, y, w, h, ch, fg, bg)`
- 单测 `test_buffer.py`：put_text 双宽、越界、占位。

**0.5 `io/display.py`**
- `Display(w, h)`：`enable_vt()`（ctypes SetConsoleMode，失败 fallback）、`stdout.reconfigure(utf-8)`。
- `hide_cursor/show_cursor`。
- `begin_frame()`：调 `buf.clear()`。
- `present(front) -> front'`：首帧/尺寸变化整屏（`ESC[H` + 全部）；否则单元格 diff（`ESC[y;xH` + SGR + char）；一次 write+flush。
- `cleanup()`：show_cursor + reset color。
- 颜色 → SGR：256 色用 `38;5;N` / `48;5;N`。

**0.6 `io/input.py`**
- `read_key() -> (key_name, char)`：msvcrt.getch，处理 `0xe0/0x00` 前缀 + 方向码（H/P/K/M）、功能键（PgUp=`I`、PgDn=`Q` in 0xe0 seq）、空格、回车（`\r`）、Esc（`\x1b`）、Backspace（`\x08`）、可打印 ASCII。
- `poll_tab_held() -> bool`：ctypes GetAsyncKeyState(0x09) 最高位。
- 不直接产 Action（留给 keys/KeyResolver）。

---

## 阶段 1：core 层

**1.1 `core/actions.py`**
- `Action`（str 枚举或 Enum）：UP/DOWN/LEFT/RIGHT/SELECT/CONFIRM/BACK/OPEN_WIKI/SCROLL_UP/SCROLL_DOWN/CHAR。
- `CHAR` 携带 `.char` 属性（用 dataclass 或 (Action.CHAR, ch) 元组）。

**1.2 `core/keys.py`**
- `DEFAULT_BINDINGS: dict[str, Action]`（key_name → Action）。
- `load_bindings(path) -> dict`：json 覆盖默认，缺失/损坏返回默认。
- `KeyResolver(bindings)`：`(key_name, char) -> Action | None`；可打印且未绑定到其他 Action 的键 → CHAR。
- 单测 `test_keys.py`：默认、覆盖、缺失、未知键。

**1.3 `core/scene.py`**
- `SceneResult`：dataclass，`kind` in {PUSH, POP, QUIT, NONE} + `scene`/`params`/`return_value`。
- `Scene` 基类：`allow_status_overlay=False`、`on_enter/on_exit/handle_action/render/get_hints`。
- `SceneStack`：`push/pop/top/__len__`；push 调 on_enter，pop 调 on_exit。

**1.4 `core/game_state.py`**
- `GameState` 示例：name/level/hp/max_hp/mp/max_mp/gold/location/inventory_count/quest_progress。
- `render_status(buf, rect, state)`：画 HP/MP 条等。

**1.5 `core/overlay.py`**
- `StatusOverlay`：`render(buf, w, h, scene_name, stack_depth, state, bindings_count)`。
- 居中面板，上半状态、下半调试，box-drawing 边框 + OVERLAY_BG。

**1.6 `core/app.py`**
- `App`：持有 display/buffer/input/resolver/stack/overlay/state/running。
- 主循环（见 DESIGN §6.3）。
- `handle_action(result)`：PUSH/POP/QUIT 分发。
- 底部 hints 统一绘制。

---

## 阶段 2：data 层

**2.1 `data/wiki.json`**
- 约 30 条奇幻 RPG 条目：武器 6、防具 5、消耗品 6、怪物 6、技能 7。
- 每条：id/name/category/summary/detail/attrs。
- 用 Python 脚本生成或手写 JSON。

**2.2 `data/wiki_data.py`**
- `WikiEntry` dataclass。
- `load_entries(path)`：读 json，文件缺失返回 []。
- `search(entries, query) -> list[SearchHit]`：子串包含（lower）、匹配 name+summary+category、按 name 排序、记录命中字段与位置（供高亮）。
- `find_match_ranges(text, query_lower) -> list[(start,end)]`：高亮辅助。
- 单测 `test_search.py`：命中、大小写、多字段、排序、空、无结果、命中位置。

---

## 阶段 3：scenes 层

**3.1 `scenes/main_menu.py`**
- `MainMenuScene`：标题 ASCII、3 菜单项、focus/selected 集合、hints。
- handle_action：UP/DOWN 移焦点、SELECT 切选中、CONFIRM 执行（PUSH Message / PUSH Wiki / QUIT）、OPEN_WIKI PUSH Wiki、BACK 忽略。
- render：标题居中、菜单带 `[x]/[ ]` 与 `>` 焦点标记、底部 hints。

**3.2 `scenes/wiki.py`**
- `WikiScene`：query/cursor/entries/results/selected_index/scroll_offset/detail_scroll。
- on_enter：加载 entries。
- handle_action：CHAR 追加、BACKSPACE 删、UP/DOWN 切条目（含滚动）、SCROLL_UP/DOWN 滚详情、BACK POP。
- 每次输入 → `search()` → reset selected=0、detail_scroll=0。
- render：标题、输入框、左列表（名称+[分类]、命中高亮、滚动窗口）、右详情（全字段、命中高亮、滚动窗口、空状态提示）、底部 hints。
- `allow_status_overlay=False`。

**3.3 `scenes/message.py`**
- `MessageScene(text)`：居中显示文本，按任意键 POP。

**3.4 `scenes/game21.py`**（21 点人机对战，见 DESIGN §8）
- 状态机阶段：menu / holding / discard / sleeve_select / slot_select / ai_turn / settled。
- `Side`：5 固定卡槽 `slots: list[Card|None]`（`table` 只读派生视图）、袖子（≤2）、passed、busted。
- 规则：抽牌锁定（`_drawn_this_turn` 阻断 pass/出袖子，唯打出结束）、占用槽放置失败重选、袖子满手动弃。
- tick 钩子 + 时间队列驱动 AI 延迟动画；AI 遵循与玩家相同约束。
- `render_overlay` 自绘 Tab 牌堆总览（左上隐写卡背 + 4×13 归属网格）。

**3.5 `game/card_back.py`**
- 隐写卡背：`embed_stealth`/`decode_card_back` 可逆、`draw_card_back_buf` 渲染进 FrameBuffer。
- `SUIT_TO_CODE` 显式映射（`card_back.SUITS` 与 `cards.SUITS` 花色顺序不同，禁用下标互转）。

---

## 阶段 4：入口与收尾

**4.1 `main.py`**
- `enable_vt` → `hide_cursor` → `App().run()`，try/except KeyboardInterrupt，finally `cleanup`。

**4.2 `README.md`**
- 运行方式、架构图（DESIGN §3）、如何加新场景/新键/新百科条目、键绑定 json 说明、限制说明。

**4.3 `requirements.txt`**：空文件 + 注释"零依赖，仅标准库"。

---

## 阶段 5：验证

- `python -m unittest discover -s pyconsole/tests -v` 全绿（当前 105 个用例）。
- `python main.py` 实跑：主菜单、H 进百科、输入实时搜索、↑↓ 切详情、PgUp/PgDn 滚详情、Esc 退、按住 Tab 看状态总览、Esc/正常退出无残留。
- 21 点实跑：抽牌→holding→打出选卡槽（金色/红色焦点）→藏入袖子→袖子满手动弃→AI 延迟动画→结算面板。
- （实跑需真实终端交互，main 跑起来会阻塞，验证以 unittest + 静态走查为主，必要时后台启动数秒后 kill 观察无崩溃。）

---

## 阶段 6：功能演进记录（按时间追加）

> 初始 5 阶段之外的功能改动追加于此，每条标注落点文件与测试，便于回溯。

**6.1 Tab 行为分区化 + 牌堆总览 + 隐写卡背**
- `main_menu.py`：`allow_status_overlay=False`（主菜单 Tab 完全无效）；移除 Tab 相关提示文本。
- `scene.py`：新增 `render_overlay(buf, w, h) -> bool` 钩子；`app.py` 渲染时先调栈顶 `render_overlay`，返回 True 跳过通用面板。
- `game/card_back.py`（新增）：从 `stealth_marked_card_back.py` 移植隐写逻辑，`SUIT_TO_CODE` 显式映射花色。
- `game21.py`：`render_overlay` 自绘——左上角抽牌堆顶隐写卡背、右上编码说明+图例、下方 4×13 网格按归属着色。
- `stealth_marked_card_back.py`：瘦身为从包内导入，`__main__` 加 UTF-8 stdout 重配。
- 测试：`test_card_back.py`（新增 52 张往返）、`test_render_smoke.py` 新增 overlay 渲染/隐写解码/位置追踪/空牌堆/Tab 开关。

**6.2 21 点规则改造：5 卡槽 / 手动选槽 / 袖子满手动弃 / 抽牌锁定**
- `game21.py`：
  - `Side.slots` 改为 5 个固定卡槽，`table` 变只读派生视图；新增 `first_free_slot()`。
  - 新阶段 `slot_select`（←→ 切焦点、1-5 直选、回车确认；占用槽放置失败停留重选）、`discard`（袖子满手动选弃）。
  - `_drawn_this_turn` 锁定：抽过牌后 pass/出袖子被禁，唯打出结束；藏牌不结束回合。
  - 焦点颜色：金色=空槽可放、红色=占用（放置会失败）；非选择阶段不高亮。
  - AI 重写遵循相同约束（抽后必打、会爆优先藏、袖子满弃最小点数、桌满强制 pass）。
- `test_render_smoke.py`：旧 `table=` 赋值改 `slots[i]=`；新增 8 个用例（5 槽默认空、table 只读、抽牌锁定、抽→藏→抽→打、占用槽失败重选、←→ 循环、袖子满手动弃、袖子牌进卡槽）。
- 文档：`DESIGN.md` §7/§8/§10/§12/§13 与 `README.md` 规则/视觉/键位同步更新。

> **阶段 7 取代 6.2 的部分规则**：抽牌锁定语义、爆牌当场结算、pass 永久停已被 §7 重写。
> 6.2 的「占用即失败」被 §7 栈模型「栈顶非空壳才不可放」取代；`first_free_slot` 改为 `first_playable_slot`（含空壳判定）。

---

## 阶段 7：经济 + 效果 + 多轮系统（grilling 决议落地）✅ 已完成

> 文档先行（DESIGN.md §8/§14/§15/§16/§17 + 本节 + README）原为施工契约；现代码已落地并复核，149 个单测全绿。
> 代码自底向上分 7 步，每步可独立单测。下述各步已全部完成，并标注与施工契约的差异点。

### 7.1 数据契约层（`game/cards.py` + `game/effects.py` + `game/deck_defs/`）✅
- `Card`：加 `tag`、`points: tuple[int,...]`（多值）、`on_play/on_activate/on_end: Effect|None`；`rank` 改可选。保持 frozen dataclass。`make_standard_card(rank, suit)` 工厂替代旧位置构造。
- `Suit(symbol, name, cards, archetype)`、`DeckDef(suits).sample_for(n_players, rng)`：抽 N 套合并成单一共享牌组。
- `hand_score` 泛化：枚举每张牌 `points` 候选笛卡尔积，≤21 取最大，否则取最小并标 busted。
- `Effect(kind, level, params)` / `SlotEffect(kind, cost, params)` + `EFFECT_REGISTRY` 注册表执行器（签名含 scene/actor_idx/slot_idx/card/effect）。
- `game/deck_defs/`：`base.py`、`exploit.py`（2/3/4/5 on_play=剥削1）、`broken.py`（6/7/8/9 on_end=损坏）。每文件导出一个 `Suit`。`__init__.py` 汇总 `DECK_DEF`。
- `effects.py` 另增 `slot_is_open`（与具体牌无关的「还能否放牌」，双重检查自动 pass 与 AI 选槽用）与 `_reset_registry_for_tests` 测试钩子。
- 测试：`test_cards.py`（31）、`test_effects.py`（17）全绿。

### 7.2 经济与多轮（`game21.py`）✅
- `self.players: list[Side]`（`[human, ai]`，`player`/`ai` 为只读属性别名）、`self.pool: int`、`self.round_num: int`、`self.current: int`（当前玩家索引）、`self.deck: list[Card]`、`self.discard: list[Card]`（弃牌堆）。
- `Side` 加 `gold: int`（软上限 20，可超）、`passed: bool`（软 pass）、`pass_score: int|None`（取消比对基准）。
- 经济方法：`_pay(who, amt)->int`（不足全交）、`_settle_pool(winners)`（平分向下取整余数丢弃）、`_clamp_gold()`（轮末 >20 丢弃）。底注在 `_begin_round` 内直接 `_pay`（`ante = round_num * 2`），未单独建 `_ante()`。
- 抽牌堆抽空 → 洗弃牌堆为新抽牌堆；袖子牌不进弃牌堆（`_draw_from_deck` 改写）。**R2 兜底已落地**：抽牌堆与弃牌堆双空时重建共享牌组保证不卡死。
- 轮末事件顺序 `_round_end`（§14.3，不可变）：21 结算 → 终局效果（按卡槽号横向触发，损坏移除）→ 分池 → 轮末整理（桌面→弃牌堆，清槽/重置 passed）→ 丢弃超额 → 0 检查（→ 游戏结束 / 进下一轮交底注）。
- 先手每轮随机（`_rng.random() < 0.5`）。

### 7.3 回合模型重写（`game21.py`）✅
- `Side.slots` 升级为 `list[Slot]`；`Slot.cards: list[Card]` + `slot_effect: SlotEffect|None`。`Side.table` 改为扁平所有牌。`first_playable_slot`（空槽/栈顶空壳/空壳效果槽，用 `slot_is_open`）、`is_table_full`（用 `slot_is_occupied`）。
- 软 pass：出牌/pass 二选一、抽牌与 pass 互斥（抽了必打）、藏牌不结束 turn、出牌自动结束 turn。
- pass 取消：`_after_effect_cancel_pass` 在每次效果结算后扫描所有 passed 玩家，`score()[0] != pass_score` → 自动 `passed=False`；不插队，等当前行动方结束。
- 结算触发 = 所有人 pass，仅在 `_end_turn` 入口检查一次。
- 双重检查自动 pass：抽牌前 + 回合开始时，无可用槽且非 pass → 自动 pass。
- 单人开局第4、5槽随机分配卡槽效果。**实现现状**：`_random_slot_effect()` v1 返回 None（无效果表），等效果表来逐条注册。

### 7.4 效果执行（`game21.py` + `game/effects.py`）✅
- 放牌时序 `_try_place`（§16.4）：选槽→校验可放→付卡槽费用→消耗来源牌→入栈→卡槽效果→打出效果（+软 pass 取消扫描）→重算点数（不立即结算，仅记日志）→激活询问（强制牌直接激活 / 爆牌跳过 / 玩家进 activate_prompt Y/N / AI 走 _ai_resolve_activate）→结束 turn。
- 已知三效果执行器（`_register_known_effects` 注册，幂等）：剥削（on_play）、损坏（on_end，记日志；移除由 `_trigger_on_end` 收集）、空壳（无操作）。
- `activate_prompt` 阶段：Y/N，回车=激活，Esc=不激活，免费，强制牌必须激活。
- 终局按卡槽号横向触发（`_trigger_on_end`：卡槽1全员→…→卡槽5，多牌按叠放顺序），损坏牌收集后统一从牌池移除。

### 7.5 渲染（`game21.py`）✅
- `CARD_W=8`（容纳 `1|11` 多值标签+卡槽效果缩写）。多值牌牌面显示 `tag`。
- 顶部状态栏：标题含 `第N轮`，AI 区标签补 AI 金币/点数/爆牌/停牌，右侧补 `牌堆/弃牌/公共池` 计数。
- 槽下标卡槽效果+费用（金色，空槽显 `[n]`）；空壳叠放显示栈顶牌 + `×N` 计数。
- 卡槽焦点颜色：金色=空槽/空壳顶可放，红色=栈顶非空壳不可放。
- `round_settled` 结算面板补双方点数/金币明细 + 胜负；`game_over` 面板按最终金币判胜负。
- Tab overlay：本局牌组构成网格按 `DECK_DEF.suits` 顺序排成行（实际套牌数）、rank 排成列，位置含弃牌堆/已出；隐写卡背保持。

### 7.6 AI（`game21.py`）✅
- 点数层（≥17 倾向 pass 85% / ≤11 必抽 / 12-16 概率，玩家已停且更高时被迫追）+ 经济层（`_ai_find_affordable_slot` 换可放且付得起槽、藏牌 gold<2 不藏）+ 软 pass 重决策 + 激活选择。
- 效果按 `kind` 硬编码启发式（每机制一函数，参数化 level 与选择对象）。**v1 尚无已知 on_activate 执行器，`_ai_resolve_activate` 默认不激活（保守），强制牌已在放牌时序直接激活。**
- 多轮意识（`gold ≤ 2 且 score < 12` 无望 pass 省金）。
- AI 走与玩家相同的放牌时序（`_ai_try_place`），但不进 slot_select/activate_prompt 阶段。

### 7.7 验证 ✅
- `python -m unittest discover -s pyconsole/tests` 全绿，**149 个用例**（cards 31 + effects 17 + card_back 9 + render_smoke 45 + 其余 47）。
- 种子模拟：25/25（玩家先手）+ 40/40（AI 先手）均到达 game_over，最多 7 轮。
- 效果端到端验证：剥削（打出 2♥ → AI 付 1 进池，pool 4→5、AI gold 18→17）、损坏（6♦ 轮末移除，确认不进弃牌堆/不回抽牌堆）。
- **`python main.py` 实跑待用户在交互终端验证**（沙箱无 TTY）。
- 不变量重点测：轮末事件顺序、软 pass 收敛、栈模型可放牌判定、损坏移除、底注抽 0、21 决胜链。

---

## 风险与对策
| 风险 | 对策 |
|---|---|
| msvcrt 方向键多字节解析错 | 单测 `KeyResolver` + 真机点按验证 |
| 双宽字符错位 | 所有文本走 `put_text`，单测覆盖 |
| Tab 按住检测不准 | GetAsyncKeyState 最高位；首帧轮询节奏 0.015s |
| VT 启用失败 | fallback 路径不崩 |
| 百科输入闪烁 | 单元格 diff + 一次 write |
| 隐写花色映射错位 | `card_back.SUITS` 与 `cards.SUITS` 顺序不同，强制 `SUIT_TO_CODE` dict；单测覆盖 52 张 |
| 软 pass 死循环（R1） | 靠效果设计规避；系统不加 pass 取消上限。若实测出现，加每轮每玩家 pass 取消次数上限→硬 pass |
| 抽牌堆+弃牌堆双空（R2） | 袖子跨轮保留+损坏移除致总量递减；极端态兜底留待实测定义 |
| 多值 hand_score 选优错 | 单测覆盖 A=(1,11)、8|0、非正点数、多 A |
| 放牌时序错乱（效果在错误阶段触发） | 时序写进 §16.4 + 单测逐步断言 |
| 轮末事件顺序错 | 顺序写进 §14.3 + 单测逐步断言 |
