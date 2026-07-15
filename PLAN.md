# PyConsole Framework — 实施计划 (PLAN)

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

---

## 阶段 4：入口与收尾

**4.1 `main.py`**
- `enable_vt` → `hide_cursor` → `App().run()`，try/except KeyboardInterrupt，finally `cleanup`。

**4.2 `README.md`**
- 运行方式、架构图（DESIGN §3）、如何加新场景/新键/新百科条目、键绑定 json 说明、限制说明。

**4.3 `requirements.txt`**：空文件 + 注释"零依赖，仅标准库"。

---

## 阶段 5：验证

- `python -m unittest discover -s pyconsole/tests -v` 全绿。
- `python main.py` 实跑：主菜单、H 进百科、输入实时搜索、↑↓ 切详情、PgUp/PgDn 滚详情、Esc 退、按住 Tab 看状态总览、Esc/正常退出无残留。
- （实跑需真实终端交互，main 跑起来会阻塞，验证以 unittest + 静态走查为主，必要时后台启动数秒后 kill 观察无崩溃。）

---

## 风险与对策
| 风险 | 对策 |
|---|---|
| msvcrt 方向键多字节解析错 | 单测 `KeyResolver` + 真机点按验证 |
| 双宽字符错位 | 所有文本走 `put_text`，单测覆盖 |
| Tab 按住检测不准 | GetAsyncKeyState 最高位；首帧轮询节奏 0.015s |
| VT 启用失败 | fallback 路径不崩 |
| 百科输入闪烁 | 单元格 diff + 一次 write |
