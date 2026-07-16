# PyConsole Framework — 实施计划 (PLAN)

> **状态**：阶段 0–4 已完成并测试通过（105 个 unittest 全绿）。阶段 5 为实跑验证。
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
| 抽牌锁定被绕过 | `_can_pass`/`_can_play_sleeve` 守卫 + `_after_play` 唯一清零点；行为单测覆盖 |
| AI 死循环（抽后无处放/一直会爆） | 桌满强制 pass；抽到不爆即打出；`test_game21_advance_ai_to_settled` 守底 |
